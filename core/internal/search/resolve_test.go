package search

import (
	"io/fs"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type fakeFileInfo struct {
	dir bool
}

func (f fakeFileInfo) Name() string       { return "rg" }
func (f fakeFileInfo) Size() int64        { return 0 }
func (f fakeFileInfo) Mode() fs.FileMode  { return 0 }
func (f fakeFileInfo) ModTime() time.Time { return time.Time{} }
func (f fakeFileInfo) IsDir() bool        { return f.dir }
func (f fakeFileInfo) Sys() any           { return nil }

func TestResolveRipgrepPathPrefersEnvOverride(t *testing.T) {
	path := ResolveRipgrepPath(ResolveOptions{
		Getenv:        func(string) string { return "/custom/rg" },
		ExecutableDir: "/app/bin",
		Stat: func(string) (fs.FileInfo, error) {
			return fakeFileInfo{}, nil
		},
	})
	if path != "/custom/rg" {
		t.Fatalf("expected env override, got %q", path)
	}
}

func TestResolveRipgrepPathUsesBundledBinary(t *testing.T) {
	path := ResolveRipgrepPath(ResolveOptions{
		Getenv:        func(string) string { return "" },
		ExecutableDir: "/app/bin",
		Stat: func(candidate string) (fs.FileInfo, error) {
			if candidate == filepath.Join("/app/bin", "rg") {
				return fakeFileInfo{}, nil
			}
			return nil, os.ErrNotExist
		},
	})
	if path != filepath.Join("/app/bin", "rg") {
		t.Fatalf("expected bundled rg, got %q", path)
	}
}

func TestResolveRipgrepPathIgnoresBundledDirectory(t *testing.T) {
	path := ResolveRipgrepPath(ResolveOptions{
		Getenv:        func(string) string { return "" },
		ExecutableDir: "/app/bin",
		Stat: func(string) (fs.FileInfo, error) {
			return fakeFileInfo{dir: true}, nil
		},
	})
	if path != "rg" {
		t.Fatalf("expected PATH fallback when candidate is a directory, got %q", path)
	}
}

func TestResolveRipgrepPathFallsBackToPathName(t *testing.T) {
	path := ResolveRipgrepPath(ResolveOptions{
		Getenv:        func(string) string { return "" },
		ExecutableDir: "",
		Stat: func(string) (fs.FileInfo, error) {
			return nil, os.ErrNotExist
		},
	})
	if path != "rg" {
		t.Fatalf("expected bare rg fallback, got %q", path)
	}
}
