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
	ID          string  `json:"id"`
	Status      Status  `json:"status"`
	Roots       []Root  `json:"roots"`
	Entries     []Entry `json:"entries"`
	Error       string  `json:"error,omitempty"`
	nextRootSeq uint64
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
	roots, nextSeq, err := buildRootsFrom(rootPaths, 1)
	if err != nil {
		return Snapshot{}, err
	}

	id := fmt.Sprintf("ws_%d", m.nextID.Add(1))
	ctx, cancel := context.WithCancel(parent)
	snapshot := &Snapshot{
		ID:          id,
		Status:      StatusScanning,
		Roots:       roots,
		nextRootSeq: nextSeq,
	}

	m.mu.Lock()
	m.snapshots[id] = snapshot
	m.cancels[id] = cancel
	clone := cloneSnapshot(snapshot)
	m.mu.Unlock()

	go m.scan(ctx, id, roots)

	return clone, nil
}

// AddRoots appends new roots to an existing workspace and scans only those new
// roots, merging their entries into the snapshot. Existing root ids are never
// renumbered or reused.
func (m *Manager) AddRoots(parent context.Context, id string, rootPaths []string) (Snapshot, error) {
	m.mu.Lock()
	snapshot, ok := m.snapshots[id]
	if !ok {
		m.mu.Unlock()
		return Snapshot{}, fmt.Errorf("workspace not found: %s", id)
	}
	newRoots, nextSeq, err := buildRootsFrom(rootPaths, snapshot.nextRootSeq)
	if err != nil {
		m.mu.Unlock()
		return Snapshot{}, err
	}
	// New roots and nextRootSeq are staged optimistically under the lock; we do
	// not roll them back if the append scan fails. This is safe because AddRoots
	// is expected to be called on a settled (ready) workspace — the Swift
	// controller guarantees this via awaitReady before invoking AddRoots.
	snapshot.Roots = append(snapshot.Roots, newRoots...)
	snapshot.nextRootSeq = nextSeq
	snapshot.Status = StatusScanning
	snapshot.Error = ""
	ctx, cancel := context.WithCancel(parent)
	if old := m.cancels[id]; old != nil {
		old()
	}
	m.cancels[id] = cancel
	clone := cloneSnapshot(snapshot)
	m.mu.Unlock()

	go m.scanAppend(ctx, id, newRoots)
	return clone, nil
}

func (m *Manager) scanAppend(ctx context.Context, id string, roots []Root) {
	var newEntries []Entry
	for _, root := range roots {
		if err := m.scanRoot(ctx, root, &newEntries); err != nil {
			m.finishAppend(id, err, newEntries)
			return
		}
	}
	m.finishAppend(id, nil, newEntries)
}

func (m *Manager) finishAppend(id string, err error, newEntries []Entry) {
	m.mu.Lock()
	defer m.mu.Unlock()

	snapshot, ok := m.snapshots[id]
	if !ok {
		return
	}
	// On cancel/fail we deliberately merge no partial entries, by design:
	// keeping the existing good entries untouched avoids corrupting the
	// snapshot with a half-scanned new root.
	switch {
	case errors.Is(err, context.Canceled):
		snapshot.Status = StatusCanceled
	case err != nil:
		snapshot.Status = StatusFailed
		snapshot.Error = err.Error()
	default:
		snapshot.Entries = append(snapshot.Entries, newEntries...)
		slices.SortFunc(snapshot.Entries, func(a, b Entry) int {
			if a.RootID != b.RootID {
				return strings.Compare(a.RootID, b.RootID)
			}
			return strings.Compare(a.Path, b.Path)
		})
		snapshot.Status = StatusReady
	}
	delete(m.cancels, id)
}

// RemoveRoot removes a single root and all of its entries from the workspace.
// Remaining roots keep their ids; the id of the removed root is not reused.
func (m *Manager) RemoveRoot(id, rootID string) (Snapshot, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	snapshot, ok := m.snapshots[id]
	if !ok {
		return Snapshot{}, fmt.Errorf("workspace not found: %s", id)
	}
	index := -1
	for i, root := range snapshot.Roots {
		if root.ID == rootID {
			index = i
			break
		}
	}
	if index == -1 {
		return Snapshot{}, fmt.Errorf("workspace root not found: %s", rootID)
	}

	roots := make([]Root, 0, len(snapshot.Roots)-1)
	roots = append(roots, snapshot.Roots[:index]...)
	roots = append(roots, snapshot.Roots[index+1:]...)
	snapshot.Roots = roots

	entries := make([]Entry, 0, len(snapshot.Entries))
	for _, entry := range snapshot.Entries {
		if entry.RootID != rootID {
			entries = append(entries, entry)
		}
	}
	snapshot.Entries = entries

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
	// On cancel/fail we leave entries untouched (symmetric with finishAppend):
	// only a successful scan commits its entries, so a canceled/failed scan
	// never wipes an otherwise-good snapshot.
	switch {
	case errors.Is(err, context.Canceled):
		snapshot.Status = StatusCanceled
	case err != nil:
		snapshot.Status = StatusFailed
		snapshot.Error = err.Error()
	default:
		snapshot.Entries = slices.Clone(entries)
		snapshot.Status = StatusReady
	}
	delete(m.cancels, id)
}

func buildRootsFrom(rootPaths []string, startSeq uint64) ([]Root, uint64, error) {
	// Return startSeq on all errors: no IDs were consumed, so callers may retry without gaps.
	if len(rootPaths) == 0 {
		return nil, startSeq, errors.New("at least one root path is required")
	}

	seq := startSeq
	roots := make([]Root, 0, len(rootPaths))
	for _, rootPath := range rootPaths {
		cleaned, err := filepath.Abs(rootPath)
		if err != nil {
			return nil, startSeq, err
		}
		info, err := os.Stat(cleaned)
		if err != nil {
			return nil, startSeq, err
		}
		if !info.IsDir() {
			return nil, startSeq, fmt.Errorf("workspace root is not a directory: %s", cleaned)
		}
		roots = append(roots, Root{
			ID:   fmt.Sprintf("root_%d", seq),
			Name: filepath.Base(cleaned),
			Path: cleaned,
		})
		seq++
	}
	return roots, seq, nil
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
		ID:          snapshot.ID,
		Status:      snapshot.Status,
		Roots:       slices.Clone(snapshot.Roots),
		Entries:     slices.Clone(snapshot.Entries),
		Error:       snapshot.Error,
		nextRootSeq: snapshot.nextRootSeq,
	}
}
