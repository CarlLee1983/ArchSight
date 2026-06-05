package search

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/cmg/archsight/core/internal/workspace"
)

func TestRipgrepSearcherFindsMatchesWithRootIdentity(t *testing.T) {
	rootA := makeSearchRoot(t, "service-a", map[string]string{
		"cmd/main.go":           "package main\nfunc main() { println(\"needle\") }\n",
		"node_modules/skip.js":  "needle\n",
		"internal/no-match.txt": "haystack\n",
	})
	rootB := makeSearchRoot(t, "service-b", map[string]string{
		"Sources/App.swift": "let value = \"needle\"\n",
		".git/config":       "needle\n",
	})

	searcher := NewRipgrepSearcher(Options{})
	var matches []Match
	err := searcher.Search(context.Background(), Request{
		Pattern: "needle",
		Roots: []workspace.Root{
			{ID: "root_1", Name: "service-a", Path: rootA},
			{ID: "root_2", Name: "service-b", Path: rootB},
		},
	}, func(match Match) error {
		matches = append(matches, match)
		return nil
	})
	if err != nil {
		t.Fatalf("Search returned error: %v", err)
	}

	paths := matchPaths(matches)
	if !slices.Contains(paths, "root_1:cmd/main.go") {
		t.Fatalf("expected root_1 cmd/main.go match, got %v", paths)
	}
	if !slices.Contains(paths, "root_2:Sources/App.swift") {
		t.Fatalf("expected root_2 Sources/App.swift match, got %v", paths)
	}
	for _, path := range paths {
		if path == "root_1:node_modules/skip.js" || path == "root_2:.git/config" {
			t.Fatalf("search returned ignored path: %s", path)
		}
	}

	first := matches[0]
	if first.Line == 0 || first.Column == 0 || first.Preview == "" {
		t.Fatalf("match missing location or preview: %+v", first)
	}
	if len(first.Ranges) == 0 || first.Ranges[0].Start == first.Ranges[0].End {
		t.Fatalf("match missing ranges: %+v", first.Ranges)
	}
}

func TestRipgrepSearcherReturnsStructuredInvalidPatternError(t *testing.T) {
	root := makeSearchRoot(t, "service", map[string]string{"main.go": "package main\n"})
	searcher := NewRipgrepSearcher(Options{})

	err := searcher.Search(context.Background(), Request{
		Pattern: "[",
		Roots:   []workspace.Root{{ID: "root_1", Name: "service", Path: root}},
	}, func(Match) error {
		t.Fatal("unexpected match")
		return nil
	})
	if err == nil {
		t.Fatal("expected invalid pattern error")
	}

	var searchErr *Error
	if !errors.As(err, &searchErr) {
		t.Fatalf("expected *Error, got %T", err)
	}
	if searchErr.Code != "invalid_pattern" {
		t.Fatalf("expected invalid_pattern, got %q", searchErr.Code)
	}
}

func TestRipgrepSearcherCancelsRunningSearch(t *testing.T) {
	root := makeSearchRoot(t, "service", map[string]string{"main.go": "needle\n"})
	searcher := NewRipgrepSearcher(Options{Path: "/bin/sh"})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	start := time.Now()
	err := searcher.Search(ctx, Request{
		Pattern: "needle",
		Roots:   []workspace.Root{{ID: "root_1", Name: "service", Path: root}},
	}, func(Match) error {
		t.Fatal("unexpected match")
		return nil
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled, got %v", err)
	}
	if time.Since(start) > time.Second {
		t.Fatal("cancellation was not prompt")
	}
}

func TestRipgrepCommandIncludesJSONAndIgnoreRules(t *testing.T) {
	searcher := NewRipgrepSearcher(Options{Path: "/usr/bin/rg"})
	cmd := searcher.command(context.Background(), Request{
		Pattern: "needle",
		Roots: []workspace.Root{
			{ID: "root_1", Name: "service", Path: "/repo/service"},
		},
	})

	args := cmd.Args
	for _, want := range []string{"--json", "--line-number", "--column", "--glob", "!node_modules/**", "--glob", "!.git/**"} {
		if !slices.Contains(args, want) {
			t.Fatalf("expected command args to contain %q, got %v", want, args)
		}
	}
	if args[len(args)-2] != "needle" || args[len(args)-1] != "/repo/service" {
		t.Fatalf("expected pattern and root at end, got %v", args)
	}
}

func makeSearchRoot(t *testing.T, name string, files map[string]string) string {
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

func matchPaths(matches []Match) []string {
	paths := make([]string, 0, len(matches))
	for _, match := range matches {
		paths = append(paths, match.RootID+":"+match.Path)
	}
	slices.Sort(paths)
	return paths
}
