package lsp

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/cmg/archsight/core/internal/workspace"
)

const defaultIdleTimeout = 5 * time.Minute

type ServerConfig struct {
	Command string
	Args    []string
}

type Options struct {
	Registry     map[string]ServerConfig
	IdleTimeout  time.Duration
	Now          func() time.Time
	StartProcess func(context.Context, string, ...string) (*exec.Cmd, error)
}

type Manager struct {
	mu           sync.Mutex
	registry     map[string]ServerConfig
	idleTimeout  time.Duration
	now          func() time.Time
	startProcess func(context.Context, string, ...string) (*exec.Cmd, error)
	servers      map[string]*serverProcess
}

type Navigator interface {
	Definition(context.Context, Request) ([]Location, error)
	References(context.Context, Request) ([]Location, error)
	DocumentSymbol(context.Context, Request) ([]Symbol, error)
}

type Request struct {
	Root     workspace.Root
	Language string
	Path     string
	Line     int
	Column   int
}

type Location struct {
	RootID      string `json:"rootId"`
	RootPath    string `json:"rootPath"`
	Path        string `json:"path"`
	StartLine   int    `json:"startLine"`
	StartColumn int    `json:"startColumn"`
	EndLine     int    `json:"endLine"`
	EndColumn   int    `json:"endColumn"`
}

// Symbol is one entry of a file's document outline, flattened from the LSP
// response. Depth records nesting (0 = top level) so the client can indent a
// hierarchical outline without re-deriving structure.
type Symbol struct {
	Name   string `json:"name"`
	Kind   int    `json:"kind"`
	Detail string `json:"detail,omitempty"`
	Line   int    `json:"line"`
	Column int    `json:"column"`
	Depth  int    `json:"depth"`
}

type Error struct {
	Code    string
	Message string
}

func (e *Error) Error() string {
	return e.Code + ": " + e.Message
}

type serverProcess struct {
	cmd         *exec.Cmd
	stdin       io.WriteCloser
	reader      *bufio.Reader
	cancel      context.CancelFunc
	lastRequest time.Time
	nextID      int
}

func NewManager(options Options) *Manager {
	idleTimeout := options.IdleTimeout
	if idleTimeout == 0 {
		idleTimeout = defaultIdleTimeout
	}
	now := options.Now
	if now == nil {
		now = time.Now
	}
	startProcess := options.StartProcess
	if startProcess == nil {
		startProcess = func(ctx context.Context, command string, args ...string) (*exec.Cmd, error) {
			return exec.CommandContext(ctx, command, args...), nil
		}
	}
	registry := options.Registry
	if registry == nil {
		registry = defaultRegistry()
	}
	return &Manager{
		registry:     registry,
		idleTimeout:  idleTimeout,
		now:          now,
		startProcess: startProcess,
		servers:      make(map[string]*serverProcess),
	}
}

func (m *Manager) Definition(ctx context.Context, req Request) ([]Location, error) {
	server, err := m.ensureServer(ctx, req)
	if err != nil {
		return nil, err
	}
	return m.navigation(ctx, server, req, "textDocument/definition", nil)
}

func (m *Manager) References(ctx context.Context, req Request) ([]Location, error) {
	server, err := m.ensureServer(ctx, req)
	if err != nil {
		return nil, err
	}
	return m.navigation(ctx, server, req, "textDocument/references", map[string]any{
		"context": map[string]any{"includeDeclaration": true},
	})
}

// DocumentSymbol returns the file's outline. Like Definition/References it lazily
// starts the language server and opens the file; unlike them it needs no caret
// position because the request is whole-file.
func (m *Manager) DocumentSymbol(ctx context.Context, req Request) ([]Symbol, error) {
	server, err := m.ensureServer(ctx, req)
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if err := didOpen(server, req); err != nil {
		return nil, err
	}
	params := map[string]any{
		"textDocument": map[string]any{"uri": fileURI(filepath.Join(req.Root.Path, req.Path))},
	}
	result, err := request(server, "textDocument/documentSymbol", params)
	if err != nil {
		return nil, err
	}
	return parseSymbols(result), nil
}

func (m *Manager) StopIdle() {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := m.now()
	for key, server := range m.servers {
		if now.Sub(server.lastRequest) <= m.idleTimeout {
			continue
		}
		stopServer(server)
		delete(m.servers, key)
	}
}

func (m *Manager) Shutdown() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for key, server := range m.servers {
		stopServer(server)
		delete(m.servers, key)
	}
}

func (m *Manager) ActiveCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()

	return len(m.servers)
}

func (m *Manager) ensureServer(ctx context.Context, req Request) (*serverProcess, error) {
	if req.Root.ID == "" || req.Root.Path == "" || req.Language == "" || req.Path == "" {
		return nil, &Error{Code: "invalid_params", Message: "root, language, and path are required"}
	}
	config, ok := m.registry[req.Language]
	if !ok || config.Command == "" {
		return nil, &Error{Code: "unsupported_language", Message: "No language server configured for: " + req.Language}
	}

	key := req.Root.ID + ":" + req.Language
	m.mu.Lock()
	defer m.mu.Unlock()

	if server, ok := m.servers[key]; ok {
		server.lastRequest = m.now()
		return server, nil
	}

	processCtx, cancel := context.WithCancel(context.Background())
	cmd, err := m.startProcess(processCtx, config.Command, config.Args...)
	if err != nil {
		cancel()
		return nil, err
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		cancel()
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		_ = stdin.Close()
		cancel()
		return nil, err
	}
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		cancel()
		return nil, err
	}
	server := &serverProcess{
		cmd:         cmd,
		stdin:       stdin,
		reader:      bufio.NewReader(stdout),
		cancel:      cancel,
		lastRequest: m.now(),
	}
	if err := initialize(ctx, server, req.Root); err != nil {
		stopServer(server)
		return nil, err
	}
	m.servers[key] = server
	return server, ctx.Err()
}

func (m *Manager) navigation(ctx context.Context, server *serverProcess, req Request, method string, extra map[string]any) ([]Location, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if err := didOpen(server, req); err != nil {
		return nil, err
	}
	params := map[string]any{
		"textDocument": map[string]any{"uri": fileURI(filepath.Join(req.Root.Path, req.Path))},
		"position": map[string]any{
			"line":      req.Line - 1,
			"character": req.Column - 1,
		},
	}
	for key, value := range extra {
		params[key] = value
	}
	result, err := request(server, method, params)
	if err != nil {
		return nil, err
	}
	return parseLocations(req.Root, result)
}

func initialize(ctx context.Context, server *serverProcess, root workspace.Root) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	params := map[string]any{
		"processId": os.Getpid(),
		"rootUri":   fileURI(root.Path),
		"capabilities": map[string]any{
			"textDocument": map[string]any{
				"definition":     map[string]any{},
				"references":     map[string]any{},
				"documentSymbol": map[string]any{},
			},
		},
	}
	if _, err := request(server, "initialize", params); err != nil {
		return err
	}
	return notify(server, "initialized", map[string]any{})
}

func didOpen(server *serverProcess, req Request) error {
	fullPath := filepath.Join(req.Root.Path, req.Path)
	content, err := os.ReadFile(fullPath)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return notify(server, "textDocument/didOpen", map[string]any{
		"textDocument": map[string]any{
			"uri":        fileURI(fullPath),
			"languageId": req.Language,
			"version":    1,
			"text":       string(content),
		},
	})
}

func request(server *serverProcess, method string, params any) (json.RawMessage, error) {
	server.nextID++
	id := server.nextID
	if err := writeMessage(server.stdin, map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"method":  method,
		"params":  params,
	}); err != nil {
		return nil, err
	}
	for {
		message, err := readMessage(server.reader)
		if err != nil {
			return nil, err
		}
		var resp struct {
			ID     int             `json:"id"`
			Result json.RawMessage `json:"result"`
			Error  *struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if err := json.Unmarshal(message, &resp); err != nil {
			return nil, err
		}
		if resp.ID != id {
			continue
		}
		if resp.Error != nil {
			return nil, &Error{Code: "lsp_error", Message: resp.Error.Message}
		}
		return resp.Result, nil
	}
}

func notify(server *serverProcess, method string, params any) error {
	return writeMessage(server.stdin, map[string]any{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
	})
}

func writeMessage(w io.Writer, payload any) error {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	if _, err := fmt.Fprintf(w, "Content-Length: %d\r\n\r\n", len(encoded)); err != nil {
		return err
	}
	_, err = w.Write(encoded)
	return err
}

func readMessage(reader *bufio.Reader) ([]byte, error) {
	length := 0
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			return nil, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		name, value, ok := strings.Cut(line, ":")
		if !ok || !strings.EqualFold(name, "Content-Length") {
			continue
		}
		parsed, err := strconv.Atoi(strings.TrimSpace(value))
		if err != nil {
			return nil, err
		}
		length = parsed
	}
	if length <= 0 {
		return nil, fmt.Errorf("missing Content-Length")
	}
	body := make([]byte, length)
	_, err := io.ReadFull(reader, body)
	return body, err
}

func parseLocations(root workspace.Root, result json.RawMessage) ([]Location, error) {
	if len(result) == 0 || string(result) == "null" {
		return []Location{}, nil
	}
	var single protocolLocation
	if err := json.Unmarshal(result, &single); err == nil && single.URI != "" {
		location, err := convertLocation(root, single)
		if err != nil {
			return nil, err
		}
		return []Location{location}, nil
	}
	var many []protocolLocation
	if err := json.Unmarshal(result, &many); err != nil {
		return nil, err
	}
	locations := make([]Location, 0, len(many))
	for _, item := range many {
		location, err := convertLocation(root, item)
		if err != nil {
			return nil, err
		}
		locations = append(locations, location)
	}
	return locations, nil
}

type protocolLocation struct {
	URI   string `json:"uri"`
	Range struct {
		Start struct {
			Line      int `json:"line"`
			Character int `json:"character"`
		} `json:"start"`
		End struct {
			Line      int `json:"line"`
			Character int `json:"character"`
		} `json:"end"`
	} `json:"range"`
}

func convertLocation(root workspace.Root, loc protocolLocation) (Location, error) {
	parsed, err := url.Parse(loc.URI)
	if err != nil {
		return Location{}, err
	}
	if parsed.Scheme != "file" {
		return Location{}, &Error{Code: "unsupported_uri", Message: "Only file URIs are supported: " + loc.URI}
	}
	rel, err := filepath.Rel(root.Path, parsed.Path)
	if err != nil {
		return Location{}, err
	}
	if rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return Location{}, &Error{Code: "outside_root", Message: "LSP location is outside workspace root: " + loc.URI}
	}
	return Location{
		RootID:      root.ID,
		RootPath:    root.Path,
		Path:        filepath.ToSlash(rel),
		StartLine:   loc.Range.Start.Line + 1,
		StartColumn: loc.Range.Start.Character + 1,
		EndLine:     loc.Range.End.Line + 1,
		EndColumn:   loc.Range.End.Character + 1,
	}, nil
}

type lspPosition struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

type lspRange struct {
	Start lspPosition `json:"start"`
	End   lspPosition `json:"end"`
}

// protocolDocumentSymbol is the hierarchical `DocumentSymbol` shape. SelectionRange
// is a pointer so its absence distinguishes this from the flat SymbolInformation.
type protocolDocumentSymbol struct {
	Name           string                   `json:"name"`
	Detail         string                   `json:"detail"`
	Kind           int                      `json:"kind"`
	Range          lspRange                 `json:"range"`
	SelectionRange *lspRange                `json:"selectionRange"`
	Children       []protocolDocumentSymbol `json:"children"`
}

type protocolSymbolInformation struct {
	Name     string `json:"name"`
	Kind     int    `json:"kind"`
	Location struct {
		URI   string   `json:"uri"`
		Range lspRange `json:"range"`
	} `json:"location"`
}

// parseSymbols handles both LSP documentSymbol shapes: hierarchical
// `DocumentSymbol[]` (flattened depth-first with depth tracking) and flat
// `SymbolInformation[]`. A null/empty result yields an empty slice.
func parseSymbols(result json.RawMessage) []Symbol {
	if len(result) == 0 || string(result) == "null" {
		return []Symbol{}
	}
	var hierarchical []protocolDocumentSymbol
	if err := json.Unmarshal(result, &hierarchical); err == nil &&
		len(hierarchical) > 0 && hierarchical[0].SelectionRange != nil {
		symbols := []Symbol{}
		for _, node := range hierarchical {
			flattenSymbol(node, 0, &symbols)
		}
		return symbols
	}
	var flat []protocolSymbolInformation
	if err := json.Unmarshal(result, &flat); err != nil {
		return []Symbol{}
	}
	symbols := make([]Symbol, 0, len(flat))
	for _, item := range flat {
		symbols = append(symbols, Symbol{
			Name:   item.Name,
			Kind:   item.Kind,
			Line:   item.Location.Range.Start.Line + 1,
			Column: item.Location.Range.Start.Character + 1,
		})
	}
	return symbols
}

func flattenSymbol(node protocolDocumentSymbol, depth int, out *[]Symbol) {
	position := node.Range.Start
	if node.SelectionRange != nil {
		position = node.SelectionRange.Start
	}
	*out = append(*out, Symbol{
		Name:   node.Name,
		Kind:   node.Kind,
		Detail: node.Detail,
		Line:   position.Line + 1,
		Column: position.Character + 1,
		Depth:  depth,
	})
	for _, child := range node.Children {
		flattenSymbol(child, depth+1, out)
	}
}

func fileURI(path string) string {
	return (&url.URL{Scheme: "file", Path: path}).String()
}

func stopServer(server *serverProcess) {
	if server.stdin != nil {
		_, _ = server.stdin.Write([]byte(`{"jsonrpc":"2.0","id":1,"method":"shutdown","params":null}` + "\n"))
		_ = server.stdin.Close()
	}
	if server.cancel != nil {
		server.cancel()
	}
	if server.cmd != nil && server.cmd.Process != nil {
		done := make(chan struct{})
		go func() {
			_ = server.cmd.Wait()
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(100 * time.Millisecond):
			_ = server.cmd.Process.Kill()
			<-done
		}
	}
}

func defaultRegistry() map[string]ServerConfig {
	registry := map[string]ServerConfig{}
	if path, err := exec.LookPath("gopls"); err == nil {
		registry["go"] = ServerConfig{Command: path}
	}
	if path, err := exec.LookPath("typescript-language-server"); err == nil {
		registry["typescript"] = ServerConfig{Command: path, Args: []string{"--stdio"}}
	}
	if path, err := exec.LookPath("sourcekit-lsp"); err == nil {
		registry["swift"] = ServerConfig{Command: path}
	}
	return registry
}

func AsError(err error, target **Error) bool {
	return errors.As(err, target)
}

func (m *Manager) String() string {
	return fmt.Sprintf("lsp.Manager(active=%d)", m.ActiveCount())
}
