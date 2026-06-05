// Package fixtures generates synthetic, read-only workspaces for performance
// and reliability checks, plus a content manifest used to prove that opening a
// workspace never writes into the user's source roots.
package fixtures

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// NeedleToken is embedded once per generated leaf file so a single search
// pattern has a deterministic, countable number of matches.
const NeedleToken = "ARCHSIGHT_NEEDLE"

// GenerateOptions controls the shape of a synthetic workspace. Zero values fall
// back to a small default so callers can opt into "large" explicitly.
type GenerateOptions struct {
	// Dirs is the number of package-like subdirectories created under the root.
	Dirs int
	// FilesPerDir is the number of leaf source files created in each directory.
	FilesPerDir int
}

func (o GenerateOptions) withDefaults() GenerateOptions {
	if o.Dirs <= 0 {
		o.Dirs = 8
	}
	if o.FilesPerDir <= 0 {
		o.FilesPerDir = 8
	}
	return o
}

// Summary reports what Generate produced so callers can assert on scale.
type Summary struct {
	Dirs    int
	Files   int
	Needles int
}

// Generate writes a deterministic synthetic workspace into root. It always
// creates main.go and target.go at the root so the definition/openFile flow has
// a stable symbol to navigate, then fills Dirs subdirectories with FilesPerDir
// leaf files that each contain exactly one NeedleToken occurrence.
func Generate(root string, opts GenerateOptions) (Summary, error) {
	opts = opts.withDefaults()
	if err := os.MkdirAll(root, 0o755); err != nil {
		return Summary{}, err
	}

	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte(mainGo), 0o644); err != nil {
		return Summary{}, err
	}
	if err := os.WriteFile(filepath.Join(root, "target.go"), []byte(targetGo), 0o644); err != nil {
		return Summary{}, err
	}

	summary := Summary{Files: 2}
	for d := 0; d < opts.Dirs; d++ {
		dir := filepath.Join(root, fmt.Sprintf("pkg%04d", d))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return Summary{}, err
		}
		summary.Dirs++
		for f := 0; f < opts.FilesPerDir; f++ {
			name := fmt.Sprintf("file%04d.go", f)
			if err := os.WriteFile(filepath.Join(dir, name), []byte(leafFile(d, f)), 0o644); err != nil {
				return Summary{}, err
			}
			summary.Files++
			summary.Needles++
		}
	}
	return summary, nil
}

const mainGo = `package main

func main() {
	Target()
}
`

const targetGo = `package main

// Target is the symbol used by navigation smoke checks.
func Target() {}
`

func leafFile(dir, file int) string {
	return fmt.Sprintf(`package pkg%04d

// Symbol%04d_%04d references the shared search token: %s
func Symbol%04d_%04d() int {
	return %d
}
`, dir, dir, file, NeedleToken, dir, file, dir*1000+file)
}

// Manifest maps each regular file's slash-relative path to a content hash. It is
// used to detect any write into a workspace by comparing before/after snapshots.
func Manifest(root string) (map[string]string, error) {
	manifest := make(map[string]string)
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(content)
		manifest[filepath.ToSlash(rel)] = hex.EncodeToString(sum[:])
		return nil
	})
	if err != nil {
		return nil, err
	}
	return manifest, nil
}

// ManifestDiff describes how an after-manifest differs from a before-manifest.
type ManifestDiff struct {
	Added   []string
	Removed []string
	Changed []string
}

// Empty reports whether the two manifests are identical.
func (d ManifestDiff) Empty() bool {
	return len(d.Added) == 0 && len(d.Removed) == 0 && len(d.Changed) == 0
}

func (d ManifestDiff) String() string {
	parts := make([]string, 0, 3)
	if len(d.Added) > 0 {
		parts = append(parts, "added="+strings.Join(d.Added, ","))
	}
	if len(d.Removed) > 0 {
		parts = append(parts, "removed="+strings.Join(d.Removed, ","))
	}
	if len(d.Changed) > 0 {
		parts = append(parts, "changed="+strings.Join(d.Changed, ","))
	}
	if len(parts) == 0 {
		return "no changes"
	}
	return strings.Join(parts, "; ")
}

// DiffManifests returns the paths added, removed, or changed between before and
// after. A read-only workspace operation must produce an empty diff.
func DiffManifests(before, after map[string]string) ManifestDiff {
	var diff ManifestDiff
	for path, hash := range after {
		prev, ok := before[path]
		switch {
		case !ok:
			diff.Added = append(diff.Added, path)
		case prev != hash:
			diff.Changed = append(diff.Changed, path)
		}
	}
	for path := range before {
		if _, ok := after[path]; !ok {
			diff.Removed = append(diff.Removed, path)
		}
	}
	sort.Strings(diff.Added)
	sort.Strings(diff.Removed)
	sort.Strings(diff.Changed)
	return diff
}
