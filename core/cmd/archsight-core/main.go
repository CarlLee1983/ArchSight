package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/cmg/archsight/core/internal/ipc"
)

const version = "0.1.0"

func main() {
	defaultSocket := fmt.Sprintf("/tmp/archsight-core-%d.sock", os.Getpid())
	socketPath := flag.String("socket", defaultSocket, "Unix Domain Socket path")
	flag.Parse()

	server := ipc.NewServer(ipc.Config{
		SocketPath: *socketPath,
		Version:    version,
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
