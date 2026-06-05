package fixtures

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateProducesRequestedScaleAndAnchors(t *testing.T) {
	root := t.TempDir()
	summary, err := Generate(root, GenerateOptions{Dirs: 4, FilesPerDir: 5})
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}

	if summary.Dirs != 4 {
		t.Fatalf("expected 4 dirs, got %d", summary.Dirs)
	}
	// 4*5 leaf files plus main.go and target.go.
	if summary.Files != 22 {
		t.Fatalf("expected 22 files, got %d", summary.Files)
	}
	if summary.Needles != 20 {
		t.Fatalf("expected 20 needles, got %d", summary.Needles)
	}

	for _, anchor := range []string{"main.go", "target.go"} {
		if _, err := os.Stat(filepath.Join(root, anchor)); err != nil {
			t.Fatalf("expected anchor %s: %v", anchor, err)
		}
	}
}

func TestGenerateDefaultsWhenZero(t *testing.T) {
	root := t.TempDir()
	summary, err := Generate(root, GenerateOptions{})
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}
	if summary.Dirs == 0 || summary.Files <= 2 {
		t.Fatalf("expected non-trivial default workspace, got %+v", summary)
	}
}

func TestNeedleCountMatchesSummary(t *testing.T) {
	root := t.TempDir()
	summary, err := Generate(root, GenerateOptions{Dirs: 3, FilesPerDir: 3})
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}

	count := 0
	err = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		count += strings.Count(string(content), NeedleToken)
		return nil
	})
	if err != nil {
		t.Fatalf("walk error: %v", err)
	}
	if count != summary.Needles {
		t.Fatalf("expected %d needles on disk, found %d", summary.Needles, count)
	}
}

func TestManifestDiffDetectsChanges(t *testing.T) {
	root := t.TempDir()
	if _, err := Generate(root, GenerateOptions{Dirs: 2, FilesPerDir: 2}); err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}

	before, err := Manifest(root)
	if err != nil {
		t.Fatalf("Manifest returned error: %v", err)
	}

	// Identical re-read yields an empty diff.
	after, err := Manifest(root)
	if err != nil {
		t.Fatalf("Manifest returned error: %v", err)
	}
	if diff := DiffManifests(before, after); !diff.Empty() {
		t.Fatalf("expected empty diff, got %s", diff)
	}

	// Mutating one file is detected as a change.
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("changed"), 0o644); err != nil {
		t.Fatalf("write error: %v", err)
	}
	// Adding a file is detected as an addition.
	if err := os.WriteFile(filepath.Join(root, "added.txt"), []byte("new"), 0o644); err != nil {
		t.Fatalf("write error: %v", err)
	}
	mutated, err := Manifest(root)
	if err != nil {
		t.Fatalf("Manifest returned error: %v", err)
	}
	diff := DiffManifests(before, mutated)
	if diff.Empty() {
		t.Fatal("expected non-empty diff after mutation")
	}
	if len(diff.Changed) != 1 || diff.Changed[0] != "main.go" {
		t.Fatalf("expected main.go changed, got %v", diff.Changed)
	}
	if len(diff.Added) != 1 || diff.Added[0] != "added.txt" {
		t.Fatalf("expected added.txt added, got %v", diff.Added)
	}
}

func TestDiffManifestsDetectsRemoval(t *testing.T) {
	before := map[string]string{"a": "1", "b": "2"}
	after := map[string]string{"a": "1"}
	diff := DiffManifests(before, after)
	if len(diff.Removed) != 1 || diff.Removed[0] != "b" {
		t.Fatalf("expected b removed, got %v", diff.Removed)
	}
}
