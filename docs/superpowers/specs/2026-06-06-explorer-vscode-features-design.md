# Explorer 借用 VSCode 功能 — 設計 spec

**日期**：2026-06-06
**範圍**：macOS app（`apps/macos`）Explorer 側邊欄
**狀態**：設計確認中

## 目標

為側邊欄 Explorer 借用四項 VSCode 導覽／檢視功能，全部維持 ArchSight 的唯讀觀察定位（不新增任何寫入／編輯能力）：

1. **可收合的根資料夾** — 修正目前多個拖入資料夾無法用三角形／「-」收合的問題。
2. **一鍵收合全部** — 對齊 VSCode *Collapse Folders in Explorer*，含工具列按鈕與快捷鍵。
3. **在 Finder 中顯示** — 右鍵 Reveal in Finder。
4. **複製路徑** — 右鍵 Copy Path（絕對）／Copy Relative Path（相對於所屬 root）。

## 現況

- 側邊欄每個拖入的 root 以 `Section(root.name)` 渲染（`ContentView.swift:234`）。SwiftUI 的 `Section`（字串 header）在 macOS sidebar List 中**不可收合**，這是「按不了『-』」的根因。
- 子資料夾展開狀態存於 `@State expandedPaths: Set<String>`（`ContentView.swift:8`），由 `sidebarNode` 的 `DisclosureGroup` 讀寫。
- 既有命令／快捷鍵集中於 `WorkspaceCommandActions` + `WorkspaceMenuCommands`，顯示用提示集中於 `ShortcutCatalog`（以單元測試維持一致）。
- 部署 target 為 `.macOS(.v14)`（`Package.swift`），故可用 `Section(_:isExpanded:)`。
- `ContentView.swift` 已 999 行，超過團隊風格指南的 800 行上限；本次新增邏輯應外移以避免持續惡化。

## 設計

### 1. 可收合的根資料夾

- 新增 `@State private var collapsedRoots: Set<WorkspaceRoot.ID> = []`。
- 採「記錄被收合者」語意：集合為空＝全部展開，新拖入的 root 預設展開、免初始化。
- root 渲染改為 `Section(root.name, isExpanded: binding)`，其中
  - `get`：`!collapsedRoots.contains(root.id)`
  - `set(expanded)`：`expanded ? collapsedRoots.remove(id) : collapsedRoots.insert(id)`
- `removeRoot(_:)` 與 `closeWorkspace()` 一併清除對應 id（比照既有 `expandedPaths` 清理）。

### 2. 一鍵收合全部

- 語意（已與使用者確認）：**子資料夾與 root sections 一起收合**。
  ```swift
  func collapseAll() {
      expandedPaths = []
      collapsedRoots = Set(state.roots.map(\.id))
  }
  ```
- **按鈕**：在 Explorer 分頁頂端新增一條輕量「FOLDERS」標題列（樣式比照既有 OPEN FILES 子標題），右側放收合按鈕，使用 SF Symbol `rectangle.compress.vertical`。僅在 `!state.roots.isEmpty` 時顯示。按鈕 `.help` 顯示動作名＋快捷鍵（沿用 `ShortcutCatalog.hint(...)?.chord.display` 模式）。
- **快捷鍵**：`⌥⌘0`（⌘1–9 已被分頁佔用、⌘0 未使用、加 ⌥ 避開「實際大小」聯想，目前無衝突）。
  - `WorkspaceCommandActions` 新增 `var collapseAll: () -> Void = {}`。
  - `WorkspaceMenuCommands` 在 `.sidebar` 群組新增 `Button("Collapse Folders") { actions?.collapseAll() }.keyboardShortcut("0", modifiers: [.command, .option])`。
  - `ContentView` 建立 `WorkspaceCommandActions` 時接上 `collapseAll: { collapseAll() }`。
  - `ShortcutCatalog.all` 新增 `ShortcutHint(id: "collapseFolders", category: .view, label: "Collapse Folders", chord: KeyChord(key: "0", command: true, option: true))`。

### 3 & 4. 右鍵選單：Reveal in Finder／Copy Path

於三處掛上 `.contextMenu`：`sidebarNode` 的檔案分支、資料夾分支，以及 root `Section`（追加到既有的 Remove/Close All 選單）。選單項：

- **Reveal in Finder** → `NSWorkspace.shared.activateFileViewerSelecting([fileURL])`
- **Copy Path** → 絕對路徑寫入 `NSPasteboard.general`
- **Copy Relative Path** → 相對於所屬 root 路徑

`sidebarNode` 簽名改為 `sidebarNode(_ node: WorkspaceTreeNode, rootPath: String)`，遞迴時帶入；呼叫端（`ForEach(nodes)`）以 `root.path` 起始。

### 程式組織

新增 `apps/macos/Sources/ArchSightApp/FileSystemActions.swift`，集中：

- `enum FileSystemActions`（或具名函式）：
  - `revealInFinder(path: String)`
  - `copyToPasteboard(_ string: String)`
  - `relativePath(of path: String, under rootPath: String) -> String` — 純函式，可單元測試。
- ContentView 僅做最小接線；不進行無關重構。

### 錯誤處理

- Reveal/Copy 為盡力而為的 UI 動作：路徑無效時靜默不動作（不丟錯、不彈窗），符合唯讀工具的低干擾風格。
- `relativePath` 在 `rootPath` 非前綴時，回退為原始 `path`（不應發生，但防禦性處理）。

## 測試

- **單元測試**（`ArchSightKitTests` 或對應 App 測試目標）：
  - `relativePath(of:under:)`：root 自身、巢狀檔案、尾斜線、非前綴回退。
  - `ShortcutCatalog`：新增 `collapseFolders` 項目存在且 chord 顯示為 `⌥⌘0`（延伸既有 `ShortcutCatalogTests`）。
- **狀態邏輯**：`collapseAll()` 清空 `expandedPaths` 並收合所有 root（如可在 `AppStateTests`/view-state 層覆蓋則加測；純 UI binding 不強求）。
- Reveal in Finder 走 `NSWorkspace`，不做單元測試。
- **驗證指令**：`swift build`、`swift test`（於 `apps/macos`）。

## 不做（YAGNI）

- 不新增 Expand All（VSCode 亦無預設，需求低）。
- 不新增 New File／New Folder／Refresh 等寫入或背景掃描動作（違反唯讀定位）。
- root section 的收合狀態不持久化到磁碟（符合「不寫入 workspace 中繼資料」原則）。
