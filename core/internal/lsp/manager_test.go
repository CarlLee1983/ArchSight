package lsp

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/cmg/archsight/core/internal/workspace"
)

func TestManagerDoesNotStartServerUntilNavigationRequest(t *testing.T) {
	root := workspace.Root{ID: "root_1", Path: t.TempDir()}
	config := fakeLSPServerConfig(t, root.Path)
	starts := 0
	manager := NewManager(Options{
		Registry: map[string]ServerConfig{
			"go": config,
		},
		StartProcess: func(ctx context.Context, command string, args ...string) (*exec.Cmd, error) {
			starts++
			return exec.CommandContext(ctx, command, args...), nil
		},
	})
	t.Cleanup(manager.Shutdown)

	if starts != 0 {
		t.Fatalf("expected no server starts before navigation, got %d", starts)
	}

	_, err := manager.Definition(context.Background(), Request{
		Root:     root,
		Language: "go",
		Path:     "main.go",
		Line:     1,
		Column:   1,
	})
	if err != nil {
		t.Fatalf("Definition returned error: %v", err)
	}
	if starts != 1 {
		t.Fatalf("expected one lazy server start, got %d", starts)
	}
}

func TestManagerReusesServerPerRootAndLanguage(t *testing.T) {
	starts := 0
	root := workspace.Root{ID: "root_1", Path: t.TempDir()}
	config := fakeLSPServerConfig(t, root.Path)
	manager := NewManager(Options{
		Registry: map[string]ServerConfig{
			"go": config,
		},
		StartProcess: func(ctx context.Context, command string, args ...string) (*exec.Cmd, error) {
			starts++
			return exec.CommandContext(ctx, command, args...), nil
		},
	})
	t.Cleanup(manager.Shutdown)

	for range 2 {
		_, err := manager.References(context.Background(), Request{
			Root:     root,
			Language: "go",
			Path:     "main.go",
			Line:     1,
			Column:   1,
		})
		if err != nil {
			t.Fatalf("References returned error: %v", err)
		}
	}
	if starts != 1 {
		t.Fatalf("expected server reuse for same root/language, got %d starts", starts)
	}
}

func TestManagerStopsIdleServers(t *testing.T) {
	now := time.Date(2026, 6, 5, 12, 0, 0, 0, time.UTC)
	root := workspace.Root{ID: "root_1", Path: t.TempDir()}
	manager := NewManager(Options{
		IdleTimeout: time.Minute,
		Now: func() time.Time {
			return now
		},
		Registry: map[string]ServerConfig{
			"go": fakeLSPServerConfig(t, root.Path),
		},
	})
	t.Cleanup(manager.Shutdown)

	_, err := manager.Definition(context.Background(), Request{
		Root:     root,
		Language: "go",
		Path:     "main.go",
		Line:     1,
		Column:   1,
	})
	if err != nil {
		t.Fatalf("Definition returned error: %v", err)
	}
	if manager.ActiveCount() != 1 {
		t.Fatalf("expected one active server, got %d", manager.ActiveCount())
	}

	now = now.Add(2 * time.Minute)
	manager.StopIdle()
	if manager.ActiveCount() != 0 {
		t.Fatalf("expected idle server to stop, got %d active", manager.ActiveCount())
	}
}

func TestManagerRejectsUnsupportedNavigationLanguage(t *testing.T) {
	manager := NewManager(Options{})
	t.Cleanup(manager.Shutdown)

	_, err := manager.Definition(context.Background(), Request{
		Root:     workspace.Root{ID: "root_1", Path: t.TempDir()},
		Language: "markdown",
		Path:     "README.md",
		Line:     1,
		Column:   1,
	})
	if err == nil {
		t.Fatal("expected unsupported language error")
	}
	var lspErr *Error
	if !AsError(err, &lspErr) {
		t.Fatalf("expected *Error, got %T", err)
	}
	if lspErr.Code != "unsupported_language" {
		t.Fatalf("expected unsupported_language, got %q", lspErr.Code)
	}
}

func TestManagerDefinitionInitializesServerAndReturnsLocation(t *testing.T) {
	rootPath := t.TempDir()
	manager := NewManager(Options{
		Registry: map[string]ServerConfig{
			"go": fakeLSPServerConfig(t, rootPath),
		},
	})
	t.Cleanup(manager.Shutdown)

	locations, err := manager.Definition(context.Background(), Request{
		Root:     workspace.Root{ID: "root_1", Path: rootPath},
		Language: "go",
		Path:     "main.go",
		Line:     2,
		Column:   6,
	})
	if err != nil {
		t.Fatalf("Definition returned error: %v", err)
	}

	if len(locations) != 1 {
		t.Fatalf("expected one location, got %+v", locations)
	}
	location := locations[0]
	if location.RootID != "root_1" || location.RootPath != rootPath || location.Path != "target.go" {
		t.Fatalf("unexpected location identity: %+v", location)
	}
	if location.StartLine != 3 || location.StartColumn != 4 || location.EndLine != 3 || location.EndColumn != 10 {
		t.Fatalf("expected 1-based location range, got %+v", location)
	}
}

func TestManagerReferencesReturnsLocations(t *testing.T) {
	rootPath := t.TempDir()
	manager := NewManager(Options{
		Registry: map[string]ServerConfig{
			"go": fakeLSPServerConfig(t, rootPath),
		},
	})
	t.Cleanup(manager.Shutdown)

	locations, err := manager.References(context.Background(), Request{
		Root:     workspace.Root{ID: "root_1", Path: rootPath},
		Language: "go",
		Path:     "main.go",
		Line:     2,
		Column:   6,
	})
	if err != nil {
		t.Fatalf("References returned error: %v", err)
	}
	if len(locations) != 2 {
		t.Fatalf("expected two locations, got %+v", locations)
	}
	if locations[0].Path != "main.go" || locations[1].Path != "target.go" {
		t.Fatalf("unexpected reference paths: %+v", locations)
	}
}

func TestManagerDocumentSymbolFlattensHierarchyWithDepth(t *testing.T) {
	rootPath := t.TempDir()
	manager := NewManager(Options{
		Registry: map[string]ServerConfig{
			"go": fakeLSPServerConfig(t, rootPath),
		},
	})
	t.Cleanup(manager.Shutdown)

	symbols, err := manager.DocumentSymbol(context.Background(), Request{
		Root:     workspace.Root{ID: "root_1", Path: rootPath},
		Language: "go",
		Path:     "main.go",
	})
	if err != nil {
		t.Fatalf("DocumentSymbol returned error: %v", err)
	}
	if len(symbols) != 2 {
		t.Fatalf("expected two flattened symbols, got %+v", symbols)
	}
	if symbols[0].Name != "Greeter" || symbols[0].Kind != 5 || symbols[0].Depth != 0 {
		t.Fatalf("unexpected top-level symbol: %+v", symbols[0])
	}
	// selectionRange start is 0-based line 4, char 5 -> 1-based 5:6.
	if symbols[0].Line != 5 || symbols[0].Column != 6 {
		t.Fatalf("expected selectionRange-based 1-based position, got %+v", symbols[0])
	}
	if symbols[1].Name != "hello" || symbols[1].Kind != 6 || symbols[1].Depth != 1 {
		t.Fatalf("unexpected nested symbol: %+v", symbols[1])
	}
	if symbols[1].Line != 6 || symbols[1].Column != 7 {
		t.Fatalf("expected nested 1-based position, got %+v", symbols[1])
	}
}

func TestParseSymbolsHandlesFlatInformationAndNull(t *testing.T) {
	if got := parseSymbols([]byte("null")); len(got) != 0 {
		t.Fatalf("expected empty slice for null, got %+v", got)
	}
	if got := parseSymbols(nil); len(got) != 0 {
		t.Fatalf("expected empty slice for empty input, got %+v", got)
	}

	flat := []byte(`[{"name":"main","kind":12,"location":{"uri":"file:///x/main.go","range":{"start":{"line":2,"character":5},"end":{"line":2,"character":9}}}}]`)
	symbols := parseSymbols(flat)
	if len(symbols) != 1 {
		t.Fatalf("expected one flat symbol, got %+v", symbols)
	}
	if symbols[0].Name != "main" || symbols[0].Kind != 12 || symbols[0].Line != 3 || symbols[0].Column != 6 || symbols[0].Depth != 0 {
		t.Fatalf("unexpected flat symbol: %+v", symbols[0])
	}
}

func fakeLSPServerConfig(t *testing.T, rootPath string) ServerConfig {
	t.Helper()

	return ServerConfig{
		Command: os.Args[0],
		Args: []string{
			"-test.run=TestFakeLSPServer",
			"--",
			rootPath,
		},
	}
}

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
			var params struct {
				Capabilities map[string]any `json:"capabilities"`
			}
			if err := json.Unmarshal(req.Params, &params); err != nil {
				fmt.Fprintf(os.Stderr, "decode initialize params: %v\n", err)
				os.Exit(2)
			}
			textDocument, _ := params.Capabilities["textDocument"].(map[string]any)
			for _, forbidden := range []string{"completion", "codeAction", "diagnostic", "publishDiagnostics", "formatting"} {
				if _, ok := textDocument[forbidden]; ok {
					fmt.Fprintf(os.Stderr, "forbidden capability advertised: %s\n", forbidden)
					os.Exit(2)
				}
			}
			writeLSPMessage(map[string]any{
				"jsonrpc": "2.0",
				"id":      req.ID,
				"result": map[string]any{
					"capabilities": map[string]any{},
				},
			})
		case "initialized", "textDocument/didOpen":
		case "textDocument/definition":
			writeLSPMessage(map[string]any{
				"jsonrpc": "2.0",
				"id":      req.ID,
				"result": map[string]any{
					"uri": testFileURI(filepath.Join(rootPath, "target.go")),
					"range": map[string]any{
						"start": map[string]any{"line": 2, "character": 3},
						"end":   map[string]any{"line": 2, "character": 9},
					},
				},
			})
		case "textDocument/references":
			var params struct {
				Context struct {
					IncludeDeclaration bool `json:"includeDeclaration"`
				} `json:"context"`
			}
			if err := json.Unmarshal(req.Params, &params); err != nil {
				fmt.Fprintf(os.Stderr, "decode references params: %v\n", err)
				os.Exit(2)
			}
			if !params.Context.IncludeDeclaration {
				fmt.Fprintln(os.Stderr, "references request must include declarations")
				os.Exit(2)
			}
			writeLSPMessage(map[string]any{
				"jsonrpc": "2.0",
				"id":      req.ID,
				"result": []map[string]any{
					{
						"uri": testFileURI(filepath.Join(rootPath, "main.go")),
						"range": map[string]any{
							"start": map[string]any{"line": 1, "character": 5},
							"end":   map[string]any{"line": 1, "character": 9},
						},
					},
					{
						"uri": testFileURI(filepath.Join(rootPath, "target.go")),
						"range": map[string]any{
							"start": map[string]any{"line": 2, "character": 3},
							"end":   map[string]any{"line": 2, "character": 9},
						},
					},
				},
			})
		case "textDocument/documentSymbol":
			writeLSPMessage(map[string]any{
				"jsonrpc": "2.0",
				"id":      req.ID,
				"result": []map[string]any{
					{
						"name": "Greeter",
						"kind": 5, // Class
						"range": map[string]any{
							"start": map[string]any{"line": 4, "character": 0},
							"end":   map[string]any{"line": 9, "character": 1},
						},
						"selectionRange": map[string]any{
							"start": map[string]any{"line": 4, "character": 5},
							"end":   map[string]any{"line": 4, "character": 12},
						},
						"children": []map[string]any{
							{
								"name": "hello",
								"kind": 6, // Method
								"range": map[string]any{
									"start": map[string]any{"line": 5, "character": 2},
									"end":   map[string]any{"line": 7, "character": 3},
								},
								"selectionRange": map[string]any{
									"start": map[string]any{"line": 5, "character": 6},
									"end":   map[string]any{"line": 5, "character": 11},
								},
							},
						},
					},
				},
			})
		case "shutdown":
			writeLSPMessage(map[string]any{
				"jsonrpc": "2.0",
				"id":      req.ID,
				"result":  nil,
			})
		default:
			if req.ID != 0 {
				writeLSPMessage(map[string]any{
					"jsonrpc": "2.0",
					"id":      req.ID,
					"error": map[string]any{
						"code":    -32601,
						"message": "unsupported method: " + req.Method,
					},
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

func testFileURI(path string) string {
	return (&url.URL{Scheme: "file", Path: path}).String()
}
