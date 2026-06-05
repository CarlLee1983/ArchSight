package ipc

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestServerHandlesHealthRequestOverUnixSocket(t *testing.T) {
	socketPath := testSocketPath(t)
	server := NewServer(Config{
		SocketPath: socketPath,
		Version:    "test-version",
	})

	errc := make(chan error, 1)
	go func() {
		errc <- server.ListenAndServe()
	}()
	t.Cleanup(func() {
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
	})

	conn := dialUnix(t, socketPath)
	defer conn.Close()

	if _, err := conn.Write([]byte(`{"id":"req_health","method":"health","params":{}}` + "\n")); err != nil {
		t.Fatalf("Write returned error: %v", err)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		t.Fatalf("ReadBytes returned error: %v", err)
	}

	var resp struct {
		ID     string `json:"id"`
		OK     bool   `json:"ok"`
		Result struct {
			Version string `json:"version"`
			PID     int    `json:"pid"`
		} `json:"result"`
	}
	if err := json.Unmarshal(line, &resp); err != nil {
		t.Fatalf("response was not valid JSON: %v", err)
	}
	if resp.ID != "req_health" || !resp.OK {
		t.Fatalf("unexpected response envelope: %+v", resp)
	}
	if resp.Result.Version != "test-version" {
		t.Fatalf("expected version test-version, got %q", resp.Result.Version)
	}
	if resp.Result.PID == 0 {
		t.Fatal("expected health response to include process ID")
	}
}

func TestServerRejectsUnsupportedMethod(t *testing.T) {
	socketPath := testSocketPath(t)
	server := NewServer(Config{SocketPath: socketPath, Version: "test-version"})

	errc := make(chan error, 1)
	go func() {
		errc <- server.ListenAndServe()
	}()
	t.Cleanup(func() {
		_ = server.Shutdown()
		<-errc
	})

	conn := dialUnix(t, socketPath)
	defer conn.Close()

	if _, err := conn.Write([]byte(`{"id":"req_edit","method":"editFile","params":{}}` + "\n")); err != nil {
		t.Fatalf("Write returned error: %v", err)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		t.Fatalf("ReadBytes returned error: %v", err)
	}

	var resp struct {
		ID    string `json:"id"`
		OK    bool   `json:"ok"`
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(line, &resp); err != nil {
		t.Fatalf("response was not valid JSON: %v", err)
	}
	if resp.ID != "req_edit" || resp.OK {
		t.Fatalf("unexpected response envelope: %+v", resp)
	}
	if resp.Error.Code != "unsupported_method" {
		t.Fatalf("expected unsupported_method, got %q", resp.Error.Code)
	}
}

func TestServerRemovesSocketOnShutdown(t *testing.T) {
	socketPath := testSocketPath(t)
	server := NewServer(Config{SocketPath: socketPath, Version: "test-version"})

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

	if _, err := os.Stat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("expected socket file to be removed, stat error: %v", err)
	}
}

func testSocketPath(t *testing.T) string {
	t.Helper()

	dir, err := os.MkdirTemp("/tmp", "as-ipc-*")
	if err != nil {
		t.Fatalf("MkdirTemp returned error: %v", err)
	}
	t.Cleanup(func() {
		_ = os.RemoveAll(dir)
	})

	return filepath.Join(dir, "core.sock")
}

func dialUnix(t *testing.T, socketPath string) net.Conn {
	t.Helper()

	var lastErr error
	for range 50 {
		conn, err := net.Dial("unix", socketPath)
		if err == nil {
			return conn
		}
		lastErr = err
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("failed to dial unix socket: %v", lastErr)
	return nil
}
