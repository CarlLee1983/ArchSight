// Package e2e exercises the full read-only observation flow against a real IPC
// server over a Unix Domain Socket: open a synthetic workspace, search it, open
// a file, request a definition through a fake language server, then prove the
// language server idles out — all without writing into the workspace and without
// starting any language server during workspace load.
package e2e

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/cmg/archsight/core/internal/fixtures"
	"github.com/cmg/archsight/core/internal/ipc"
	"github.com/cmg/archsight/core/internal/lsp"
	"github.com/cmg/archsight/core/internal/search"
)

func TestEndToEndReadOnlyFlow(t *testing.T) {
	rgPath, err := exec.LookPath("rg")
	if err != nil {
		t.Skip("ripgrep (rg) not installed; skipping end-to-end search flow")
	}

	wsRoot := t.TempDir()
	summary, err := fixtures.Generate(wsRoot, fixtures.GenerateOptions{Dirs: 3, FilesPerDir: 3})
	if err != nil {
		t.Fatalf("fixtures.Generate returned error: %v", err)
	}

	before, err := fixtures.Manifest(wsRoot)
	if err != nil {
		t.Fatalf("Manifest returned error: %v", err)
	}

	idleNow := time.Date(2026, 6, 5, 12, 0, 0, 0, time.UTC)
	currentNow := idleNow
	navigator := lsp.NewManager(lsp.Options{
		IdleTimeout: time.Minute,
		Now:         func() time.Time { return currentNow },
		Registry: map[string]lsp.ServerConfig{
			"go": fakeLSPServerConfig(wsRoot),
		},
	})

	socketPath := tempSocketPath(t)
	server := ipc.NewServer(ipc.Config{
		SocketPath: socketPath,
		Version:    "e2e-test",
		Searcher:   search.NewRipgrepSearcher(search.Options{Path: rgPath}),
		Navigator:  navigator,
	})
	serveErr := make(chan error, 1)
	go func() { serveErr <- server.ListenAndServe() }()
	t.Cleanup(func() {
		_ = server.Shutdown()
		if err := <-serveErr; err != nil {
			t.Errorf("ListenAndServe returned error: %v", err)
		}
	})

	client := dial(t, socketPath)
	defer client.Close()

	// health
	health := client.call(t, "health", map[string]any{})
	if !health.OK {
		t.Fatalf("health failed: %+v", health.Error)
	}

	// openWorkspace
	open := client.call(t, "openWorkspace", map[string]any{"roots": []string{wsRoot}})
	if !open.OK {
		t.Fatalf("openWorkspace failed: %+v", open.Error)
	}
	var opened struct {
		WorkspaceID string `json:"workspaceId"`
	}
	open.decode(t, &opened)
	if opened.WorkspaceID == "" {
		t.Fatal("expected a workspace id")
	}

	// listTree until ready
	var rootID string
	deadline := time.Now().Add(5 * time.Second)
	for {
		tree := client.call(t, "listTree", map[string]any{"workspaceId": opened.WorkspaceID})
		if !tree.OK {
			t.Fatalf("listTree failed: %+v", tree.Error)
		}
		var listed struct {
			Status string `json:"status"`
			Roots  []struct {
				ID string `json:"id"`
			} `json:"roots"`
			Entries []json.RawMessage `json:"entries"`
		}
		tree.decode(t, &listed)
		if listed.Status == "ready" {
			if len(listed.Roots) == 0 {
				t.Fatal("expected at least one root")
			}
			rootID = listed.Roots[0].ID
			if len(listed.Entries) < summary.Files {
				t.Fatalf("expected at least %d entries, got %d", summary.Files, len(listed.Entries))
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("workspace never became ready, last status %q", listed.Status)
		}
		time.Sleep(10 * time.Millisecond)
	}

	// No language server may start during workspace load.
	if navigator.ActiveCount() != 0 {
		t.Fatalf("expected no language server after workspace load, got %d active", navigator.ActiveCount())
	}

	// search returns one match per generated needle.
	searchResp := client.call(t, "search", map[string]any{
		"workspaceId": opened.WorkspaceID,
		"pattern":     fixtures.NeedleToken,
	})
	if !searchResp.OK {
		t.Fatalf("search failed: %+v", searchResp.Error)
	}
	var searched struct {
		Matches []struct {
			Path string `json:"path"`
		} `json:"matches"`
	}
	searchResp.decode(t, &searched)
	if len(searched.Matches) != summary.Needles {
		t.Fatalf("expected %d search matches, got %d", summary.Needles, len(searched.Matches))
	}

	// openFile returns read-only content for an anchor file.
	openFile := client.call(t, "openFile", map[string]any{
		"workspaceId": opened.WorkspaceID,
		"rootId":      rootID,
		"path":        "main.go",
	})
	if !openFile.OK {
		t.Fatalf("openFile failed: %+v", openFile.Error)
	}
	var file struct {
		Language string `json:"language"`
		Content  string `json:"content"`
	}
	openFile.decode(t, &file)
	if !strings.Contains(file.Content, "func main") {
		t.Fatalf("expected main.go content, got %q", file.Content)
	}

	// definition starts exactly one language server lazily.
	def := client.call(t, "definition", map[string]any{
		"workspaceId": opened.WorkspaceID,
		"rootId":      rootID,
		"path":        "main.go",
		"line":        4,
		"column":      2,
	})
	if !def.OK {
		t.Fatalf("definition failed: %+v", def.Error)
	}
	var navResult struct {
		Locations []struct {
			Path string `json:"path"`
		} `json:"locations"`
	}
	def.decode(t, &navResult)
	if len(navResult.Locations) != 1 || navResult.Locations[0].Path != "target.go" {
		t.Fatalf("expected definition at target.go, got %+v", navResult.Locations)
	}
	if navigator.ActiveCount() != 1 {
		t.Fatalf("expected one active language server after definition, got %d", navigator.ActiveCount())
	}

	// Idle out: advance time past the idle timeout and run cleanup.
	currentNow = idleNow.Add(2 * time.Minute)
	navigator.StopIdle()
	if navigator.ActiveCount() != 0 {
		t.Fatalf("expected language server to idle out, got %d active", navigator.ActiveCount())
	}

	// The whole flow must not have written anything into the workspace.
	after, err := fixtures.Manifest(wsRoot)
	if err != nil {
		t.Fatalf("Manifest returned error: %v", err)
	}
	if diff := fixtures.DiffManifests(before, after); !diff.Empty() {
		t.Fatalf("workspace was modified: %s", diff)
	}
}

// --- IPC test client -------------------------------------------------------

type ipcClient struct {
	conn   net.Conn
	reader *bufio.Reader
	nextID int
}

type ipcResponse struct {
	ID     string          `json:"id"`
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result"`
	Error  *struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func (r ipcResponse) decode(t *testing.T, target any) {
	t.Helper()
	if err := json.Unmarshal(r.Result, target); err != nil {
		t.Fatalf("decode result: %v", err)
	}
}

func (c *ipcClient) call(t *testing.T, method string, params map[string]any) ipcResponse {
	t.Helper()
	c.nextID++
	id := fmt.Sprintf("req_%d", c.nextID)
	payload, err := json.Marshal(map[string]any{"id": id, "method": method, "params": params})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}
	if _, err := c.conn.Write(append(payload, '\n')); err != nil {
		t.Fatalf("write request: %v", err)
	}
	line, err := c.reader.ReadBytes('\n')
	if err != nil {
		t.Fatalf("read response: %v", err)
	}
	var resp ipcResponse
	if err := json.Unmarshal(line, &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return resp
}

func (c *ipcClient) Close() { _ = c.conn.Close() }

func dial(t *testing.T, socketPath string) *ipcClient {
	t.Helper()
	var lastErr error
	for range 100 {
		conn, err := net.Dial("unix", socketPath)
		if err == nil {
			return &ipcClient{conn: conn, reader: bufio.NewReader(conn)}
		}
		lastErr = err
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("failed to dial unix socket: %v", lastErr)
	return nil
}

func tempSocketPath(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "as-e2e-*")
	if err != nil {
		t.Fatalf("MkdirTemp returned error: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	return filepath.Join(dir, "core.sock")
}

// --- Fake language server --------------------------------------------------

func fakeLSPServerConfig(rootPath string) lsp.ServerConfig {
	return lsp.ServerConfig{
		Command: os.Args[0],
		Args:    []string{"-test.run=TestFakeLSPServer", "--", rootPath},
	}
}

// TestFakeLSPServer is a minimal stdio JSON-RPC server used as a fake language
// server. It only runs when invoked as a subprocess with the "--" sentinel.
func TestFakeLSPServer(t *testing.T) {
	if len(os.Args) < 2 || os.Args[len(os.Args)-2] != "--" {
		return
	}
	rootPath := os.Args[len(os.Args)-1]

	for {
		msg, err := readLSPMessage(os.Stdin)
		if err != nil {
			if err == io.EOF {
				return
			}
			fmt.Fprintf(os.Stderr, "read message: %v\n", err)
			os.Exit(2)
		}
		var req struct {
			ID     int             `json:"id"`
			Method string          `json:"method"`
			Params json.RawMessage `json:"params"`
		}
		if err := json.Unmarshal(msg, &req); err != nil {
			fmt.Fprintf(os.Stderr, "decode request: %v\n", err)
			os.Exit(2)
		}

		switch req.Method {
		case "initialize":
			writeLSPMessage(map[string]any{
				"jsonrpc": "2.0",
				"id":      req.ID,
				"result":  map[string]any{"capabilities": map[string]any{}},
			})
		case "initialized", "textDocument/didOpen":
		case "textDocument/definition":
			writeLSPMessage(map[string]any{
				"jsonrpc": "2.0",
				"id":      req.ID,
				"result": map[string]any{
					"uri": fileURI(filepath.Join(rootPath, "target.go")),
					"range": map[string]any{
						"start": map[string]any{"line": 2, "character": 5},
						"end":   map[string]any{"line": 2, "character": 11},
					},
				},
			})
		case "shutdown":
			writeLSPMessage(map[string]any{"jsonrpc": "2.0", "id": req.ID, "result": nil})
		default:
			if req.ID != 0 {
				writeLSPMessage(map[string]any{
					"jsonrpc": "2.0",
					"id":      req.ID,
					"error":   map[string]any{"code": -32601, "message": "unsupported: " + req.Method},
				})
			}
		}
	}
}

func readLSPMessage(r io.Reader) ([]byte, error) {
	var length int
	for {
		var line string
		for {
			var b [1]byte
			n, err := r.Read(b[:])
			if err != nil {
				return nil, err
			}
			if n == 0 {
				continue
			}
			line += string(b[0])
			if strings.HasSuffix(line, "\r\n") {
				break
			}
		}
		line = strings.TrimSuffix(line, "\r\n")
		if line == "" {
			break
		}
		_, _ = fmt.Sscanf(line, "Content-Length: %d", &length)
	}
	if length == 0 {
		return nil, fmt.Errorf("missing Content-Length")
	}
	body := make([]byte, length)
	_, err := io.ReadFull(r, body)
	return body, err
}

func writeLSPMessage(payload any) {
	encoded, err := json.Marshal(payload)
	if err != nil {
		fmt.Fprintf(os.Stderr, "encode response: %v\n", err)
		os.Exit(2)
	}
	_, _ = fmt.Fprintf(os.Stdout, "Content-Length: %d\r\n\r\n%s", len(encoded), encoded)
}

func fileURI(path string) string {
	return (&url.URL{Scheme: "file", Path: path}).String()
}
