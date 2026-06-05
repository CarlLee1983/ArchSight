package ipc

import (
	"bufio"
	"os"
	"path/filepath"
	"testing"
)

func TestServerOpenFileReturnsReadOnlyContentAndSyntaxTokens(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(filepath.Join(root, "cmd"), 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	source := "package main\n\nfunc main() {}\n"
	if err := os.WriteFile(filepath.Join(root, "cmd", "main.go"), []byte(source), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_open_file",
		"method": "openFile",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        "cmd/main.go",
		},
	})

	resp := readResponse[struct {
		RootID   string `json:"rootId"`
		RootPath string `json:"rootPath"`
		Path     string `json:"path"`
		Language string `json:"language"`
		Content  string `json:"content"`
		Tokens   []struct {
			StartLine   int    `json:"startLine"`
			StartColumn int    `json:"startColumn"`
			EndLine     int    `json:"endLine"`
			EndColumn   int    `json:"endColumn"`
			Type        string `json:"type"`
		} `json:"tokens"`
	}](t, reader)
	if !resp.OK {
		t.Fatalf("openFile failed: %+v", resp.Error)
	}
	if resp.Result.RootID != "root_1" || resp.Result.RootPath != root || resp.Result.Path != "cmd/main.go" {
		t.Fatalf("unexpected file identity: %+v", resp.Result)
	}
	if resp.Result.Language != "go" {
		t.Fatalf("expected go language, got %q", resp.Result.Language)
	}
	if resp.Result.Content != source {
		t.Fatalf("unexpected content: %q", resp.Result.Content)
	}
	if len(resp.Result.Tokens) == 0 {
		t.Fatal("expected syntax tokens for Go file")
	}
}

func TestServerOpenFileRejectsPathTraversal(t *testing.T) {
	temp := t.TempDir()
	root := filepath.Join(temp, "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(temp, "secret.go"), []byte("package secret\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_open_escape",
		"method": "openFile",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        "../secret.go",
		},
	})

	resp := readResponse[struct{}](t, reader)
	if resp.OK {
		t.Fatal("expected path traversal to fail")
	}
	if resp.Error == nil || resp.Error.Code != "invalid_path" {
		t.Fatalf("expected invalid_path error, got %+v", resp.Error)
	}
}

func TestServerOpenFileFallsBackToPlainTextForUnsupportedLanguage(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "notes.txt"), []byte("plain text\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_open_plain",
		"method": "openFile",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        "notes.txt",
		},
	})

	resp := readResponse[struct {
		Language string        `json:"language"`
		Content  string        `json:"content"`
		Tokens   []interface{} `json:"tokens"`
	}](t, reader)
	if !resp.OK {
		t.Fatalf("openFile failed: %+v", resp.Error)
	}
	if resp.Result.Language != "" {
		t.Fatalf("expected empty language for unsupported file, got %q", resp.Result.Language)
	}
	if resp.Result.Content != "plain text\n" {
		t.Fatalf("unexpected content: %q", resp.Result.Content)
	}
	if len(resp.Result.Tokens) != 0 {
		t.Fatalf("expected no tokens for unsupported file, got %+v", resp.Result.Tokens)
	}
}

func TestServerOpenFileRejectsFilesOutsideSnapshot(t *testing.T) {
	root := filepath.Join(t.TempDir(), "service")
	if err := os.MkdirAll(filepath.Join(root, ".git"), 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, ".git", "config"), []byte("[core]\n"), 0o644); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	conn, cleanup := startTestServer(t)
	defer cleanup()
	defer conn.Close()
	reader := bufio.NewReader(conn)

	workspaceID := openReadyWorkspace(t, conn, reader, root)
	writeJSON(t, conn, map[string]any{
		"id":     "req_open_ignored",
		"method": "openFile",
		"params": map[string]any{
			"workspaceId": workspaceID,
			"rootId":      "root_1",
			"path":        ".git/config",
		},
	})

	resp := readResponse[struct{}](t, reader)
	if resp.OK {
		t.Fatal("expected ignored file outside snapshot to fail")
	}
	if resp.Error == nil || resp.Error.Code != "not_found" {
		t.Fatalf("expected not_found error, got %+v", resp.Error)
	}
}
