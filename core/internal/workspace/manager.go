package workspace

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
)

type Status string

const (
	StatusScanning Status = "scanning"
	StatusReady    Status = "ready"
	StatusCanceled Status = "canceled"
	StatusFailed   Status = "failed"
)

type Kind string

const (
	KindDirectory Kind = "directory"
	KindFile      Kind = "file"
)

type Root struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Path string `json:"path"`
}

type Entry struct {
	RootID   string `json:"rootId"`
	RootPath string `json:"rootPath"`
	Path     string `json:"path"`
	Name     string `json:"name"`
	Kind     Kind   `json:"kind"`
}

type Snapshot struct {
	ID      string  `json:"id"`
	Status  Status  `json:"status"`
	Roots   []Root  `json:"roots"`
	Entries []Entry `json:"entries"`
	Error   string  `json:"error,omitempty"`
}

type Manager struct {
	mu        sync.RWMutex
	nextID    atomic.Uint64
	snapshots map[string]*Snapshot
	cancels   map[string]context.CancelFunc

	beforeEntry func()
}

func NewManager() *Manager {
	return &Manager{
		snapshots: make(map[string]*Snapshot),
		cancels:   make(map[string]context.CancelFunc),
	}
}

func (m *Manager) Open(parent context.Context, rootPaths []string) (Snapshot, error) {
	roots, err := buildRoots(rootPaths)
	if err != nil {
		return Snapshot{}, err
	}

	id := fmt.Sprintf("ws_%d", m.nextID.Add(1))
	ctx, cancel := context.WithCancel(parent)
	snapshot := &Snapshot{
		ID:     id,
		Status: StatusScanning,
		Roots:  roots,
	}

	m.mu.Lock()
	m.snapshots[id] = snapshot
	m.cancels[id] = cancel
	m.mu.Unlock()

	go m.scan(ctx, id, roots)

	return cloneSnapshot(snapshot), nil
}

func (m *Manager) Get(id string) (Snapshot, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	snapshot, ok := m.snapshots[id]
	if !ok {
		return Snapshot{}, false
	}
	return cloneSnapshot(snapshot), true
}

func (m *Manager) Cancel(id string) bool {
	m.mu.RLock()
	cancel, ok := m.cancels[id]
	m.mu.RUnlock()
	if !ok {
		return false
	}

	cancel()
	return true
}

func (m *Manager) scan(ctx context.Context, id string, roots []Root) {
	var entries []Entry
	for _, root := range roots {
		if err := m.scanRoot(ctx, root, &entries); err != nil {
			m.finish(id, err, entries)
			return
		}
	}
	slices.SortFunc(entries, func(a, b Entry) int {
		if a.RootID != b.RootID {
			return strings.Compare(a.RootID, b.RootID)
		}
		return strings.Compare(a.Path, b.Path)
	})
	m.finish(id, nil, entries)
}

func (m *Manager) finish(id string, err error, entries []Entry) {
	m.mu.Lock()
	defer m.mu.Unlock()

	snapshot, ok := m.snapshots[id]
	if !ok {
		return
	}
	snapshot.Entries = slices.Clone(entries)
	switch {
	case errors.Is(err, context.Canceled):
		snapshot.Status = StatusCanceled
	case err != nil:
		snapshot.Status = StatusFailed
		snapshot.Error = err.Error()
	default:
		snapshot.Status = StatusReady
	}
	delete(m.cancels, id)
}

func buildRoots(rootPaths []string) ([]Root, error) {
	if len(rootPaths) == 0 {
		return nil, errors.New("at least one root path is required")
	}

	roots := make([]Root, 0, len(rootPaths))
	for i, rootPath := range rootPaths {
		cleaned, err := filepath.Abs(rootPath)
		if err != nil {
			return nil, err
		}
		info, err := os.Stat(cleaned)
		if err != nil {
			return nil, err
		}
		if !info.IsDir() {
			return nil, fmt.Errorf("workspace root is not a directory: %s", cleaned)
		}
		roots = append(roots, Root{
			ID:   fmt.Sprintf("root_%d", i+1),
			Name: filepath.Base(cleaned),
			Path: cleaned,
		})
	}
	return roots, nil
}

func (m *Manager) scanRoot(ctx context.Context, root Root, entries *[]Entry) error {
	return filepath.WalkDir(root.Path, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if m.beforeEntry != nil {
			m.beforeEntry()
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if path == root.Path {
			return nil
		}

		name := d.Name()
		if d.IsDir() && shouldIgnoreDir(name) {
			return filepath.SkipDir
		}

		rel, err := filepath.Rel(root.Path, path)
		if err != nil {
			return err
		}
		kind := KindFile
		if d.IsDir() {
			kind = KindDirectory
		}
		*entries = append(*entries, Entry{
			RootID:   root.ID,
			RootPath: root.Path,
			Path:     filepath.ToSlash(rel),
			Name:     name,
			Kind:     kind,
		})
		return nil
	})
}

func shouldIgnoreDir(name string) bool {
	switch name {
	case ".git", "node_modules", "build", ".next", "DerivedData", "vendor", ".cache":
		return true
	default:
		return false
	}
}

func cloneSnapshot(snapshot *Snapshot) Snapshot {
	return Snapshot{
		ID:      snapshot.ID,
		Status:  snapshot.Status,
		Roots:   slices.Clone(snapshot.Roots),
		Entries: slices.Clone(snapshot.Entries),
		Error:   snapshot.Error,
	}
}
