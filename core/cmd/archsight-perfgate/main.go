// Command archsight-perfgate is the Phase 9 performance and reliability gate. It
// launches a real archsight-core binary against a large synthetic workspace and
// measures startup latency, scan time, idle resident memory against the 50MB
// target, child-process count, search cancellation behavior, and orphan
// processes after shutdown. It also proves the workspace is never written to.
//
// Correctness failures (scan never ready, search mismatch, workspace modified,
// orphan processes, socket left behind) exit non-zero. Exceeding the memory
// budget is reported as a warning unless --strict is set.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/cmg/archsight/core/internal/fixtures"
	"github.com/cmg/archsight/core/internal/perf"
)

const memoryBudgetKB = 50 * 1024 // M <= 50MB idle static memory target.

type options struct {
	corePath    string
	rgPath      string
	dirs        int
	filesPerDir int
	budgetKB    int
	outPath     string
	strict      bool
	keepWorkdir bool
}

func main() {
	opts := parseFlags()
	report, err := run(opts)
	if report != nil {
		report.print(os.Stdout)
		if opts.outPath != "" {
			if writeErr := report.writeJSON(opts.outPath); writeErr != nil {
				fmt.Fprintf(os.Stderr, "perfgate: write report: %v\n", writeErr)
			}
		}
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "perfgate: %v\n", err)
		os.Exit(1)
	}
	if report != nil && !report.passed(opts.strict) {
		os.Exit(1)
	}
}

func parseFlags() options {
	var opts options
	flag.StringVar(&opts.corePath, "core", "", "path to the built archsight-core binary (required)")
	flag.StringVar(&opts.rgPath, "rg", "", "path to ripgrep; falls back to PATH lookup")
	flag.IntVar(&opts.dirs, "dirs", 200, "number of synthetic package directories")
	flag.IntVar(&opts.filesPerDir, "files", 25, "number of leaf files per directory")
	flag.IntVar(&opts.budgetKB, "memory-budget-kb", memoryBudgetKB, "idle resident memory budget in kilobytes")
	flag.StringVar(&opts.outPath, "out", "", "optional path to write a JSON report")
	flag.BoolVar(&opts.strict, "strict", false, "fail when idle memory exceeds the budget")
	flag.BoolVar(&opts.keepWorkdir, "keep-workdir", false, "keep the synthetic workspace for inspection")
	flag.Parse()
	return opts
}

// Report captures every measured metric and check outcome.
type Report struct {
	WorkspaceFiles     int    `json:"workspaceFiles"`
	WorkspaceDirs      int    `json:"workspaceDirs"`
	StartupMillis      int64  `json:"startupMillis"`
	ScanMillis         int64  `json:"scanMillis"`
	TreeEntries        int    `json:"treeEntries"`
	IdleRSSKilobytes   int    `json:"idleRssKilobytes"`
	MemoryBudgetKB     int    `json:"memoryBudgetKb"`
	MemoryWithinTarget bool   `json:"memoryWithinTarget"`
	ChildProcsAtIdle   int    `json:"childProcsAtIdle"`
	NoLSPOnLoad        bool   `json:"noLspOnLoad"`
	SearchMatches      int    `json:"searchMatches"`
	SearchExpected     int    `json:"searchExpected"`
	SearchOK           bool   `json:"searchOk"`
	CancelOutcome      string `json:"cancelOutcome"`
	CancelLatencyMs    int64  `json:"cancelLatencyMs"`
	SocketRemoved      bool   `json:"socketRemoved"`
	SurvivingProcs     int    `json:"survivingProcs"`
	NoOrphanProcs      bool   `json:"noOrphanProcs"`
	WorkspaceReadOnly  bool   `json:"workspaceReadOnly"`
	ReadOnlyDetail     string `json:"readOnlyDetail"`
}

func (r *Report) passed(strict bool) bool {
	ok := r.NoLSPOnLoad &&
		r.SearchOK &&
		r.SocketRemoved &&
		r.NoOrphanProcs &&
		r.WorkspaceReadOnly
	if strict {
		ok = ok && r.MemoryWithinTarget
	}
	return ok
}

func run(opts options) (*Report, error) {
	if opts.corePath == "" {
		return nil, fmt.Errorf("--core is required")
	}
	if _, err := os.Stat(opts.corePath); err != nil {
		return nil, fmt.Errorf("core binary not found: %w", err)
	}

	rgPath := opts.rgPath
	if rgPath == "" {
		if found, err := exec.LookPath("rg"); err == nil {
			rgPath = found
		} else {
			return nil, fmt.Errorf("ripgrep (rg) not found; install it or pass --rg")
		}
	}

	workdir, err := os.MkdirTemp("/tmp", "as-perf-*")
	if err != nil {
		return nil, err
	}
	if opts.keepWorkdir {
		fmt.Fprintf(os.Stderr, "perfgate: keeping workdir %s\n", workdir)
	} else {
		defer os.RemoveAll(workdir)
	}

	wsRoot := filepath.Join(workdir, "workspace")
	summary, err := fixtures.Generate(wsRoot, fixtures.GenerateOptions{Dirs: opts.dirs, FilesPerDir: opts.filesPerDir})
	if err != nil {
		return nil, fmt.Errorf("generate workspace: %w", err)
	}
	before, err := fixtures.Manifest(wsRoot)
	if err != nil {
		return nil, fmt.Errorf("manifest before: %w", err)
	}

	report := &Report{
		WorkspaceFiles: summary.Files,
		WorkspaceDirs:  summary.Dirs,
		SearchExpected: summary.Needles,
		MemoryBudgetKB: opts.budgetKB,
	}

	socketPath := filepath.Join(workdir, "core.sock")
	cmd := exec.Command(opts.corePath, "--socket", socketPath)
	cmd.Env = append(os.Environ(), "ARCHSIGHT_RG_PATH="+rgPath)
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	// Run the core as its own process-group leader so the orphan check can verify
	// the whole group is empty after the core exits, regardless of reparenting.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	launchedAt := time.Now()
	if err := cmd.Start(); err != nil {
		return report, fmt.Errorf("start core: %w", err)
	}
	corePID := cmd.Process.Pid // also the process-group id thanks to Setpgid.
	coreExited := make(chan error, 1)
	go func() { coreExited <- cmd.Wait() }()
	exited := false
	defer func() {
		// Safety net: if we abort before a graceful shutdown, kill the whole group
		// and drain the waiter so we never leak the core or its children.
		if !exited {
			_ = syscall.Kill(-corePID, syscall.SIGKILL)
			<-coreExited
		}
	}()

	// startup: time until health responds.
	client, startupErr := dialWithHealth(socketPath, launchedAt, 10*time.Second)
	if startupErr != nil {
		return report, fmt.Errorf("await health: %w", startupErr)
	}
	report.StartupMillis = time.Since(launchedAt).Milliseconds()
	defer client.Close()

	// openWorkspace + scan
	open, err := client.call("openWorkspace", map[string]any{"roots": []string{wsRoot}})
	if err != nil || !open.OK {
		return report, fmt.Errorf("openWorkspace failed: %v %+v", err, open.Error)
	}
	var opened struct {
		WorkspaceID string `json:"workspaceId"`
	}
	open.decode(&opened)

	scanStart := time.Now()
	_, entries, err := awaitReady(client, opened.WorkspaceID, 30*time.Second)
	if err != nil {
		return report, err
	}
	report.ScanMillis = time.Since(scanStart).Milliseconds()
	report.TreeEntries = entries

	// idle memory + child processes (no LSP, no in-flight rg)
	if rss, err := perf.ProcessRSSKilobytes(corePID); err == nil {
		report.IdleRSSKilobytes = rss
		report.MemoryWithinTarget = rss <= opts.budgetKB
	} else {
		fmt.Fprintf(os.Stderr, "perfgate: rss measurement failed: %v\n", err)
	}
	descendants, err := perf.DescendantPIDs(corePID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "perfgate: descendant scan failed: %v\n", err)
	}
	report.ChildProcsAtIdle = len(descendants)
	report.NoLSPOnLoad = len(descendants) == 0

	// search
	searchResp, err := client.call("search", map[string]any{
		"workspaceId": opened.WorkspaceID,
		"pattern":     fixtures.NeedleToken,
	})
	if err != nil || !searchResp.OK {
		return report, fmt.Errorf("search failed: %v %+v", err, searchResp.Error)
	}
	var searched struct {
		Matches []json.RawMessage `json:"matches"`
	}
	searchResp.decode(&searched)
	report.SearchMatches = len(searched.Matches)
	report.SearchOK = report.SearchMatches == report.SearchExpected

	// search cancellation (best effort): broad search on one connection, cancel
	// from another mid-flight.
	report.CancelOutcome, report.CancelLatencyMs = measureCancellation(socketPath, opened.WorkspaceID)

	// shutdown + orphan check: SIGTERM only the core, then confirm its process
	// group is empty so no child (rg/LSP) was left orphaned.
	_ = cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-coreExited:
		exited = true
	case <-time.After(5 * time.Second):
		_ = syscall.Kill(-corePID, syscall.SIGKILL)
		<-coreExited
		exited = true
		return report, fmt.Errorf("core did not exit on SIGTERM within 5s")
	}

	survivors, err := perf.ProcessGroupPIDs(corePID)
	if err != nil {
		// A failed orphan scan must not silently pass the gate.
		fmt.Fprintf(os.Stderr, "perfgate: orphan scan failed: %v\n", err)
		report.NoOrphanProcs = false
	} else {
		report.SurvivingProcs = len(survivors)
		report.NoOrphanProcs = len(survivors) == 0
		if len(survivors) > 0 {
			_ = syscall.Kill(-corePID, syscall.SIGKILL) // clean up so we don't leak.
		}
	}
	if _, err := os.Stat(socketPath); os.IsNotExist(err) {
		report.SocketRemoved = true
	}

	// read-only proof
	after, err := fixtures.Manifest(wsRoot)
	if err != nil {
		return report, fmt.Errorf("manifest after: %w", err)
	}
	diff := fixtures.DiffManifests(before, after)
	report.WorkspaceReadOnly = diff.Empty()
	report.ReadOnlyDetail = diff.String()

	return report, nil
}

func measureCancellation(socketPath, workspaceID string) (string, int64) {
	searchClient, err := dial(socketPath)
	if err != nil {
		return "dial_failed", 0
	}
	defer searchClient.Close()
	cancelClient, err := dial(socketPath)
	if err != nil {
		return "dial_failed", 0
	}
	defer cancelClient.Close()

	reqID, err := searchClient.send("search", map[string]any{
		"workspaceId": workspaceID,
		"pattern":     "Symbol",
	})
	if err != nil {
		return "send_failed", 0
	}

	cancelSentAt := time.Now()
	if _, err := cancelClient.call("cancel", map[string]any{"targetId": reqID}); err != nil {
		return "cancel_failed", 0
	}

	resp, err := searchClient.read()
	latency := time.Since(cancelSentAt).Milliseconds()
	if err != nil {
		return "read_failed", latency
	}
	if !resp.OK && resp.Error != nil && resp.Error.Code == "context_canceled" {
		return "canceled", latency
	}
	return "completed_before_cancel", latency
}

func (r *Report) print(w io.Writer) {
	status := func(ok bool) string {
		if ok {
			return "PASS"
		}
		return "FAIL"
	}
	memStatus := "PASS"
	if !r.MemoryWithinTarget {
		memStatus = "OVER"
	}
	fmt.Fprintf(w, "\n== ArchSight Phase 9 Performance & Reliability Gate ==\n")
	fmt.Fprintf(w, "Synthetic workspace : %d files in %d dirs (%d tree entries)\n", r.WorkspaceFiles, r.WorkspaceDirs, r.TreeEntries)
	fmt.Fprintf(w, "Startup latency     : %d ms\n", r.StartupMillis)
	fmt.Fprintf(w, "Scan time           : %d ms\n", r.ScanMillis)
	fmt.Fprintf(w, "Idle memory         : %d KB (%.1f MB) budget %d KB [%s]\n",
		r.IdleRSSKilobytes, float64(r.IdleRSSKilobytes)/1024.0, r.MemoryBudgetKB, memStatus)
	fmt.Fprintf(w, "Child procs at idle : %d [no-LSP-on-load %s]\n", r.ChildProcsAtIdle, status(r.NoLSPOnLoad))
	fmt.Fprintf(w, "Search matches      : %d / %d [%s]\n", r.SearchMatches, r.SearchExpected, status(r.SearchOK))
	fmt.Fprintf(w, "Search cancellation : %s (%d ms after cancel) [best-effort, non-gating]\n", r.CancelOutcome, r.CancelLatencyMs)
	fmt.Fprintf(w, "Socket removed      : %s\n", status(r.SocketRemoved))
	fmt.Fprintf(w, "No orphan processes : %s (%d survivors)\n", status(r.NoOrphanProcs), r.SurvivingProcs)
	fmt.Fprintf(w, "Workspace read-only : %s (%s)\n", status(r.WorkspaceReadOnly), r.ReadOnlyDetail)
	fmt.Fprintf(w, "\n")
}

func (r *Report) writeJSON(path string) error {
	data, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}

// --- IPC client ------------------------------------------------------------

// clientSeq gives every connection a distinct request-ID namespace. The server
// tracks active requests by a global id, so the cancel-from-another-connection
// path must not reuse an id another connection already used.
var clientSeq atomic.Int64

type client struct {
	conn   net.Conn
	reader *bufio.Reader
	prefix int64
	nextID int
}

type response struct {
	ID     string          `json:"id"`
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result"`
	Error  *struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func (r response) decode(target any) {
	_ = json.Unmarshal(r.Result, target)
}

func dial(socketPath string) (*client, error) {
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		return nil, err
	}
	return &client{conn: conn, reader: bufio.NewReader(conn), prefix: clientSeq.Add(1)}, nil
}

func dialWithHealth(socketPath string, since time.Time, timeout time.Duration) (*client, error) {
	deadline := since.Add(timeout)
	var lastErr error
	for time.Now().Before(deadline) {
		c, err := dial(socketPath)
		if err != nil {
			lastErr = err
			time.Sleep(20 * time.Millisecond)
			continue
		}
		resp, err := c.call("health", map[string]any{})
		if err == nil && resp.OK {
			return c, nil
		}
		lastErr = err
		c.Close()
		time.Sleep(20 * time.Millisecond)
	}
	return nil, fmt.Errorf("health never succeeded: %v", lastErr)
}

func (c *client) send(method string, params map[string]any) (string, error) {
	c.nextID++
	id := fmt.Sprintf("c%d_req_%d", c.prefix, c.nextID)
	payload, err := json.Marshal(map[string]any{"id": id, "method": method, "params": params})
	if err != nil {
		return "", err
	}
	if _, err := c.conn.Write(append(payload, '\n')); err != nil {
		return "", err
	}
	return id, nil
}

func (c *client) read() (response, error) {
	line, err := c.reader.ReadBytes('\n')
	if err != nil {
		return response{}, err
	}
	var resp response
	if err := json.Unmarshal(line, &resp); err != nil {
		return response{}, err
	}
	return resp, nil
}

func (c *client) call(method string, params map[string]any) (response, error) {
	if _, err := c.send(method, params); err != nil {
		return response{}, err
	}
	return c.read()
}

func (c *client) Close() { _ = c.conn.Close() }

func awaitReady(c *client, workspaceID string, timeout time.Duration) (string, int, error) {
	deadline := time.Now().Add(timeout)
	for {
		tree, err := c.call("listTree", map[string]any{"workspaceId": workspaceID})
		if err != nil || !tree.OK {
			return "", 0, fmt.Errorf("listTree failed: %v %+v", err, tree.Error)
		}
		var listed struct {
			Status string `json:"status"`
			Roots  []struct {
				ID string `json:"id"`
			} `json:"roots"`
			Entries []json.RawMessage `json:"entries"`
			Error   string            `json:"error"`
		}
		tree.decode(&listed)
		switch listed.Status {
		case "ready":
			if len(listed.Roots) == 0 {
				return "", 0, fmt.Errorf("ready workspace has no roots")
			}
			return listed.Roots[0].ID, len(listed.Entries), nil
		case "failed":
			return "", 0, fmt.Errorf("workspace scan failed: %s", listed.Error)
		case "canceled":
			return "", 0, fmt.Errorf("workspace scan canceled")
		}
		if time.Now().After(deadline) {
			return "", 0, fmt.Errorf("workspace never became ready, last status %q", listed.Status)
		}
		time.Sleep(15 * time.Millisecond)
	}
}
