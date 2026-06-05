package ipc

import (
	"bufio"
	"context"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/cmg/archsight/core/internal/lsp"
)

func TestServerDefinitionStartsOnlyOnExplicitNavigation(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("package main\nfunc main() {}\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	navigator := &recordingNavigator{
		definitionLocations: []lsp.Location{{
			RootID:      "root_1",
			RootPath:    root,
			Path:        "main.go",
			StartLine:   1,
			StartColumn: 1,
			EndLine:     1,
			EndColumn:   5,
		}},
	}
	conn, cleanup := startTestServerWithNavigator(t, navigator)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	if navigator.definitionCalls != 0 || navigator.referencesCalls != 0 {
		t.Fatalf("workspace open started LSP navigation: %+v", navigator)
	}

	writeJSON(t, conn, map[string]any{
		"id":     "req_open_before_lsp",
		"method": "openFile",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        "main.go",
		},
	})
	openResp := readResponse[struct{}](t, reader)
	if !openResp.OK {
		t.Fatalf("openFile failed: %+v", openResp.Error)
	}
	if navigator.definitionCalls != 0 || navigator.referencesCalls != 0 {
		t.Fatalf("openFile started LSP navigation: %+v", navigator)
	}

	writeJSON(t, conn, map[string]any{
		"id":     "req_definition",
		"method": "definition",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        "main.go",
			"line":        2,
			"column":      6,
		},
	})
	resp := readResponse[struct {
		Locations []lsp.Location `json:"locations"`
	}](t, reader)
	if !resp.OK {
		t.Fatalf("definition failed: %+v", resp.Error)
	}
	if navigator.definitionCalls != 1 {
		t.Fatalf("expected one definition call, got %d", navigator.definitionCalls)
	}
	if navigator.lastRequest.Language != "go" || navigator.lastRequest.Path != "main.go" {
		t.Fatalf("unexpected navigation request: %+v", navigator.lastRequest)
	}
	if len(resp.Result.Locations) != 1 || resp.Result.Locations[0].Path != "main.go" {
		t.Fatalf("unexpected definition locations: %+v", resp.Result.Locations)
	}
}

func TestServerReferencesUsesReadOnlyNavigationPath(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	navigator := &recordingNavigator{}
	conn, cleanup := startTestServerWithNavigator(t, navigator)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_refs",
		"method": "references",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        "main.go",
			"line":        1,
			"column":      9,
		},
	})

	resp := readResponse[struct {
		Locations []lsp.Location `json:"locations"`
	}](t, reader)
	if !resp.OK {
		t.Fatalf("references failed: %+v", resp.Error)
	}
	if navigator.referencesCalls != 1 {
		t.Fatalf("expected one references call, got %d", navigator.referencesCalls)
	}
}

func TestServerRejectsEditorOrientedLSPMethods(t *testing.T) {
	conn, cleanup := startTestServerWithNavigator(t, &recordingNavigator{})
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	for _, method := range []string{"completion", "codeAction", "diagnostics", "formatting"} {
		writeJSON(t, conn, map[string]any{
			"id":     "req_" + method,
			"method": method,
			"params": map[string]any{},
		})
		resp := readResponse[struct{}](t, reader)
		if resp.OK {
			t.Fatalf("expected %s to be unsupported", method)
		}
		if resp.Error == nil || resp.Error.Code != "unsupported_method" {
			t.Fatalf("expected unsupported_method for %s, got %+v", method, resp.Error)
		}
	}
}

func TestServerShutdownStopsNavigator(t *testing.T) {
	navigator := &recordingNavigator{}
	socketPath := testSocketPath(t)
	server := NewServer(Config{
		SocketPath: socketPath,
		Version:    "test-version",
		Navigator:  navigator,
	})
	errc := make(chan error, 1)
	go func() {
		errc <- server.ListenAndServe()
	}()

	conn := dialUnix(t, socketPath)
	_ = conn.Close()
	if err := server.Shutdown(); err != nil {
		t.Fatalf("Shutdown returned error: %v", err)
	}
	select {
	case err := <-errc:
		if err != nil {
			t.Fatalf("ListenAndServe returned error: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("server did not shut down")
	}
	if navigator.shutdownCalls != 1 {
		t.Fatalf("expected navigator shutdown once, got %d", navigator.shutdownCalls)
	}
}

func TestServerDefinitionRejectsFileOutsideSnapshot(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(filepath.Join(root, ".git"), 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, ".git", "config"), []byte("[core]\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	navigator := &recordingNavigator{}
	conn, cleanup := startTestServerWithNavigator(t, navigator)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_definition_ignored",
		"method": "definition",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        ".git/config",
			"line":        1,
			"column":      1,
		},
	})

	resp := readResponse[struct{}](t, reader)
	if resp.OK {
		t.Fatal("expected definition outside snapshot to fail")
	}
	if resp.Error == nil || resp.Error.Code != "not_found" {
		t.Fatalf("expected not_found, got %+v", resp.Error)
	}
	if navigator.definitionCalls != 0 {
		t.Fatalf("definition should not reach navigator for ignored files, got %d calls", navigator.definitionCalls)
	}
}

type recordingNavigator struct {
	definitionCalls     int
	referencesCalls     int
	shutdownCalls       int
	lastRequest         lsp.Request
	definitionLocations []lsp.Location
	referencesLocations []lsp.Location
}

func (n *recordingNavigator) Definition(_ context.Context, req lsp.Request) ([]lsp.Location, error) {
	n.definitionCalls++
	n.lastRequest = req
	return n.definitionLocations, nil
}

func (n *recordingNavigator) References(_ context.Context, req lsp.Request) ([]lsp.Location, error) {
	n.referencesCalls++
	n.lastRequest = req
	return n.referencesLocations, nil
}

func (n *recordingNavigator) Shutdown() {
	n.shutdownCalls++
}

func startTestServerWithNavigator(t *testing.T, navigator *recordingNavigator) (net.Conn, func()) {
	t.Helper()

	socketPath := testSocketPath(t)
	server := NewServer(Config{
		SocketPath: socketPath,
		Version:    "test-version",
		Navigator:  navigator,
	})
	errc := make(chan error, 1)
	go func() {
		errc <- server.ListenAndServe()
	}()

	conn := dialUnix(t, socketPath)
	cleanup := func() {
		_ = conn.Close()
		_ = server.Shutdown()
		select {
		case err := <-errc:
			if err != nil {
				t.Fatalf("ListenAndServe returned error: %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("server did not shut down")
		}
	}
	return conn, cleanup
}
