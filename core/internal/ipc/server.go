package ipc

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"sync"

	"github.com/cmg/archsight/core/internal/workspace"
)

type Config struct {
	SocketPath       string
	Version          string
	WorkspaceManager *workspace.Manager
}

type Server struct {
	config     Config
	workspaces *workspace.Manager
	listener   net.Listener
	done       chan struct{}
	once       sync.Once
}

type HealthResult struct {
	Version string `json:"version"`
	PID     int    `json:"pid"`
}

func NewServer(config Config) *Server {
	manager := config.WorkspaceManager
	if manager == nil {
		manager = workspace.NewManager()
	}
	return &Server{
		config:     config,
		workspaces: manager,
		done:       make(chan struct{}),
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
	case "openWorkspace":
		return s.openWorkspace(req)
	case "listTree":
		return s.listTree(req)
	case "cancel":
		return s.cancel(req)
	default:
		return ErrorResponse(req.ID, NewError("unsupported_method", "Unsupported method: "+req.Method))
	}
}

type openWorkspaceParams struct {
	Roots []string `json:"roots"`
}

type openWorkspaceResult struct {
	WorkspaceID string           `json:"workspaceId"`
	Status      workspace.Status `json:"status"`
	Roots       []workspace.Root `json:"roots"`
}

type listTreeParams struct {
	WorkspaceID string `json:"workspaceId"`
}

type listTreeResult struct {
	WorkspaceID string            `json:"workspaceId"`
	Status      workspace.Status  `json:"status"`
	Roots       []workspace.Root  `json:"roots"`
	Entries     []workspace.Entry `json:"entries"`
	Error       string            `json:"error,omitempty"`
}

type cancelParams struct {
	TargetID    string `json:"targetId"`
	WorkspaceID string `json:"workspaceId"`
}

func (s *Server) openWorkspace(req Request) Response {
	var params openWorkspaceParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	snapshot, err := s.workspaces.Open(context.Background(), params.Roots)
	if err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	return SuccessResponse(req.ID, openWorkspaceResult{
		WorkspaceID: snapshot.ID,
		Status:      snapshot.Status,
		Roots:       snapshot.Roots,
	})
}

func (s *Server) listTree(req Request) Response {
	var params listTreeParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	snapshot, ok := s.workspaces.Get(params.WorkspaceID)
	if !ok {
		return ErrorResponse(req.ID, NewError("not_found", "Workspace not found: "+params.WorkspaceID))
	}
	return SuccessResponse(req.ID, listTreeResult{
		WorkspaceID: snapshot.ID,
		Status:      snapshot.Status,
		Roots:       snapshot.Roots,
		Entries:     snapshot.Entries,
		Error:       snapshot.Error,
	})
}

func (s *Server) cancel(req Request) Response {
	var params cancelParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	targetID := params.WorkspaceID
	if targetID == "" {
		targetID = params.TargetID
	}
	if targetID == "" {
		return ErrorResponse(req.ID, NewError("invalid_params", "targetId or workspaceId is required"))
	}
	if !s.workspaces.Cancel(targetID) {
		return ErrorResponse(req.ID, NewError("not_found", "Cancelable work not found: "+targetID))
	}
	return SuccessResponse(req.ID, map[string]any{"canceled": true})
}

func writeResponse(w io.Writer, resp Response) error {
	encoded, err := json.Marshal(resp)
	if err != nil {
		return err
	}
	_, err = w.Write(append(encoded, '\n'))
	return err
}
