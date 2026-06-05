# Plan A — 多視窗共用 core + 多資料夾增量共存 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓所有視窗共用單一 core 行程、可開多視窗，並讓加入/移除資料夾走增量掃描而非整包重開，既有分頁與選取不受影響。

**Architecture:** core（Go）的 `workspace.Manager` 改用單調穩定的 root id，並新增 `AddRoots` / `RemoveRoot` 只掃/刪差異；新增 `addRoots` / `removeRoot` 兩個 IPC RPC。Swift 端在 `ArchSightKit` 補對應 client/controller，在 App target 新增 `AppCore`（App 級唯一 `CoreSession`）注入各視窗，`ContentView` 改讀共用 endpoint 並接上加/移除資料夾。

**Tech Stack:** Go 1.x（`core`）、Swift 6 / SwiftPM、SwiftUI、AppKit、Observation、XCTest、`go test`。

設計來源：`docs/superpowers/specs/2026-06-05-multiwindow-folders-keybindings-design.md`（第 1、2、4 部分）。

工作目錄：Go 任務在 `core` 執行 `go test`；Swift 任務在 `apps/macos` 執行 `swift build` / `swift test`。

---

## 檔案結構

**新增**
- `apps/macos/Sources/ArchSightApp/AppCore.swift` — App 級 `@Observable`，持有唯一 `CoreSession`，暴露 `endpoint` 與 `status`。

**修改（core）**
- `core/internal/workspace/manager.go` — 穩定 root id（`buildRootsFrom` + `Snapshot.nextRootSeq`）、`AddRoots`、`RemoveRoot`、`scanAppend`、`finishAppend`、`cloneSnapshot`。
- `core/internal/workspace/manager_test.go` — 穩定 id、`AddRoots`、`RemoveRoot` 測試。
- `core/internal/ipc/server.go` — `addRoots` / `removeRoot` dispatch 與 handler。
- `core/internal/ipc/workspace_test.go` — RPC round-trip 測試。

**修改（Kit）**
- `apps/macos/Sources/ArchSightKit/IPC.swift` — `IPCMethod` 新增 `addRoots`/`removeRoot`、`AddRootsParams`/`RemoveRootParams`。
- `apps/macos/Sources/ArchSightKit/CoreClient.swift` — `CoreServicing` 協定 + `CoreClient` 實作新增兩方法。
- `apps/macos/Sources/ArchSightKit/WorkspaceController.swift` — `addRoots`/`removeRoot`，抽出共用 `awaitReady`。
- `apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift` — `removeRoot(id:)`、`closeWorkspace()`。
- `apps/macos/Tests/ArchSightKitTests/WorkspaceControllerTests.swift` — `FakeCoreClient` 補兩方法 + 新測試。
- `apps/macos/Tests/ArchSightKitTests/NavigationTests.swift` — `StubServicing` 補兩方法（編譯所需）。
- `apps/macos/Tests/ArchSightKitTests/AppStateTests.swift` — `removeRoot`/`closeWorkspace` 測試。

**修改（App）**
- `apps/macos/Sources/ArchSightApp/ArchSightApp.swift` — 建 `AppCore`、注入、移除空的 `.newItem` 替換以恢復 New Window。
- `apps/macos/Sources/ArchSightApp/ContentView.swift` — 讀 `AppCore`、加/移除資料夾接線、側邊欄 root 右鍵選單。

---

# Phase 1 — core 穩定 root id 與增量 add/remove（Go, TDD）

## Task 1: 穩定且單調的 root id

**Files:**
- Modify: `core/internal/workspace/manager.go`
- Test: `core/internal/workspace/manager_test.go`

- [x] **Step 1: Write the failing test**

在 `core/internal/workspace/manager_test.go` 末端新增：
```go
func TestOpenAssignsSequentialRootIDsFromOne(t *testing.T) {
	dirA := t.TempDir()
	dirB := t.TempDir()
	manager := NewManager()

	snapshot, err := manager.Open(context.Background(), []string{dirA, dirB})
	if err != nil {
		t.Fatalf("Open returned error: %v", err)
	}
	if len(snapshot.Roots) != 2 {
		t.Fatalf("expected 2 roots, got %d", len(snapshot.Roots))
	}
	if snapshot.Roots[0].ID != "root_1" || snapshot.Roots[1].ID != "root_2" {
		t.Fatalf("unexpected root ids: %s, %s", snapshot.Roots[0].ID, snapshot.Roots[1].ID)
	}
}
```

- [x] **Step 2: Run test to verify it fails or passes**

Run（在 `core`）：`go test ./internal/workspace/ -run TestOpenAssignsSequentialRootIDsFromOne -v`
Expected: PASS（現有 `buildRoots` 已產生 `root_1`/`root_2`）。此測試先鎖住既有行為，後續重構不可破壞它。

- [x] **Step 3: 重構為單調計數器**

在 `core/internal/workspace/manager.go`：

(a) `Snapshot` struct 加未匯出欄位（不會序列化）：
```go
type Snapshot struct {
	ID          string  `json:"id"`
	Status      Status  `json:"status"`
	Roots       []Root  `json:"roots"`
	Entries     []Entry `json:"entries"`
	Error       string  `json:"error,omitempty"`
	nextRootSeq uint64
}
```

(b) 把 `buildRoots` 改為 `buildRootsFrom`（接續編號、回傳下一個序號）：
```go
func buildRootsFrom(rootPaths []string, startSeq uint64) ([]Root, uint64, error) {
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
```

(c) `Open` 改用它並記錄 `nextRootSeq`：
```go
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
	m.mu.Unlock()

	go m.scan(ctx, id, roots)

	return cloneSnapshot(snapshot), nil
}
```

(d) `cloneSnapshot` 帶上計數器：
```go
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
```

- [x] **Step 4: Run test to verify it passes**

Run（在 `core`）：`go test ./internal/workspace/ -run TestOpenAssignsSequentialRootIDsFromOne -v`
Expected: PASS。

- [x] **Step 5: 全 workspace 套件確認無回歸**

Run（在 `core`）：`go test ./internal/workspace/`
Expected: PASS。

- [x] **Step 6: Commit**

```bash
git add core/internal/workspace/manager.go core/internal/workspace/manager_test.go
git commit -m "refactor: [core] assign monotonic stable workspace root ids"
```

---

## Task 2: Manager.AddRoots 增量掃描

**Files:**
- Modify: `core/internal/workspace/manager.go`
- Test: `core/internal/workspace/manager_test.go`

- [x] **Step 1: Write the failing test**

在 `manager_test.go` 末端新增（沿用既有 `waitForSnapshot` helper）：
```go
func TestAddRootsAppendsOnlyNewRootsWithContinuingIDs(t *testing.T) {
	dirA := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirA, "a.txt"), []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirB := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirB, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	manager := NewManager()

	opened, err := manager.Open(context.Background(), []string{dirA})
	if err != nil {
		t.Fatalf("Open error: %v", err)
	}
	waitForSnapshot(t, manager, opened.ID)

	added, err := manager.AddRoots(context.Background(), opened.ID, []string{dirB})
	if err != nil {
		t.Fatalf("AddRoots error: %v", err)
	}
	if len(added.Roots) != 2 {
		t.Fatalf("expected 2 roots, got %d", len(added.Roots))
	}
	if added.Roots[1].ID != "root_2" {
		t.Fatalf("expected continuing id root_2, got %s", added.Roots[1].ID)
	}
	waitForSnapshot(t, manager, opened.ID)

	got, _ := manager.Get(opened.ID)
	var roots []string
	for _, e := range got.Entries {
		if e.Kind == KindFile {
			roots = append(roots, e.RootID+"/"+e.Path)
		}
	}
	if len(roots) != 2 {
		t.Fatalf("expected entries from both roots, got %v", roots)
	}
}

func TestAddRootsUnknownWorkspaceErrors(t *testing.T) {
	manager := NewManager()
	if _, err := manager.AddRoots(context.Background(), "ws_missing", []string{t.TempDir()}); err == nil {
		t.Fatal("expected error for unknown workspace")
	}
}
```

- [x] **Step 2: Run test to verify it fails**

Run（在 `core`）：`go test ./internal/workspace/ -run TestAddRoots -v`
Expected: FAIL（`manager.AddRoots undefined`）。

- [x] **Step 3: Write minimal implementation**

在 `core/internal/workspace/manager.go` 新增（放在 `Open` 之後）：
```go
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
	snapshot.Roots = append(snapshot.Roots, newRoots...)
	snapshot.nextRootSeq = nextSeq
	snapshot.Status = StatusScanning
	snapshot.Error = ""
	ctx, cancel := context.WithCancel(parent)
	m.cancels[id] = cancel
	clone := cloneSnapshot(snapshot)
	m.mu.Unlock()

	go m.scanAppend(ctx, id, newRoots)
	return clone, nil
}

func (m *Manager) scanAppend(ctx context.Context, id string, roots []Root) {
	var entries []Entry
	for _, root := range roots {
		if err := m.scanRoot(ctx, root, &entries); err != nil {
			m.finishAppend(id, err, entries)
			return
		}
	}
	m.finishAppend(id, nil, entries)
}

func (m *Manager) finishAppend(id string, err error, newEntries []Entry) {
	m.mu.Lock()
	defer m.mu.Unlock()

	snapshot, ok := m.snapshots[id]
	if !ok {
		return
	}
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
```

- [x] **Step 4: Run test to verify it passes**

Run（在 `core`）：`go test ./internal/workspace/ -run TestAddRoots -v`
Expected: PASS。

- [x] **Step 5: Commit**

```bash
git add core/internal/workspace/manager.go core/internal/workspace/manager_test.go
git commit -m "feat: [core] add incremental AddRoots scanning to workspace manager"
```

---

## Task 3: Manager.RemoveRoot

**Files:**
- Modify: `core/internal/workspace/manager.go`
- Test: `core/internal/workspace/manager_test.go`

- [x] **Step 1: Write the failing test**

在 `manager_test.go` 末端新增：
```go
func TestRemoveRootDropsRootAndItsEntriesKeepingOthers(t *testing.T) {
	dirA := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirA, "a.txt"), []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirB := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirB, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	manager := NewManager()
	opened, err := manager.Open(context.Background(), []string{dirA, dirB})
	if err != nil {
		t.Fatalf("Open error: %v", err)
	}
	waitForSnapshot(t, manager, opened.ID)

	removed, err := manager.RemoveRoot(opened.ID, "root_1")
	if err != nil {
		t.Fatalf("RemoveRoot error: %v", err)
	}
	if len(removed.Roots) != 1 || removed.Roots[0].ID != "root_2" {
		t.Fatalf("expected only root_2 to remain, got %+v", removed.Roots)
	}
	for _, e := range removed.Entries {
		if e.RootID == "root_1" {
			t.Fatalf("entries for removed root should be gone, found %s", e.Path)
		}
	}
}

func TestRemoveRootUnknownErrors(t *testing.T) {
	dirA := t.TempDir()
	manager := NewManager()
	opened, _ := manager.Open(context.Background(), []string{dirA})
	waitForSnapshot(t, manager, opened.ID)
	if _, err := manager.RemoveRoot(opened.ID, "root_99"); err == nil {
		t.Fatal("expected error for unknown root")
	}
}
```

- [x] **Step 2: Run test to verify it fails**

Run（在 `core`）：`go test ./internal/workspace/ -run TestRemoveRoot -v`
Expected: FAIL（`manager.RemoveRoot undefined`）。

- [x] **Step 3: Write minimal implementation**

在 `core/internal/workspace/manager.go` 新增：
```go
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
```

- [x] **Step 4: Run test to verify it passes**

Run（在 `core`）：`go test ./internal/workspace/ -run TestRemoveRoot -v`
Expected: PASS。

- [x] **Step 5: 全套件確認無回歸**

Run（在 `core`）：`go test ./internal/workspace/`
Expected: PASS。

- [x] **Step 6: Commit**

```bash
git add core/internal/workspace/manager.go core/internal/workspace/manager_test.go
git commit -m "feat: [core] add RemoveRoot to drop a root and its entries"
```

---

# Phase 2 — core IPC RPC（Go, TDD）

## Task 4: addRoots / removeRoot RPC handler

**Files:**
- Modify: `core/internal/ipc/server.go`
- Test: `core/internal/ipc/workspace_test.go`

- [x] **Step 1: Write the failing test**

先看既有 `core/internal/ipc/workspace_test.go` 的 helper（如何建 server、發 request、解 response），沿用同款 helper 新增：
```go
func TestAddRootsRPCAppendsRoot(t *testing.T) {
	dirA := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirA, "a.txt"), []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirB := t.TempDir()
	if err := os.WriteFile(filepath.Join(dirB, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	server := NewServer(Config{Version: "test"})

	openResp := server.dispatch(mustRequest(t, "1", "openWorkspace", map[string]any{"roots": []string{dirA}}))
	wsID := decodeWorkspaceID(t, openResp)
	waitForReadyRPC(t, server, wsID)

	addResp := server.dispatch(mustRequest(t, "2", "addRoots", map[string]any{"workspaceId": wsID, "roots": []string{dirB}}))
	if !addResp.OK {
		t.Fatalf("addRoots failed: %+v", addResp.Error)
	}
	waitForReadyRPC(t, server, wsID)

	treeResp := server.dispatch(mustRequest(t, "3", "listTree", map[string]any{"workspaceId": wsID}))
	tree := decodeListTree(t, treeResp)
	if len(tree.Roots) != 2 {
		t.Fatalf("expected 2 roots after addRoots, got %d", len(tree.Roots))
	}
}

func TestRemoveRootRPCDropsRoot(t *testing.T) {
	dirA := t.TempDir()
	dirB := t.TempDir()
	server := NewServer(Config{Version: "test"})

	openResp := server.dispatch(mustRequest(t, "1", "openWorkspace", map[string]any{"roots": []string{dirA, dirB}}))
	wsID := decodeWorkspaceID(t, openResp)
	waitForReadyRPC(t, server, wsID)

	rmResp := server.dispatch(mustRequest(t, "2", "removeRoot", map[string]any{"workspaceId": wsID, "rootId": "root_1"}))
	if !rmResp.OK {
		t.Fatalf("removeRoot failed: %+v", rmResp.Error)
	}
	tree := decodeListTree(t, rmResp)
	if len(tree.Roots) != 1 || tree.Roots[0].ID != "root_2" {
		t.Fatalf("expected only root_2 after removeRoot, got %+v", tree.Roots)
	}
}
```
> 註：`mustRequest`、`decodeWorkspaceID`、`decodeListTree`、`waitForReadyRPC` 若 `workspace_test.go` 尚無，請依該檔既有測試的解碼方式新增小 helper（`mustRequest` 把 params marshal 成 `json.RawMessage` 後組 `Request`；`decodeListTree` 把 `resp.Result` 重新 marshal+unmarshal 成 `listTreeResult`；`waitForReadyRPC` 反覆 dispatch `listTree` 直到 `status == "ready"`，上限約 200 次）。

- [x] **Step 2: Run test to verify it fails**

Run（在 `core`）：`go test ./internal/ipc/ -run 'TestAddRootsRPC|TestRemoveRootRPC' -v`
Expected: FAIL（`Unsupported method: addRoots`）。

- [x] **Step 3: Write minimal implementation**

在 `core/internal/ipc/server.go`：

(a) `dispatch` 的 switch 內，於 `case "openWorkspace":` 之後新增：
```go
	case "addRoots":
		return s.addRoots(req)
	case "removeRoot":
		return s.removeRoot(req)
```

(b) 新增 params 型別（放在 `openWorkspaceResult` 附近）：
```go
type addRootsParams struct {
	WorkspaceID string   `json:"workspaceId"`
	Roots       []string `json:"roots"`
}

type removeRootParams struct {
	WorkspaceID string `json:"workspaceId"`
	RootID      string `json:"rootId"`
}
```

(c) 新增 handler（放在 `openWorkspace` 之後）：
```go
func (s *Server) addRoots(req Request) Response {
	var params addRootsParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	if params.WorkspaceID == "" {
		return ErrorResponse(req.ID, NewError("invalid_params", "workspaceId is required"))
	}
	snapshot, err := s.workspaces.AddRoots(context.Background(), params.WorkspaceID, params.Roots)
	if err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	return SuccessResponse(req.ID, openWorkspaceResult{
		WorkspaceID: snapshot.ID,
		Status:      snapshot.Status,
		Roots:       snapshot.Roots,
	})
}

func (s *Server) removeRoot(req Request) Response {
	var params removeRootParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return ErrorResponse(req.ID, NewError("invalid_params", err.Error()))
	}
	if params.WorkspaceID == "" || params.RootID == "" {
		return ErrorResponse(req.ID, NewError("invalid_params", "workspaceId and rootId are required"))
	}
	snapshot, err := s.workspaces.RemoveRoot(params.WorkspaceID, params.RootID)
	if err != nil {
		return ErrorResponse(req.ID, NewError("not_found", err.Error()))
	}
	roots := snapshot.Roots
	if roots == nil {
		roots = []workspace.Root{}
	}
	entries := snapshot.Entries
	if entries == nil {
		entries = []workspace.Entry{}
	}
	return SuccessResponse(req.ID, listTreeResult{
		WorkspaceID: snapshot.ID,
		Status:      snapshot.Status,
		Roots:       roots,
		Entries:     entries,
		Error:       snapshot.Error,
	})
}
```

- [x] **Step 4: Run test to verify it passes**

Run（在 `core`）：`go test ./internal/ipc/ -run 'TestAddRootsRPC|TestRemoveRootRPC' -v`
Expected: PASS。

- [x] **Step 5: 全 core 測試確認無回歸**

Run（在 `core`）：`go test ./...`
Expected: PASS。

- [x] **Step 6: Commit**

```bash
git add core/internal/ipc/server.go core/internal/ipc/workspace_test.go
git commit -m "feat: [core] add addRoots and removeRoot IPC handlers"
```

---

# Phase 3 — Swift Kit：協定、client、controller、state（TDD）

## Task 5: IPC 方法與參數型別

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/IPC.swift`

- [x] **Step 1: 新增 IPCMethod case 與 params**

在 `apps/macos/Sources/ArchSightKit/IPC.swift`：

(a) `IPCMethod` enum 補兩個 case：
```swift
public enum IPCMethod: String, Codable, Sendable {
    case health
    case openWorkspace
    case addRoots
    case removeRoot
    case listTree
    case openFile
    case search
    case definition
    case references
    case cancel
}
```

(b) 在 `OpenWorkspaceParams` 之後新增：
```swift
public struct AddRootsParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let roots: [String]

    public init(workspaceId: String, roots: [String]) {
        self.workspaceId = workspaceId
        self.roots = roots
    }
}

public struct RemoveRootParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let rootId: String

    public init(workspaceId: String, rootId: String) {
        self.workspaceId = workspaceId
        self.rootId = rootId
    }
}
```

- [x] **Step 2: Build 驗證**

Run（在 `apps/macos`）：`swift build`
Expected: 編譯成功（型別新增、尚無使用）。

- [x] **Step 3: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/IPC.swift
git commit -m "feat: [macos] add addRoots/removeRoot IPC method and params"
```

---

## Task 6: CoreServicing / CoreClient 新增方法 + 更新 fakes

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/CoreClient.swift`
- Modify: `apps/macos/Tests/ArchSightKitTests/WorkspaceControllerTests.swift`（`FakeCoreClient`）
- Modify: `apps/macos/Tests/ArchSightKitTests/NavigationTests.swift`（`StubServicing`）

- [x] **Step 1: 擴充協定與實作**

在 `apps/macos/Sources/ArchSightKit/CoreClient.swift`：

(a) `CoreServicing` 協定新增兩方法（放在 `openWorkspace` 後）：
```swift
public protocol CoreServicing: AnyObject {
    func openWorkspace(roots: [String]) throws -> OpenWorkspaceResult
    func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult
    func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult
    func listTree(workspaceId: String) throws -> ListTreeResult
    func openFile(workspaceId: String, rootId: String, path: String) throws -> OpenFileResult
    func search(workspaceId: String, pattern: String) throws -> SearchResult
    func definition(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult
    func references(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult
}
```

(b) `CoreClient` 實作（放在 `openWorkspace` 方法後）：
```swift
    public func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult {
        try send(
            .addRoots,
            params: AddRootsParams(workspaceId: workspaceId, roots: roots),
            resultType: OpenWorkspaceResult.self
        )
    }

    public func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult {
        try send(
            .removeRoot,
            params: RemoveRootParams(workspaceId: workspaceId, rootId: rootId),
            resultType: ListTreeResult.self
        )
    }
```

- [x] **Step 2: 更新 `FakeCoreClient`（WorkspaceControllerTests）**

在 `apps/macos/Tests/ArchSightKitTests/WorkspaceControllerTests.swift` 的 `FakeCoreClient` 內，新增可記錄呼叫的屬性與方法：
```swift
    var addRootsResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
    var removeRootResult = ListTreeResult(workspaceId: "ws_1", status: "ready", roots: [], entries: [], error: nil)
    private(set) var addRootsCalls: [(workspaceId: String, roots: [String])] = []
    private(set) var removeRootCalls: [(workspaceId: String, rootId: String)] = []

    func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult {
        addRootsCalls.append((workspaceId, roots))
        return addRootsResult
    }

    func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult {
        removeRootCalls.append((workspaceId, rootId))
        return removeRootResult
    }
```

- [x] **Step 3: 更新 `StubServicing`（NavigationTests）**

在 `apps/macos/Tests/ArchSightKitTests/NavigationTests.swift` 的 `StubServicing` 內新增（僅供編譯，回傳最小值）：
```swift
    func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult {
        OpenWorkspaceResult(workspaceId: workspaceId, status: "ready", roots: [])
    }

    func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult {
        ListTreeResult(workspaceId: workspaceId, status: "ready", roots: [], entries: [], error: nil)
    }
```
> 若 `NavigationTests` 的 stub 名稱/內容不同，依該檔實際 stub 補齊這兩個方法即可。執行 Step 4 的 build 會明確指出所有未實作協定的型別。

- [x] **Step 4: Build 測試 target 驗證**

Run（在 `apps/macos`）：`swift build --build-tests`
Expected: 編譯成功（所有 `CoreServicing` 實作都補齊）。若有其它檔案實作 `CoreServicing` 未補方法，編譯錯誤會列出，逐一補上同樣兩方法。

- [x] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/CoreClient.swift apps/macos/Tests/ArchSightKitTests/WorkspaceControllerTests.swift apps/macos/Tests/ArchSightKitTests/NavigationTests.swift
git commit -m "feat: [macos] add addRoots/removeRoot to CoreServicing and fakes"
```

---

## Task 7: WorkspaceController.addRoots / removeRoot

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/WorkspaceController.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/WorkspaceControllerTests.swift`

- [x] **Step 1: Write the failing test**

在 `WorkspaceControllerTests` 內新增：
```swift
    func testAddRootsPollsUntilReady() throws {
        let client = FakeCoreClient()
        client.addRootsResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
        client.listTreeResults = [
            makeTree(status: "scanning", entries: []),
            makeTree(status: "ready", entries: [makeEntry(path: "b.txt", kind: "file")]),
        ]
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        let result = try controller.addRoots(workspaceId: "ws_1", paths: ["/tmp/b"])

        XCTAssertEqual(result.status, "ready")
        XCTAssertEqual(result.entries.first?.path, "b.txt")
        XCTAssertEqual(client.addRootsCalls.first?.roots, ["/tmp/b"])
        XCTAssertEqual(client.listTreeCalls.count, 2)
    }

    func testRemoveRootReturnsUpdatedTree() throws {
        let client = FakeCoreClient()
        client.removeRootResult = ListTreeResult(
            workspaceId: "ws_1",
            status: "ready",
            roots: [WorkspaceRoot(id: "root_2", name: "b", path: "/tmp/b")],
            entries: [],
            error: nil
        )
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        let result = try controller.removeRoot(workspaceId: "ws_1", rootId: "root_1")

        XCTAssertEqual(result.roots.map(\.id), ["root_2"])
        XCTAssertEqual(client.removeRootCalls.first?.rootId, "root_1")
    }
```

- [x] **Step 2: Run test to verify it fails**

Run（在 `apps/macos`）：`swift test --filter WorkspaceControllerTests`
Expected: FAIL（`addRoots`/`removeRoot` 不存在於 controller）。

- [x] **Step 3: Write minimal implementation**

在 `apps/macos/Sources/ArchSightKit/WorkspaceController.swift`：

(a) 把 `openWorkspace` 內的輪詢抽成共用方法，並讓 `openWorkspace` 改用它：
```swift
    @discardableResult
    public func openWorkspace(paths: [String]) throws -> ListTreeResult {
        let opened = try client.openWorkspace(roots: paths)
        return try awaitReady(workspaceId: opened.workspaceId)
    }

    /// Appends roots to an existing workspace, then polls until the incremental
    /// scan settles.
    @discardableResult
    public func addRoots(workspaceId: String, paths: [String]) throws -> ListTreeResult {
        _ = try client.addRoots(workspaceId: workspaceId, roots: paths)
        return try awaitReady(workspaceId: workspaceId)
    }

    /// Removes a single root; the core returns the already-settled tree.
    @discardableResult
    public func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult {
        try client.removeRoot(workspaceId: workspaceId, rootId: rootId)
    }

    private func awaitReady(workspaceId: String) throws -> ListTreeResult {
        for _ in 0..<pollLimit {
            let tree = try client.listTree(workspaceId: workspaceId)
            switch tree.status {
            case "scanning":
                sleep()
            case "failed":
                throw CoreClientError(code: "workspace_failed", message: tree.error ?? "Workspace scan failed")
            default:
                return tree
            }
        }
        throw CoreClientError(code: "workspace_timeout", message: "Workspace scan did not finish in time")
    }
```
> 移除舊 `openWorkspace` 內重複的 for-loop 主體（已搬進 `awaitReady`）。

- [x] **Step 4: Run test to verify it passes**

Run（在 `apps/macos`）：`swift test --filter WorkspaceControllerTests`
Expected: PASS（含既有四個 openWorkspace 測試維持綠燈）。

- [x] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/WorkspaceController.swift apps/macos/Tests/ArchSightKitTests/WorkspaceControllerTests.swift
git commit -m "feat: [macos] add WorkspaceController addRoots/removeRoot with shared poll"
```

---

## Task 8: WorkspaceViewState.removeRoot / closeWorkspace

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/AppStateTests.swift`

- [x] **Step 1: Write the failing test**

在 `apps/macos/Tests/ArchSightKitTests/AppStateTests.swift` 新增（若該檔已有 `WorkspaceViewState` 測試，沿用同檔；否則新增測試類別）：
```swift
    func testRemoveRootDropsRootEntriesAndItsTabs() {
        var state = WorkspaceViewState(
            workspaceId: "ws_1",
            roots: [
                WorkspaceRoot(id: "root_1", name: "a", path: "/tmp/a"),
                WorkspaceRoot(id: "root_2", name: "b", path: "/tmp/b"),
            ],
            entries: [
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/a", path: "a.txt", name: "a.txt", kind: "file"),
                WorkspaceEntry(rootId: "root_2", rootPath: "/tmp/b", path: "b.txt", name: "b.txt", kind: "file"),
            ]
        )
        state.openFile(rootID: "root_1", path: "a.txt", content: "a")
        state.openFile(rootID: "root_2", path: "b.txt", content: "b")
        // selectedTabID is now root_2:b.txt

        state.removeRoot(id: "root_1")

        XCTAssertEqual(state.roots.map(\.id), ["root_2"])
        XCTAssertTrue(state.entries.allSatisfy { $0.rootId == "root_2" })
        XCTAssertEqual(state.openTabs.map(\.rootID), ["root_2"])
        XCTAssertEqual(state.selectedTabID, "root_2:b.txt")
    }

    func testRemoveRootClearsSelectionWhenSelectedTabRemoved() {
        var state = WorkspaceViewState(
            workspaceId: "ws_1",
            roots: [WorkspaceRoot(id: "root_1", name: "a", path: "/tmp/a")],
            entries: []
        )
        state.openFile(rootID: "root_1", path: "a.txt", content: "a")
        state.removeRoot(id: "root_1")
        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertNil(state.selectedTabID)
    }

    func testCloseWorkspaceClearsEverythingButKeepsWorkspaceId() {
        var state = WorkspaceViewState(
            workspaceId: "ws_1",
            roots: [WorkspaceRoot(id: "root_1", name: "a", path: "/tmp/a")],
            entries: [WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/a", path: "a.txt", name: "a.txt", kind: "file")]
        )
        state.openFile(rootID: "root_1", path: "a.txt", content: "a")
        state.searchResults = []

        state.closeWorkspace()

        XCTAssertEqual(state.workspaceId, "ws_1")
        XCTAssertTrue(state.roots.isEmpty)
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertNil(state.selectedTabID)
    }
```
> 若 `AppStateTests` 尚未 `import` / `@testable import ArchSightKit`，比照同檔其他測試補上。

- [x] **Step 2: Run test to verify it fails**

Run（在 `apps/macos`）：`swift test --filter AppStateTests`
Expected: FAIL（`removeRoot`/`closeWorkspace` 不存在）。

- [x] **Step 3: Write minimal implementation**

在 `apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift` 的 `WorkspaceViewState` 內新增（放在 `closeTab` 之後）：
```swift
    /// Removes a single root: drops its roots/entries, closes every tab that
    /// belongs to it (fixing selection), and clears references pointing at it.
    public mutating func removeRoot(id: String) {
        roots.removeAll { $0.id == id }
        entries.removeAll { $0.rootId == id }
        for tab in openTabs where tab.rootID == id {
            closeTab(id: tab.id)
        }
        references.removeAll { $0.rootId == id }
        if references.isEmpty {
            referencesContext = nil
        }
    }

    /// Empties the workspace back to a blank state while keeping the same
    /// workspaceId so new roots can still be added to it.
    public mutating func closeWorkspace() {
        roots = []
        entries = []
        openTabs = []
        selectedTabID = nil
        searchResults = []
        references = []
        referencesContext = nil
    }
```

- [x] **Step 4: Run test to verify it passes**

Run（在 `apps/macos`）：`swift test --filter AppStateTests`
Expected: PASS。

- [x] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift apps/macos/Tests/ArchSightKitTests/AppStateTests.swift
git commit -m "feat: [macos] add WorkspaceViewState removeRoot/closeWorkspace"
```

---

# Phase 4 — App target：共用 core 與多視窗、加/移除資料夾 UI（build + 手動驗證）

## Task 9: AppCore 與 App 級注入、恢復 New Window

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/AppCore.swift`
- Modify: `apps/macos/Sources/ArchSightApp/ArchSightApp.swift`

- [x] **Step 1: 建立 AppCore**

`apps/macos/Sources/ArchSightApp/AppCore.swift`:
```swift
import ArchSightKit
import Observation

/// App-level owner of the single shared core session. Every window reads the
/// same endpoint so only one core process runs regardless of window count.
@Observable
final class AppCore {
    private(set) var status: CoreSessionStatus = .disconnected
    private(set) var endpoint: CoreServiceEndpoint?

    @ObservationIgnored private let session: CoreSession?

    init(session: CoreSession? = CoreSessionFactory.fromEnvironment()) {
        self.session = session
    }

    /// Connects once; safe to call from every window's `.task`.
    func connectIfNeeded() {
        guard let session, endpoint == nil else {
            return
        }
        status = .connecting
        do {
            _ = try session.connect()
            status = session.status
            endpoint = session.serviceEndpoint
        } catch {
            status = session.status
        }
    }
}
```

- [x] **Step 2: App 注入 AppCore 並恢復 New Window**

`apps/macos/Sources/ArchSightApp/ArchSightApp.swift`:
```swift
import ArchSightKit
import SwiftUI

@main
struct ArchSightApp: App {
    @State private var readingPreferences = ReadingPreferencesStore()
    @State private var appCore = AppCore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(readingPreferences)
                .environment(appCore)
                .task { appCore.connectIfNeeded() }
        }

        Settings {
            ReadingSettingsView()
                .environment(readingPreferences)
        }
    }
}
```
> 關鍵：移除原本的 `.commands { CommandGroup(replacing: .newItem) {} }`。`WindowGroup` 預設即提供 File ▸ New Window（`Cmd+N`），刪除這個空替換就能開多視窗。Plan B 之後加入的 `.commands` 不會替換 `.newItem`，故 New Window 持續存在。

- [x] **Step 3: Build 驗證**

Run（在 `apps/macos`）：`swift build`
Expected: 編譯失敗，錯誤集中在 `ContentView` 仍引用已不存在的 `coreSession`/`coreEndpoint`/`coreStatus`。下一個 Task 修正。

- [x] **Step 4: Commit（先存 AppCore 與 App）**

> 為維持可編譯的提交邊界，本 Task 與 Task 10 的改動一起編譯通過後再 commit。先不 commit，直接進 Task 10。

---

## Task 10: ContentView 改讀 AppCore + 加/移除資料夾接線 + 右鍵選單

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

- [x] **Step 1: 改用共用 AppCore**

在 `apps/macos/Sources/ArchSightApp/ContentView.swift`：

(a) 刪除這三個 `@State`：
```swift
    @State private var coreStatus: CoreSessionStatus = .disconnected
    @State private var coreSession = CoreSessionFactory.fromEnvironment()
    @State private var coreEndpoint: CoreServiceEndpoint?
```
改為讀環境（放在其他 `@Environment` 附近）：
```swift
    @Environment(AppCore.self) private var appCore
```

(b) 新增一個 computed 取代 `coreEndpoint`：
```swift
    private var coreEndpoint: CoreServiceEndpoint? { appCore.endpoint }
```

(c) `body` 內移除 `.task { connectCoreIfConfigured() }`（連線改由 App 的 `.task` 負責），並刪除 `connectCoreIfConfigured()` 整個方法與 `// MARK: - Core lifecycle` 區塊。

(d) `statusBar` 內的 `switch coreStatus` 改為 `switch appCore.status`。

- [x] **Step 2: 加入/首開資料夾改走增量**

把 `appendRoots(_:)` 改為：首開用 `openWorkspace`，已有 workspace 用 `addRoots`：
```swift
    private func appendRoots(_ urls: [URL]) {
        let added = urls.map(\.path)
        guard coreEndpoint != nil else {
            appendRootsLocally(added)
            return
        }
        let existing = state.roots.map(\.path)
        let fresh = added.filter { !existing.contains($0) }
        guard !fresh.isEmpty else { return }

        if state.workspaceId == nil {
            reopenWorkspace(paths: existing + fresh)
        } else {
            addRoots(paths: fresh)
        }
    }
```

新增 `addRoots`（放在 `reopenWorkspace` 之後）：
```swift
    private func addRoots(paths: [String]) {
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        state.isLoading = true
        state.errorMessage = nil
        Task {
            do {
                let result = try await Task.detached {
                    try endpoint.makeController().addRoots(workspaceId: workspaceId, paths: paths)
                }.value
                state.roots = result.roots
                state.entries = result.entries
                refreshSidebarTreeNodes()
                state.isLoading = false
            } catch {
                state.isLoading = false
                state.errorMessage = Self.describe(error)
            }
        }
    }
```

- [x] **Step 3: 新增移除/關閉資料夾動作**

在 `addRoots` 之後新增：
```swift
    private func removeRoot(_ root: WorkspaceRoot) {
        // Drop the tabs/selection locally first so the UI updates immediately,
        // then tell the core to forget the root and refresh from the result.
        expandedPaths = expandedPaths.filter { !$0.hasPrefix(root.path) }
        state.removeRoot(id: root.id)
        refreshSidebarTreeNodes()
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        Task {
            do {
                let result = try await Task.detached {
                    try endpoint.makeController().removeRoot(workspaceId: workspaceId, rootId: root.id)
                }.value
                state.roots = result.roots
                state.entries = result.entries
                refreshSidebarTreeNodes()
            } catch {
                state.errorMessage = Self.describe(error)
            }
        }
    }

    private func closeWorkspace() {
        expandedPaths = []
        state.closeWorkspace()
        refreshSidebarTreeNodes()
    }
```

- [x] **Step 4: 側邊欄 root Section 加右鍵選單**

在 `sidebarPanel` 的 explorer 分支，`Section(root.name) { ... }` 後加 `.contextMenu`。把：
```swift
                    ForEach(state.roots) { root in
                        Section(root.name) {
                            let nodes = sidebarTreeNodes[root.id, default: []]
                            if nodes.isEmpty {
                                Text("No files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(nodes) { node in
                                    sidebarNode(node)
                                }
                            }
                        }
                    }
```
改為（在 `Section` 上掛 `.contextMenu`）：
```swift
                    ForEach(state.roots) { root in
                        Section(root.name) {
                            let nodes = sidebarTreeNodes[root.id, default: []]
                            if nodes.isEmpty {
                                Text("No files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(nodes) { node in
                                    sidebarNode(node)
                                }
                            }
                        }
                        .contextMenu {
                            Button("Remove Folder from Workspace") { removeRoot(root) }
                            Divider()
                            Button("Close Folder") { closeWorkspace() }
                        }
                    }
```

- [x] **Step 5: Build 驗證**

Run（在 `apps/macos`）：`swift build`
Expected: 編譯成功（Task 9 + Task 10 一起綠燈）。
若仍有 `coreStatus`/`coreSession`/`connectCoreIfConfigured` 殘留引用，依錯誤逐一移除。

- [x] **Step 6: 全測試確認無回歸**

Run（在 `apps/macos`）：`swift test`
Expected: PASS。

- [x] **Step 7: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/AppCore.swift apps/macos/Sources/ArchSightApp/ArchSightApp.swift apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] share one core across windows and add incremental folder add/remove"
```

---

## Task 11: 手動驗證（多視窗 + 多資料夾）

**Files:** 無（驗證）

> **驗證紀錄（2026-06-05）：** 自動化部分全綠 — `go test ./...`、`swift build`、`swift test`（109 tests, 0 失敗）。
> 「單一 core」不變量以行程父子關係直接證實：執行中 App 的子行程恰為 1 個 core（其餘為過去 SIGKILL 殘留、PPID=1 的孤兒，已清理）。
> Step 1–2 的互動式 GUI 點擊步驟（Cmd+N 第二視窗、Cmd+O 兩資料夾、右鍵 Remove/Close Folder、增量無閃爍）依使用者決定**略過**（原生 macOS UI 互動無法可靠自動化）。
> 旁註：App 被 SIGKILL 時 core 不會自我終止 → 孤兒累積，屬健壯性缺口，超出 Plan A 範圍，留作後續（見記憶 `core-orphan-on-sigkill`）。

- [x] **Step 1: 啟動並驗證多視窗共用單一 core**

Run（在 `apps/macos`）：`swift run ArchSight`
逐項確認：
1. `Cmd+N` 開出第二個視窗（File 選單也有 New Window）。
2. 兩個視窗各自 `Cmd+O` 開不同資料夾，互不干擾（各自 roots/tabs）。
3. 另開終端機：`pgrep -fl archsight-core | wc -l` → 應只有 **1** 個 core 行程。

- [x] **Step 2: 驗證多資料夾增量 + 移除/關閉**

1. 開資料夾 A，開一個檔成分頁。
2. 再拖入/`Cmd+O` 資料夾 B：A 的分頁、選取、展開狀態不變，側邊欄新增 B 區段（無整包閃爍）。
3. 右鍵 A 區段 → Remove Folder from Workspace：A 與其分頁消失，B 保留。
4. 右鍵任一區段 → Close Folder：回到 No Workspace 空狀態；再開資料夾仍正常。
5. 開檔後 `Go to Definition` / `Find References` / 搜尋仍正常（workspaceId 與 root id 對應未壞）。

- [x] **Step 3: 收尾**

若全部通過，Plan A 完成。Run（在 `core`）`go test ./...` 與（在 `apps/macos`）`swift test` 最後各跑一次確認綠燈。

---

## Self-review 對照

- 規格第 1 部分（共用 core + 多視窗）→ Task 9、10、11。
- 規格第 2 部分（增量 add/remove + 穩定 id + 移除/關閉 UI）→ Task 1–8、10、11。
- 規格第 4 部分（測試與驗證）→ 各 Task 的 TDD 步驟 + Task 11 手動驗證。
- 型別一致性：`addRoots(workspaceId:roots:)`（client）vs `addRoots(workspaceId:paths:)`（controller）為刻意命名（client 對齊 IPC `roots`、controller 對齊既有 `openWorkspace(paths:)`）；`removeRoot` 兩層皆 `rootId`。
