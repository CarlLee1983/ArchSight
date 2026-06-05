package workspace

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func TestManagerScansMultipleRootsAsFlattenedSnapshot(t *testing.T) {
	rootA := makeRoot(t, "service-a", map[string]string{
		"cmd/api/main.go":       "package main\n",
		"node_modules/pkg/a.js": "ignored\n",
	})
	rootB := makeRoot(t, "service-b", map[string]string{
		"Sources/App.swift":      "struct App {}\n",
		".git/objects/ignored":   "ignored\n",
		"DerivedData/cache/file": "ignored\n",
	})

	manager := NewManager()
	snapshot, err := manager.Open(context.Background(), []string{rootA, rootB})
	if err != nil {
		t.Fatalf("Open returned error: %v", err)
	}

	waitForSnapshot(t, manager, snapshot.ID)
	got, ok := manager.Get(snapshot.ID)
	if !ok {
		t.Fatal("snapshot was not stored")
	}
	if got.Status != StatusReady {
		t.Fatalf("expected ready snapshot, got %q", got.Status)
	}
	if len(got.Roots) != 2 {
		t.Fatalf("expected 2 roots, got %d", len(got.Roots))
	}
	if got.Roots[0].Path != rootA || got.Roots[1].Path != rootB {
		t.Fatalf("root paths were not preserved: %+v", got.Roots)
	}

	paths := entryPaths(got.Entries)
	if !slices.Contains(paths, "cmd/api/main.go") {
		t.Fatalf("expected flattened entry for Go file, got %v", paths)
	}
	if !slices.Contains(paths, "Sources/App.swift") {
		t.Fatalf("expected flattened entry for Swift file, got %v", paths)
	}
	for _, path := range paths {
		if path == "node_modules/pkg/a.js" || path == ".git/objects/ignored" || path == "DerivedData/cache/file" {
			t.Fatalf("ignored path was scanned: %s", path)
		}
	}
}

func TestManagerDoesNotWriteMetadataIntoRoots(t *testing.T) {
	root := makeRoot(t, "service", map[string]string{
		"main.go": "package main\n",
	})
	before := listAllPaths(t, root)

	manager := NewManager()
	snapshot, err := manager.Open(context.Background(), []string{root})
	if err != nil {
		t.Fatalf("Open returned error: %v", err)
	}
	waitForSnapshot(t, manager, snapshot.ID)

	after := listAllPaths(t, root)
	if !slices.Equal(before, after) {
		t.Fatalf("workspace scan wrote metadata; before=%v after=%v", before, after)
	}
}

func TestManagerCancelsScanPromptly(t *testing.T) {
	root := makeRoot(t, "large-service", nil)
	for i := range 200 {
		path := filepath.Join(root, "dir", "file-"+string(rune('a'+(i%26)))+"-"+time.Now().Format("150405.000000000"))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("MkdirAll returned error: %v", err)
		}
		if err := os.WriteFile(path, []byte("content"), 0o644); err != nil {
			t.Fatalf("WriteFile returned error: %v", err)
		}
	}

	manager := NewManager()
	manager.beforeEntry = func() {
		time.Sleep(time.Millisecond)
	}
	snapshot, err := manager.Open(context.Background(), []string{root})
	if err != nil {
		t.Fatalf("Open returned error: %v", err)
	}
	if !manager.Cancel(snapshot.ID) {
		t.Fatal("expected cancellation to be accepted")
	}

	waitForSnapshot(t, manager, snapshot.ID)
	got, _ := manager.Get(snapshot.ID)
	if got.Status != StatusCanceled {
		t.Fatalf("expected canceled snapshot, got %q", got.Status)
	}
}

func makeRoot(t *testing.T, name string, files map[string]string) string {
	t.Helper()

	root := filepath.Join(t.TempDir(), name)
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	for rel, content := range files {
		path := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("MkdirAll returned error: %v", err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatalf("WriteFile returned error: %v", err)
		}
	}
	return root
}

func waitForSnapshot(t *testing.T, manager *Manager, id string) {
	t.Helper()

	deadline := time.After(2 * time.Second)
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-deadline:
			got, _ := manager.Get(id)
			t.Fatalf("timed out waiting for snapshot %s; status=%q", id, got.Status)
		case <-ticker.C:
			got, ok := manager.Get(id)
			if ok && got.Status != StatusScanning {
				return
			}
		}
	}
}

func entryPaths(entries []Entry) []string {
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.Kind == KindFile {
			paths = append(paths, entry.Path)
		}
	}
	slices.Sort(paths)
	return paths
}

func listAllPaths(t *testing.T, root string) []string {
	t.Helper()

	var paths []string
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if path == root {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		paths = append(paths, rel)
		return nil
	})
	if err != nil {
		t.Fatalf("WalkDir returned error: %v", err)
	}
	slices.Sort(paths)
	return paths
}
