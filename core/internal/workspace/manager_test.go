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

func TestAddRootsAppendsOnlyNewRootsWithContinuingIDs(t *testing.T) {
	dirA := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirA, "a.txt"), []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirB := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirB, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	manager := NewManager()

	opened, err := manager.Open(context.Background(), []string{dirA})
	if err != nil {
		t.Fatalf("Open error: %v", err)
	}
	waitForSnapshot(t, manager, opened.ID)

	added, err := manager.AddRoots(context.Background(), opened.ID, []string{dirB})
	if err != nil {
		t.Fatalf("AddRoots error: %v", err)
	}
	if len(added.Roots) != 2 {
		t.Fatalf("expected 2 roots, got %d", len(added.Roots))
	}
	if added.Roots[1].ID != "root_2" {
		t.Fatalf("expected continuing id root_2, got %s", added.Roots[1].ID)
	}
	waitForSnapshot(t, manager, opened.ID)

	got, _ := manager.Get(opened.ID)
	var roots []string
	for _, e := range got.Entries {
		if e.Kind == KindFile {
			roots = append(roots, e.RootID+"/"+e.Path)
		}
	}
	if len(roots) != 2 {
		t.Fatalf("expected entries from both roots, got %v", roots)
	}
}

func TestAddRootsUnknownWorkspaceErrors(t *testing.T) {
	manager := NewManager()
	if _, err := manager.AddRoots(context.Background(), "ws_missing", []string{t.TempDir()}); err == nil {
		t.Fatal("expected error for unknown workspace")
	}
}

func TestRemoveRootDropsRootAndItsEntriesKeepingOthers(t *testing.T) {
	dirA := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirA, "a.txt"), []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirB := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirB, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	manager := NewManager()
	opened, err := manager.Open(context.Background(), []string{dirA, dirB})
	if err != nil {
		t.Fatalf("Open error: %v", err)
	}
	waitForSnapshot(t, manager, opened.ID)

	removed, err := manager.RemoveRoot(opened.ID, "root_1")
	if err != nil {
		t.Fatalf("RemoveRoot error: %v", err)
	}
	if len(removed.Roots) != 1 || removed.Roots[0].ID != "root_2" {
		t.Fatalf("expected only root_2 to remain, got %+v", removed.Roots)
	}
	for _, e := range removed.Entries {
		if e.RootID == "root_1" {
			t.Fatalf("entries for removed root should be gone, found %s", e.Path)
		}
	}

	got, ok := manager.Get(opened.ID)
	if !ok {
		t.Fatal("snapshot was not stored")
	}
	if len(got.Roots) != 1 || got.Roots[0].ID != "root_2" {
		t.Fatalf("expected persisted snapshot to keep only root_2, got %+v", got.Roots)
	}
	for _, e := range got.Entries {
		if e.RootID == "root_1" {
			t.Fatalf("persisted entries for removed root should be gone, found %s", e.Path)
		}
	}
}

func TestRemoveRootUnknownWorkspaceErrors(t *testing.T) {
	manager := NewManager()
	if _, err := manager.RemoveRoot("ws_missing", "root_1"); err == nil {
		t.Fatal("expected error for unknown workspace")
	}
}

func TestRemoveRootUnknownErrors(t *testing.T) {
	dirA := t.TempDir()
	manager := NewManager()
	opened, _ := manager.Open(context.Background(), []string{dirA})
	waitForSnapshot(t, manager, opened.ID)
	if _, err := manager.RemoveRoot(opened.ID, "root_99"); err == nil {
		t.Fatal("expected error for unknown root")
	}
}

// TestFinishAppendDropsEntriesForRemovedRoot verifies the invariant that every
// entry's RootID is a current root even when RemoveRoot races with a concurrent
// scanAppend. We pause the scan inside beforeEntry, remove the root under the
// lock, then release the scan — finishAppend must filter out the stale entries.
func TestFinishAppendDropsEntriesForRemovedRoot(t *testing.T) {
	dirA := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirA, "a.txt"), []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirB := t.TempDir()
	// Give dirB several files so the scanner has at least one entry to process
	// before we unblock it.
	for _, name := range []string{"b1.txt", "b2.txt", "b3.txt"} {
		if err := os.WriteFile(filepath.Join(dirB, name), []byte(name), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	manager := NewManager()

	opened, err := manager.Open(context.Background(), []string{dirA})
	if err != nil {
		t.Fatalf("Open error: %v", err)
	}
	waitForSnapshot(t, manager, opened.ID)

	// Block at the very first entry of the dirB scan so we can call RemoveRoot
	// while the append scan is still in flight.
	blocked := make(chan struct{})
	unblock := make(chan struct{})
	once := false
	manager.beforeEntry = func() {
		if !once {
			once = true
			close(blocked)
			<-unblock
		}
	}

	added, err := manager.AddRoots(context.Background(), opened.ID, []string{dirB})
	if err != nil {
		t.Fatalf("AddRoots error: %v", err)
	}
	root2ID := added.Roots[len(added.Roots)-1].ID

	// Wait until the scan goroutine is blocked on the first entry, then remove
	// the root it is scanning. This simulates a concurrent RemoveRoot call
	// arriving before finishAppend commits its entries.
	select {
	case <-blocked:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for scan to block")
	}
	if _, err := manager.RemoveRoot(opened.ID, root2ID); err != nil {
		t.Fatalf("RemoveRoot error: %v", err)
	}
	// Release the blocked scan so finishAppend runs.
	close(unblock)

	waitForSnapshot(t, manager, opened.ID)
	got, ok := manager.Get(opened.ID)
	if !ok {
		t.Fatal("snapshot not found after append+remove race")
	}
	for _, e := range got.Entries {
		if e.RootID == root2ID {
			t.Errorf("found orphaned entry %q with removed root %s", e.Path, root2ID)
		}
	}
}

func TestOpenAssignsSequentialRootIDsFromOne(t *testing.T) {
	dirA := t.TempDir()
	dirB := t.TempDir()
	manager := NewManager()

	snapshot, err := manager.Open(context.Background(), []string{dirA, dirB})
	if err != nil {
		t.Fatalf("Open returned error: %v", err)
	}
	if len(snapshot.Roots) != 2 {
		t.Fatalf("expected 2 roots, got %d", len(snapshot.Roots))
	}
	if snapshot.Roots[0].ID != "root_1" || snapshot.Roots[1].ID != "root_2" {
		t.Fatalf("unexpected root ids: %s, %s", snapshot.Roots[0].ID, snapshot.Roots[1].ID)
	}
	if snapshot.nextRootSeq != 3 {
		t.Fatalf("expected nextRootSeq=3, got %d", snapshot.nextRootSeq)
	}
}
