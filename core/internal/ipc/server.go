package ipc

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"sync"
)

type Config struct {
	SocketPath string
	Version    string
}

type Server struct {
	config   Config
	listener net.Listener
	done     chan struct{}
	once     sync.Once
}

type HealthResult struct {
	Version string `json:"version"`
	PID     int    `json:"pid"`
}

func NewServer(config Config) *Server {
	return &Server{
		config: config,
		done:   make(chan struct{}),
	}
}

func (s *Server) ListenAndServe() error {
	if s.config.SocketPath == "" {
		return NewError("invalid_config", "Socket path is required")
	}
	if err := os.MkdirAll(filepath.Dir(s.config.SocketPath), 0o755); err != nil {
		return err
	}
	if err := os.Remove(s.config.SocketPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}

	listener, err := net.Listen("unix", s.config.SocketPath)
	if err != nil {
		return err
	}
	s.listener = listener

	for {
		conn, err := listener.Accept()
		if err != nil {
			select {
			case <-s.done:
				_ = os.Remove(s.config.SocketPath)
				return nil
			default:
				return err
			}
		}
		go s.handleConn(conn)
	}
}

func (s *Server) Shutdown() error {
	var err error
	s.once.Do(func() {
		close(s.done)
		if s.listener != nil {
			err = s.listener.Close()
		}
	})
	if errors.Is(err, net.ErrClosed) {
		return nil
	}
	return err
}

func (s *Server) handleConn(conn net.Conn) {
	defer conn.Close()

	scanner := bufio.NewScanner(conn)
	for scanner.Scan() {
		req, err := DecodeRequest(scanner.Bytes())
		if err != nil {
			_ = writeResponse(conn, ErrorResponse("", err))
			continue
		}
		_ = writeResponse(conn, s.dispatch(req))
	}
	if err := scanner.Err(); err != nil && !errors.Is(err, io.EOF) {
		return
	}
}

func (s *Server) dispatch(req Request) Response {
	switch req.Method {
	case "health":
		return SuccessResponse(req.ID, HealthResult{
			Version: s.config.Version,
			PID:     os.Getpid(),
		})
	default:
		return ErrorResponse(req.ID, NewError("unsupported_method", "Unsupported method: "+req.Method))
	}
}

func writeResponse(w io.Writer, resp Response) error {
	encoded, err := json.Marshal(resp)
	if err != nil {
		return err
	}
	_, err = w.Write(append(encoded, '\n'))
	return err
}
