package ipc

import (
	"bufio"
	"context"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/cmg/archsight/core/internal/search"
	"github.com/cmg/archsight/core/internal/workspace"
)

func TestServerSearchesOpenedWorkspace(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("package main\n// needle\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_search",
		"method": "search",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"pattern":     "needle",
		},
	})

	resp := readResponse[struct {
		Matches []search.Match `json:"matches"`
	}](t, reader)
	if !resp.OK {
		t.Fatalf("search failed: %+v", resp.Error)
	}
	if len(resp.Result.Matches) != 1 {
		t.Fatalf("expected 1 match, got %+v", resp.Result.Matches)
	}
	match := resp.Result.Matches[0]
	if match.RootPath != root || match.Path != "main.go" || match.Line != 2 {
		t.Fatalf("unexpected match: %+v", match)
	}
}

func TestServerSearchRejectsInvalidPattern(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_search",
		"method": "search",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"pattern":     "[",
		},
	})

	resp := readResponse[struct{}](t, reader)
	if resp.OK {
		t.Fatal("expected invalid pattern to fail")
	}
	if resp.Error == nil || resp.Error.Code != "invalid_pattern" {
		t.Fatalf("expected invalid_pattern error, got %+v", resp.Error)
	}
}

func TestServerCancelsActiveSearchRequest(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}

	socketPath := testSocketPath(t)
	searcher := &blockingSearcher{
		started:  make(chan struct{}),
		released: make(chan struct{}),
	}
	server := NewServer(Config{
		SocketPath: socketPath,
		Version:    "test-version",
		Searcher:   searcher,
	})
	errc := make(chan error, 1)
	go func() {
		errc <- server.ListenAndServe()
	}()
	conn := dialUnix(t, socketPath)
	defer func() {
		_ = conn.Close()
		_ = server.Shutdown()
		<-errc
	}()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	searchDone := make(chan ResponseEnvelope[struct {
		Matches []search.Match `json:"matches"`
	}], 1)
	go func() {
		writeJSON(t, conn, map[string]any{
			"id":     "req_blocking_search",
			"method": "search",
			"params": map[string]any{
				"workspaceId": workspaceID,
				"pattern":     "needle",
			},
		})
		searchDone <- readResponse[struct {
			Matches []search.Match `json:"matches"`
		}](t, reader)
	}()

	select {
	case <-searcher.started:
	case <-time.After(time.Second):
		t.Fatal("search did not start")
	}

	cancelConn := dialUnix(t, socketPath)
	defer cancelConn.Close()
	cancelReader := bufio.NewReader(cancelConn)
	writeJSON(t, cancelConn, map[string]any{
		"id":     "req_cancel_search",
		"method": "cancel",
		"params": map[string]any{"targetId": "req_blocking_search"},
	})
	cancelResp := readResponse[map[string]bool](t, cancelReader)
	if !cancelResp.OK || !cancelResp.Result["canceled"] {
		t.Fatalf("cancel failed: %+v", cancelResp)
	}

	select {
	case <-searcher.released:
	case <-time.After(time.Second):
		t.Fatal("search context was not canceled")
	}
	select {
	case resp := <-searchDone:
		if resp.OK || resp.Error == nil || resp.Error.Code != "context_canceled" {
			t.Fatalf("expected canceled search response, got %+v", resp)
		}
	case <-time.After(time.Second):
		t.Fatal("search response did not return after cancellation")
	}
}

func openReadyWorkspace(t *testing.T, conn net.Conn, reader *bufio.Reader, root string) string {
	t.Helper()

	writeJSON(t, conn, map[string]any{
		"id":     "req_open_for_search",
		"method": "openWorkspace",
		"params": map[string]any{"roots": []string{root}},
	})
	openResp := readResponse[struct {
		WorkspaceID string `json:"workspaceId"`
	}](t, reader)
	if !openResp.OK {
		t.Fatalf("openWorkspace failed: %+v", openResp.Error)
	}

	deadline := time.After(2 * time.Second)
	for {
		writeJSON(t, conn, map[string]any{
			"id":     "req_list_for_search",
			"method": "listTree",
			"params": map[string]any{"workspaceId": openResp.Result.WorkspaceID},
		})
		listResp := readResponse[struct {
			Status workspace.Status `json:"status"`
		}](t, reader)
		if !listResp.OK {
			t.Fatalf("listTree failed: %+v", listResp.Error)
		}
		if listResp.Result.Status == workspace.StatusReady {
			return openResp.Result.WorkspaceID
		}
		select {
		case <-deadline:
			t.Fatal("workspace did not become ready")
		default:
			time.Sleep(10 * time.Millisecond)
		}
	}
}

type blockingSearcher struct {
	started  chan struct{}
	released chan struct{}
}

func (s *blockingSearcher) Search(ctx context.Context, _ search.Request, _ func(search.Match) error) error {
	close(s.started)
	<-ctx.Done()
	close(s.released)
	return ctx.Err()
}
