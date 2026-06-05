package search

import (
	"io/fs"
	"os"
	"path/filepath"
)

// RipgrepEnvVar is the explicit override for the ripgrep binary path. When set
// and non-empty it wins over bundled and PATH discovery, which keeps development
// and packaging overrides simple and predictable.
const RipgrepEnvVar = "ARCHSIGHT_RG_PATH"

// bundledRipgrepName is the file name looked up next to the core executable when
// ripgrep ships inside the macOS app bundle.
const bundledRipgrepName = "rg"

// ResolveOptions carries the seams ResolveRipgrepPath needs so the resolution
// order can be tested without touching the real process environment.
type ResolveOptions struct {
	// Getenv reads an environment variable. Defaults to os.Getenv.
	Getenv func(string) string
	// ExecutableDir is the directory holding the running core binary. A bundled
	// ripgrep is expected at ExecutableDir/rg. Empty disables bundle lookup.
	ExecutableDir string
	// Stat reports whether a candidate bundled path exists. Defaults to os.Stat.
	Stat func(string) (fs.FileInfo, error)
}

// ResolveRipgrepPath returns the ripgrep path the core should run. Resolution
// order is: explicit ARCHSIGHT_RG_PATH override, a binary bundled next to the
// core executable, then the bare "rg" name so exec resolves it from PATH at run
// time. The bare-name fallback keeps development on a system ripgrep working
// without any configuration.
func ResolveRipgrepPath(options ResolveOptions) string {
	getenv := options.Getenv
	if getenv == nil {
		getenv = os.Getenv
	}
	stat := options.Stat
	if stat == nil {
		stat = os.Stat
	}

	if override := getenv(RipgrepEnvVar); override != "" {
		return override
	}

	if options.ExecutableDir != "" {
		candidate := filepath.Join(options.ExecutableDir, bundledRipgrepName)
		if info, err := stat(candidate); err == nil && !info.IsDir() {
			return candidate
		}
	}

	return bundledRipgrepName
}
