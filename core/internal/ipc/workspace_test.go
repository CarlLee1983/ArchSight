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

func TestAddRootsRPCAppendsRoot(t *testing.T) {
	dirA := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirA, "a.txt"), []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirB := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirB, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	writeJSON(t, conn, map[string]any{
		"id":     "1",
		"method": "openWorkspace",
		"params": map[string]any{"roots": []string{dirA}},
	})
	openResp := readResponse[struct {
		WorkspaceID string           `json:"workspaceId"`
		Status      workspace.Status `json:"status"`
	}](t, reader)
	if !openResp.OK {
		t.Fatalf("openWorkspace failed: %+v", openResp.Error)
	}
	wsID := openResp.Result.WorkspaceID

	waitForReadySocket(t, conn, reader, wsID)

	writeJSON(t, conn, map[string]any{
		"id":     "2",
		"method": "addRoots",
		"params": map[string]any{"workspaceId": wsID, "roots": []string{dirB}},
	})
	addResp := readResponse[struct {
		WorkspaceID string           `json:"workspaceId"`
		Status      workspace.Status `json:"status"`
	}](t, reader)
	if !addResp.OK {
		t.Fatalf("addRoots failed: %+v", addResp.Error)
	}

	waitForReadySocket(t, conn, reader, wsID)

	writeJSON(t, conn, map[string]any{
		"id":     "3",
		"method": "listTree",
		"params": map[string]any{"workspaceId": wsID},
	})
	treeResp := readResponse[struct {
		Roots []workspace.Root `json:"roots"`
	}](t, reader)
	if !treeResp.OK {
		t.Fatalf("listTree failed: %+v", treeResp.Error)
	}
	if len(treeResp.Result.Roots) != 2 {
		t.Fatalf("expected 2 roots after addRoots, got %d", len(treeResp.Result.Roots))
	}
}

func TestRemoveRootRPCDropsRoot(t *testing.T) {
	dirA := t.TempDir()
	dirB := t.TempDir()

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	writeJSON(t, conn, map[string]any{
		"id":     "1",
		"method": "openWorkspace",
		"params": map[string]any{"roots": []string{dirA, dirB}},
	})
	openResp := readResponse[struct {
		WorkspaceID string           `json:"workspaceId"`
		Status      workspace.Status `json:"status"`
	}](t, reader)
	if !openResp.OK {
		t.Fatalf("openWorkspace failed: %+v", openResp.Error)
	}
	wsID := openResp.Result.WorkspaceID

	waitForReadySocket(t, conn, reader, wsID)

	writeJSON(t, conn, map[string]any{
		"id":     "2",
		"method": "removeRoot",
		"params": map[string]any{"workspaceId": wsID, "rootId": "root_1"},
	})
	rmResp := readResponse[struct {
		Roots []workspace.Root `json:"roots"`
	}](t, reader)
	if !rmResp.OK {
		t.Fatalf("removeRoot failed: %+v", rmResp.Error)
	}
	if len(rmResp.Result.Roots) != 1 || rmResp.Result.Roots[0].ID != "root_2" {
		t.Fatalf("expected only root_2 after removeRoot, got %+v", rmResp.Result.Roots)
	}
}

func TestAddRootsRPCUnknownWorkspaceReturnsNotFound(t *testing.T) {
	dir := t.TempDir()

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	writeJSON(t, conn, map[string]any{
		"id":     "1",
		"method": "addRoots",
		"params": map[string]any{"workspaceId": "ws_does_not_exist", "roots": []string{dir}},
	})
	resp := readResponse[struct{}](t, reader)
	if resp.OK {
		t.Fatalf("expected addRoots to fail for unknown workspace, got OK")
	}
	if resp.Error == nil || resp.Error.Code != "not_found" {
		t.Fatalf("expected error code not_found, got %+v", resp.Error)
	}
}

// waitForReadySocket polls listTree over the socket until status == "ready".
func waitForReadySocket(t *testing.T, conn net.Conn, reader *bufio.Reader, wsID string) {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		writeJSON(t, conn, map[string]any{
			"id":     "poll",
			"method": "listTree",
			"params": map[string]any{"workspaceId": wsID},
		})
		resp := readResponse[struct {
			Status workspace.Status `json:"status"`
		}](t, reader)
		if !resp.OK {
			t.Fatalf("listTree (poll) failed: %+v", resp.Error)
		}
		if resp.Result.Status == workspace.StatusReady {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("workspace %s did not become ready within 2s", wsID)
		default:
			time.Sleep(10 * time.Millisecond)
		}
	}
}

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

func TestListTreeReturnsEmptyArraysWhileScanning(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
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
		WorkspaceID string `json:"workspaceId"`
	}](t, reader)
	if !openResp.OK {
		t.Fatalf("openWorkspace failed: %+v", openResp.Error)
	}

	writeJSON(t, conn, map[string]any{
		"id":     "req_list",
		"method": "listTree",
		"params": map[string]any{"workspaceId": openResp.Result.WorkspaceID},
	})
	line, err := reader.ReadBytes('\n')
	if err != nil {
		t.Fatalf("ReadBytes returned error: %v", err)
	}
	if string(line) == "" {
		t.Fatal("expected listTree response")
	}

	var decoded struct {
		OK     bool `json:"ok"`
		Result struct {
			Roots   []workspace.Root  `json:"roots"`
			Entries []workspace.Entry `json:"entries"`
		} `json:"result"`
	}
	if err := json.Unmarshal(line, &decoded); err != nil {
		t.Fatalf("Unmarshal returned error: %v; line=%s", err, line)
	}
	if !decoded.OK {
		t.Fatalf("listTree failed: %s", line)
	}
	if decoded.Result.Roots == nil {
		t.Fatalf("expected roots to decode as an empty or populated array, got nil; line=%s", line)
	}
	if decoded.Result.Entries == nil {
		t.Fatalf("expected entries to decode as an empty array, got nil; line=%s", line)
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
