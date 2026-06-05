package ipc

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/cmg/archsight/core/internal/workspace"
)

func TestServerOpensWorkspaceAndListsTree(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(filepath.Join(root, "cmd"), 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "cmd", "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	writeJSON(t, conn, map[string]any{
		"id":     "req_open",
		"method": "openWorkspace",
		"params": map[string]any{"roots": []string{root}},
	})
	openResp := readResponse[struct {
		WorkspaceID string           `json:"workspaceId"`
		Status      workspace.Status `json:"status"`
	}](t, reader)
	if !openResp.OK {
		t.Fatalf("openWorkspace failed: %+v", openResp.Error)
	}
	if openResp.Result.WorkspaceID == "" {
		t.Fatal("expected workspace ID")
	}
	if openResp.Result.Status != workspace.StatusScanning {
		t.Fatalf("expected asynchronous scan to start in scanning state, got %q", openResp.Result.Status)
	}

	var listResp ResponseEnvelope[struct {
		Status  workspace.Status  `json:"status"`
		Entries []workspace.Entry `json:"entries"`
	}]
	deadline := time.After(2 * time.Second)
	for {
		writeJSON(t, conn, map[string]any{
			"id":     "req_list",
			"method": "listTree",
			"params": map[string]any{"workspaceId": openResp.Result.WorkspaceID},
		})
		listResp = readResponse[struct {
			Status  workspace.Status  `json:"status"`
			Entries []workspace.Entry `json:"entries"`
		}](t, reader)
		if !listResp.OK {
			t.Fatalf("listTree failed: %+v", listResp.Error)
		}
		if listResp.Result.Status == workspace.StatusReady {
			break
		}
		select {
		case <-deadline:
			t.Fatal("workspace did not become ready")
		default:
			time.Sleep(10 * time.Millisecond)
		}
	}

	found := false
	for _, entry := range listResp.Result.Entries {
		if entry.RootPath == root && entry.Path == "cmd/main.go" && entry.Kind == workspace.KindFile {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected listed tree to include cmd/main.go, got %+v", listResp.Result.Entries)
	}
}

type ResponseEnvelope[T any] struct {
	ID     string      `json:"id"`
	OK     bool        `json:"ok"`
	Result T           `json:"result"`
	Error  *ErrorShape `json:"error"`
}

func startTestServer(t *testing.T) (net.Conn, func()) {
	t.Helper()

	socketPath := testSocketPath(t)
	server := NewServer(Config{SocketPath: socketPath, Version: "test-version"})
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

func writeJSON(t *testing.T, conn net.Conn, payload any) {
	t.Helper()

	encoded, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("Marshal returned error: %v", err)
	}
	if _, err := conn.Write(append(encoded, '\n')); err != nil {
		t.Fatalf("Write returned error: %v", err)
	}
}

func readResponse[T any](t *testing.T, reader *bufio.Reader) ResponseEnvelope[T] {
	t.Helper()

	line, err := reader.ReadBytes('\n')
	if err != nil {
		t.Fatalf("ReadBytes returned error: %v", err)
	}
	var resp ResponseEnvelope[T]
	if err := json.Unmarshal(line, &resp); err != nil {
		t.Fatalf("Unmarshal returned error: %v; line=%s", err, line)
	}
	return resp
}
