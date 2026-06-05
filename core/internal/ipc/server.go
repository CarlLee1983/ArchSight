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
	"strings"
	"sync"

	"github.com/cmg/archsight/core/internal/lsp"
	"github.com/cmg/archsight/core/internal/search"
	"github.com/cmg/archsight/core/internal/syntax"
	"github.com/cmg/archsight/core/internal/workspace"
)

type Config struct {
	SocketPath       string
	Version          string
	WorkspaceManager *workspace.Manager
	Searcher         search.Searcher
	Navigator        lsp.Navigator
}

type Server struct {
	config     Config
	workspaces *workspace.Manager
	searcher   search.Searcher
	navigator  lsp.Navigator
	listener   net.Listener
	done       chan struct{}
	once       sync.Once
	activeMu   sync.Mutex
	active     map[string]context.CancelFunc
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
	searcher := config.Searcher
	if searcher == nil {
		searcher = search.NewRipgrepSearcher(search.Options{})
	}
	navigator := config.Navigator
	if navigator == nil {
		navigator = lsp.NewManager(lsp.Options{})
	}
	return &Server{
		config:     config,
		workspaces: manager,
		searcher:   searcher,
		navigator:  navigator,
		done:       make(chan struct{}),
		active:     make(map[string]context.CancelFunc),
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
		if shutdowner, ok := s.navigator.(interface{ Shutdown() }); ok {
			shutdowner.Shutdown()
		}
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
	case "openFile":
		return s.openFile(req)
	case "search":
		return s.search(req)
	case "definition":
		return s.definition(req)
	case "references":
		return s.references(req)
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

type searchParams struct {
	WorkspaceID string `json:"workspaceId"`
	Pattern     string `json:"pattern"`
}

type searchResult struct {
	Matches []search.Match `json:"matches"`
}

type openFileParams struct {
	WorkspaceID string `json:"workspaceId"`
	RootID      string `json:"rootId"`
	Path        string `json:"path"`
}

type navigationParams struct {
	WorkspaceID string `json:"workspaceId"`
	RootID      string `json:"rootId"`
	Path        string `json:"path"`
	Line        int    `json:"line"`
	Column      int    `json:"column"`
}

type navigationResult struct {
	Locations []lsp.Location `json:"locations"`
}

type openFileResult struct {
	RootID   string         `json:"rootId"`
	RootPath string         `json:"rootPath"`
	Path     string         `json:"path"`
	Language string         `json:"language"`
	Content  string         `json:"content"`
	Tokens   []syntax.Token `json:"tokens"`
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

func (s *Server) openFile(req Request) Response {
	var params openFileParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	if params.WorkspaceID == "" || params.RootID == "" || params.Path == "" {
		return ErrorResponse(req.ID, NewError("invalid_params", "workspaceId, rootId, and path are required"))
	}

	snapshot, ok := s.workspaces.Get(params.WorkspaceID)
	if !ok {
		return ErrorResponse(req.ID, NewError("not_found", "Workspace not found: "+params.WorkspaceID))
	}
	if snapshot.Status != workspace.StatusReady {
		return ErrorResponse(req.ID, NewError("workspace_not_ready", "Workspace is not ready: "+params.WorkspaceID))
	}

	root, ok := findRoot(snapshot.Roots, params.RootID)
	if !ok {
		return ErrorResponse(req.ID, NewError("not_found", "Workspace root not found: "+params.RootID))
	}
	fullPath, relPath, err := resolveWorkspaceFile(root.Path, params.Path)
	if err != nil {
		return ErrorResponse(req.ID, err)
	}
	if !snapshotHasFile(snapshot.Entries, root.ID, relPath) {
		return ErrorResponse(req.ID, NewError("not_found", "File not found in workspace snapshot: "+relPath))
	}
	info, err := os.Stat(fullPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return ErrorResponse(req.ID, NewError("not_found", "File not found: "+relPath))
		}
		return ErrorResponse(req.ID, err)
	}
	if info.IsDir() {
		return ErrorResponse(req.ID, NewError("invalid_path", "Path is a directory: "+relPath))
	}

	content, err := os.ReadFile(fullPath)
	if err != nil {
		return ErrorResponse(req.ID, err)
	}
	highlight := syntax.Highlight(relPath, string(content))
	return SuccessResponse(req.ID, openFileResult{
		RootID:   root.ID,
		RootPath: root.Path,
		Path:     relPath,
		Language: highlight.Language,
		Content:  string(content),
		Tokens:   highlight.Tokens,
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
	if s.cancelActive(targetID) {
		return SuccessResponse(req.ID, map[string]any{"canceled": true})
	}
	if !s.workspaces.Cancel(targetID) {
		return ErrorResponse(req.ID, NewError("not_found", "Cancelable work not found: "+targetID))
	}
	return SuccessResponse(req.ID, map[string]any{"canceled": true})
}

func (s *Server) search(req Request) Response {
	var params searchParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	snapshot, ok := s.workspaces.Get(params.WorkspaceID)
	if !ok {
		return ErrorResponse(req.ID, NewError("not_found", "Workspace not found: "+params.WorkspaceID))
	}
	if snapshot.Status != workspace.StatusReady {
		return ErrorResponse(req.ID, NewError("workspace_not_ready", "Workspace is not ready: "+params.WorkspaceID))
	}

	var matches []search.Match
	ctx, cancel := context.WithCancel(context.Background())
	s.trackActive(req.ID, cancel)
	defer s.untrackActive(req.ID)

	err := s.searcher.Search(ctx, search.Request{
		Pattern: params.Pattern,
		Roots:   snapshot.Roots,
	}, func(match search.Match) error {
		matches = append(matches, match)
		return nil
	})
	if err != nil {
		if errors.Is(err, context.Canceled) {
			return ErrorResponse(req.ID, NewError("context_canceled", "Request canceled"))
		}
		var searchErr *search.Error
		if search.AsError(err, &searchErr) {
			return ErrorResponse(req.ID, NewError(searchErr.Code, searchErr.Message))
		}
		return ErrorResponse(req.ID, err)
	}
	return SuccessResponse(req.ID, searchResult{Matches: matches})
}

func (s *Server) definition(req Request) Response {
	return s.navigate(req, func(ctx context.Context, navReq lsp.Request) ([]lsp.Location, error) {
		return s.navigator.Definition(ctx, navReq)
	})
}

func (s *Server) references(req Request) Response {
	return s.navigate(req, func(ctx context.Context, navReq lsp.Request) ([]lsp.Location, error) {
		return s.navigator.References(ctx, navReq)
	})
}

func (s *Server) navigate(req Request, call func(context.Context, lsp.Request) ([]lsp.Location, error)) Response {
	navReq, respErr := s.navigationRequest(req)
	if respErr != nil {
		return *respErr
	}

	ctx, cancel := context.WithCancel(context.Background())
	s.trackActive(req.ID, cancel)
	defer s.untrackActive(req.ID)

	locations, err := call(ctx, navReq)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			return ErrorResponse(req.ID, NewError("context_canceled", "Request canceled"))
		}
		var lspErr *lsp.Error
		if lsp.AsError(err, &lspErr) {
			return ErrorResponse(req.ID, NewError(lspErr.Code, lspErr.Message))
		}
		return ErrorResponse(req.ID, err)
	}
	return SuccessResponse(req.ID, navigationResult{Locations: locations})
}

func (s *Server) navigationRequest(req Request) (lsp.Request, *Response) {
	var params navigationParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		resp := ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
		return lsp.Request{}, &resp
	}
	if params.WorkspaceID == "" || params.RootID == "" || params.Path == "" || params.Line <= 0 || params.Column <= 0 {
		resp := ErrorResponse(req.ID, NewError("invalid_params", "workspaceId, rootId, path, line, and column are required"))
		return lsp.Request{}, &resp
	}

	snapshot, ok := s.workspaces.Get(params.WorkspaceID)
	if !ok {
		resp := ErrorResponse(req.ID, NewError("not_found", "Workspace not found: "+params.WorkspaceID))
		return lsp.Request{}, &resp
	}
	if snapshot.Status != workspace.StatusReady {
		resp := ErrorResponse(req.ID, NewError("workspace_not_ready", "Workspace is not ready: "+params.WorkspaceID))
		return lsp.Request{}, &resp
	}
	root, ok := findRoot(snapshot.Roots, params.RootID)
	if !ok {
		resp := ErrorResponse(req.ID, NewError("not_found", "Workspace root not found: "+params.RootID))
		return lsp.Request{}, &resp
	}
	_, relPath, err := resolveWorkspaceFile(root.Path, params.Path)
	if err != nil {
		resp := ErrorResponse(req.ID, err)
		return lsp.Request{}, &resp
	}
	if !snapshotHasFile(snapshot.Entries, root.ID, relPath) {
		resp := ErrorResponse(req.ID, NewError("not_found", "File not found in workspace snapshot: "+relPath))
		return lsp.Request{}, &resp
	}

	return lsp.Request{
		Root:     root,
		Language: syntax.DetectLanguage(relPath),
		Path:     relPath,
		Line:     params.Line,
		Column:   params.Column,
	}, nil
}

func findRoot(roots []workspace.Root, rootID string) (workspace.Root, bool) {
	for _, root := range roots {
		if root.ID == rootID {
			return root, true
		}
	}
	return workspace.Root{}, false
}

func snapshotHasFile(entries []workspace.Entry, rootID, relPath string) bool {
	for _, entry := range entries {
		if entry.RootID == rootID && entry.Path == relPath && entry.Kind == workspace.KindFile {
			return true
		}
	}
	return false
}

func resolveWorkspaceFile(rootPath, requestedPath string) (string, string, error) {
	if filepath.IsAbs(requestedPath) {
		return "", "", NewError("invalid_path", "Path must be relative to the workspace root")
	}
	cleanRel := filepath.Clean(requestedPath)
	if cleanRel == "." || strings.HasPrefix(cleanRel, ".."+string(filepath.Separator)) || cleanRel == ".." {
		return "", "", NewError("invalid_path", "Path escapes the workspace root")
	}

	fullPath := filepath.Join(rootPath, cleanRel)
	rel, err := filepath.Rel(rootPath, fullPath)
	if err != nil {
		return "", "", err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", "", NewError("invalid_path", "Path escapes the workspace root")
	}
	return fullPath, filepath.ToSlash(rel), nil
}

func (s *Server) trackActive(id string, cancel context.CancelFunc) {
	s.activeMu.Lock()
	defer s.activeMu.Unlock()

	s.active[id] = cancel
}

func (s *Server) untrackActive(id string) {
	s.activeMu.Lock()
	defer s.activeMu.Unlock()

	delete(s.active, id)
}

func (s *Server) cancelActive(id string) bool {
	s.activeMu.Lock()
	cancel, ok := s.active[id]
	s.activeMu.Unlock()
	if !ok {
		return false
	}

	cancel()
	return true
}

func writeResponse(w io.Writer, resp Response) error {
	encoded, err := json.Marshal(resp)
	if err != nil {
		return err
	}
	_, err = w.Write(append(encoded, '\n'))
	return err
}
