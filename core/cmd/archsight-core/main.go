package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/cmg/archsight/core/internal/ipc"
	"github.com/cmg/archsight/core/internal/search"
)

const version = "0.1.0"

func main() {
	defaultSocket := fmt.Sprintf("/tmp/archsight-core-%d.sock", os.Getpid())
	socketPath := flag.String("socket", defaultSocket, "Unix Domain Socket path")
	flag.Parse()

	rgPath := search.ResolveRipgrepPath(search.ResolveOptions{
		ExecutableDir: executableDir(),
	})

	server := ipc.NewServer(ipc.Config{
		SocketPath: *socketPath,
		Version:    version,
		Searcher:   search.NewRipgrepSearcher(search.Options{Path: rgPath}),
	})

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-signals
		_ = server.Shutdown()
	}()

	if err := server.ListenAndServe(); err != nil {
		fmt.Fprintf(os.Stderr, "archsight-core: %v\n", err)
		os.Exit(1)
	}
}

// executableDir returns the directory holding the running core binary so a
// ripgrep bundled alongside it can be discovered. It returns an empty string
// when the path cannot be resolved, which simply disables bundle lookup.
func executableDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Dir(exe)
}
