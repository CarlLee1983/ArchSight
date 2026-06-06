# 最近資料夾（Recent Folders）Design

**狀態：** 設計完成，待實作。
**日期：** 2026-06-06
**前置依賴：** 多視窗／資料夾開啟流程已完成（`ContentView` 的 `openFolderPicker` / `appendRoots` / `reopenWorkspace`、`WorkspaceController.openWorkspace`、`WorkspaceMenuCommands` 的「Open Folder…」皆已存在）。

---

## 目標

讓使用者能快速重開先前開過的資料夾，不必每次都用 Finder 重新挑選。目前 App 透過 `NSOpenPanel`（⌘O）開啟 workspace，但**沒有任何持久化的「最近開啟」記錄**——關閉 App 後重開只能再挑一次。

本次新增「最近資料夾」清單，透過兩個互補管道呈現：

1. **File 選單「Open Recent」子選單** — 原生 macOS 慣例、有快捷鍵肌肉記憶、附「Clear Menu」。
2. **歡迎頁（Welcome）** — 未開啟任何 workspace 時，主畫面顯示最近清單，視覺上明顯、點擊即開，提升可發現性。

### 範圍界定

- **記錄對象：** 只記「資料夾（workspace root）」，不記個別檔案。
- **記錄粒度：** 每個 root 資料夾各記一筆（即使一次開多個資料夾，也拆成多筆獨立記錄）。
- **範圍外（YAGNI，先不做）：** 釘選 / pinning、拖放排序、記錄最近「檔案」、跨裝置同步。

---

## 架構決策

### 沿用既有分層

邏輯與持久化放 **ArchSightKit（可單元測試）**，SwiftUI view 放 **ArchSightApp（不寫 view test，與現狀一致）**。持久化完全對齊既有 `ReadingPreferencesStore` 的 `UserDefaults` 慣例（`@MainActor @Observable`、`init(defaults:)` 可注入測試用 suite）。

### 不需要 security-scoped bookmark

App **未開啟 sandbox**（`Package.swift` SwiftPM 可執行檔，`build-app.sh` 產出的 `Info.plist` 無 `com.apple.security.app-sandbox` entitlement）。因此可直接持久化原始路徑字串並重開，無需 security-scoped bookmark——與現有架構一致。

### 重開沿用既有路徑

選單與歡迎頁的「重開」都路由回既有的 `appendRoots([URL])` → `reopenWorkspace(paths:)`，不另闢開啟流程，確保行為一致（核心連線檢查、錯誤處理、tree 載入皆共用）。

---

## 元件

### 1. `ArchSightKit/RecentFolder.swift`（純值、可測）

```swift
public struct RecentFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String        // 絕對路徑
    public let name: String        // URL(fileURLWithPath: path).lastPathComponent
    public let lastOpened: Date
}
```

immutable 值型別，`id` 即 path（同路徑視為同一筆，用於去重）。

### 2. `ArchSightKit/RecentFoldersStore.swift`（`@MainActor @Observable`）

鏡射 `ReadingPreferencesStore` 結構：

```swift
@MainActor
@Observable
public final class RecentFoldersStore {
    public private(set) var entries: [RecentFolder]   // MRU，最新在最前

    public init(defaults: UserDefaults = .standard)   // 測試注入 in-memory suite

    public func record(path: String)        // 去重(同路徑) + 移到最前 + lastOpened=now + 存檔
    public func remove(path: String)        // 移除單筆 + 存檔
    public func clear()                     // 清空全部 + 存檔
    public func existingEntries() -> [RecentFolder]   // 過濾當前不存在的目錄後回傳
}
```

**關鍵行為：**

- **去重 + MRU：** 同一路徑只保留一筆；`record` 時若已存在則更新 `lastOpened` 並移到最前。
- **上限：** 儲存最多 **15 筆**，UI 透過 `existingEntries()` 取用時顯示最多 **10 筆**（避免選單過長）。超過上限時裁掉最舊的。
- **失效路徑：** `existingEntries()` 用 `FileManager` 過濾掉「當前不是有效目錄」的路徑（`isDirectory == true`），但**不從儲存中刪除**——暫時卸載的外接碟重新掛載後記錄會自動回來。唯有 `clear()` 與 `remove(path:)` 會真正從儲存移除。
- **immutable 更新：** 所有變更都產生新陣列再指派給 `entries`，不就地 mutate（符合 coding-style 的不可變原則）。
- **持久化格式：** `entries` 以 JSON（`JSONEncoder`/`Decoder`）編碼存於 `UserDefaults` 單一 key（例如 `"recentFolders.v1"`）；讀取失敗（解碼錯誤 / 無值）時回退為空陣列，不拋例外。

### 3. `ArchSightApp/WelcomeView.swift`（新檔）

未開啟任何 workspace（`state.roots.isEmpty`）時，於 `editorPane` 顯示，取代目前的 `ContentUnavailableView("Read Only", systemImage: "eye")`：

- 上半：`ArchSightIcon` + 標題（如「ArchSight」）+「Open Folder…」按鈕（呼叫 `openFolderPicker()`）。
- 下半「Recent」清單：`recentStore.existingEntries()` 前 10 筆，每列顯示 `📁 名稱` + 灰色縮寫路徑（用 `abbreviatingWithTildeInPath` 或 `FileSystemPaths`）；點擊 → `openRecent(path:)`。
- 每列 hover 時右側顯示小 `✕`，點擊 → `recentStore.remove(path:)`（單筆移除）。
- 清單為空時只顯示 icon + Open 按鈕與一行提示文字，不顯示空的「Recent」標題區塊。

### 4. `ArchSightApp/WorkspaceCommands.swift`（File 選單子選單）

- 在「Open Folder…」之後新增 `Menu("Open Recent")` 子選單。
- 列出 `recentStore.existingEntries()` 前 10 筆：每個 `Button(folder.name)`，`.help(folder.path)` 顯示完整路徑，點擊 → `actions?.openRecent(folder.path)`。
- 底部 `Divider()` + `Button("Clear Menu") { recentStore.clear() }`。
- 清單為空時整個子選單 `.disabled(true)`。
- `WorkspaceCommandActions` 新增欄位：`var openRecent: (String) -> Void = {}`。
- `WorkspaceMenuCommands` 比照 `readingStore` 接收 `recentStore`。

### 5. 接線（`ArchSightApp.swift` / `ContentView.swift`）

- **`ArchSightApp.swift`：** 新增 `@State private var recentStore = RecentFoldersStore()`，`.environment(recentStore)`，並傳入 `WorkspaceMenuCommands(readingStore:recentStore:)`。
- **`ContentView.swift`：**
  - 新增 `@Environment(RecentFoldersStore.self) private var recentStore`。
  - `reopenWorkspace` / `addRoots` 成功後，對回傳的 `result.roots` 逐一呼叫 `recentStore.record(path:)`（用核心確認過的真實路徑，而非使用者原始輸入）。
  - `focusedValue(\.workspaceCommands, ...)` 新增 `openRecent: { path in appendRoots([URL(fileURLWithPath: path)]) }`。
  - `editorPane` 的 `primaryPane`：當 `state.roots.isEmpty` 時改顯示 `WelcomeView`，否則維持既有（有 tab 顯示檔案、無 tab 顯示「Read Only」）。

---

## 資料流

```
開資料夾成功 (reopenWorkspace / addRoots)
   └─ 對每個 result.roots.path 呼叫 recentStore.record(path)
        └─ 去重 + 移到最前 + 裁切到 15 筆 + JSON 寫入 UserDefaults

重開（選單 Open Recent 或歡迎頁點擊）
   └─ actions.openRecent(path) / openRecent(path:)
        └─ appendRoots([URL(fileURLWithPath: path)])
             └─ reopenWorkspace(paths:) ← 既有流程（核心連線、tree 載入、錯誤處理共用）
```

---

## 錯誤處理

- **解碼失敗：** `UserDefaults` 中的 JSON 無法解碼時回退空陣列，不拋例外（與 `ReadingPreferencesStore` 容錯一致）。
- **路徑已不存在：** 不在 `record` 當下硬刪，改在 `existingEntries()` 顯示層過濾，保留暫時卸載卷宗的記錄；使用者可用 hover `✕` 或「Clear Menu」主動清除。
- **核心未連線：** 重開時若核心離線，沿用 `appendRoots` 既有的 `appendRootsLocally` 行為與錯誤訊息，不另外處理。

---

## 測試

單元測試只在 ArchSightKit，view 不寫測試（與現狀一致）。

### `Tests/ArchSightKitTests/RecentFoldersStoreTests.swift`

對齊 `ReadingPreferencesStoreTests`，用 `UserDefaults(suiteName:)` in-memory suite，涵蓋：

- `record` 新增單筆 → `entries` 含該筆、`lastOpened` 已設定。
- `record` 同路徑兩次 → 仍只一筆，且移到最前（MRU）。
- `record` 多筆 → 順序為最新在前。
- 超過 15 筆上限 → 裁掉最舊、總數維持 15。
- `remove(path:)` → 移除指定筆、其餘不變。
- `clear()` → 清空。
- 持久化往返：同一 suite 建立新 store → `entries` 還原一致。
- `existingEntries()`：給一個真實存在的臨時目錄與一個不存在的路徑 → 只回存在者，且**儲存中的 entries 不被刪除**。

### 手動驗證

`scripts/build-app.sh`（或 `swift build` + 跑起來）後：

1. 開兩三個資料夾 → 確認 File ▸ Open Recent 子選單與歡迎頁皆列出。
2. 關閉 App 重開 → 記錄仍在。
3. 點選單／歡迎頁任一筆 → 正確重開該資料夾。
4. 歡迎頁某筆 hover `✕` → 該筆消失。
5. 「Clear Menu」→ 清單清空、子選單變 disabled、歡迎頁不再顯示 Recent 區塊。

---

## 不做的事（YAGNI）

- 釘選 / pinning、拖放排序最近清單。
- 記錄最近「檔案」（跨 workspace）。
- 跨裝置 / iCloud 同步。
- 為「Open Recent」子選單指定額外快捷鍵（macOS 標準也無預設）。
