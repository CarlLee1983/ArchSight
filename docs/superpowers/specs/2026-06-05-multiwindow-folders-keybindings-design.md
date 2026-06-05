# 多視窗、多資料夾穩定共存與快捷鍵補齊 Design

**日期**：2026-06-05
**狀態**：設計已核可，待寫 plan
**工作目錄**：`apps/macos`（Swift）、`core`（Go）

## 目標

整體介面對標 VSCode 後，補齊三條主線：

1. **多視窗**：啟用真・多視窗（VSCode 風），所有視窗共用單一 core 行程。
2. **多資料夾**：修正加入第二個資料夾時整包重掃、且無法移除資料夾的問題；改為增量掃描、可移除/關閉。
3. **快捷鍵**：補齊對標 VSCode 的鍵盤快捷鍵，包含新做的 `Cmd+P` 快速開檔與 `Cmd+F` 檔內尋找。

全程維持產品邊界：read-only 觀測工具、單一 core、增量/惰性掃描、靜態記憶體盡量貼近 `M <= 50MB`。

## 非目標

- 不做編輯、自動完成、診斷、背景索引（AGENTS.md 既有邊界）。
- 不持久化 workspace 快照到磁碟。
- 不改既有閱讀偏好/主題化機制。

---

## 現況（問題根因）

- **每視窗各起一個 core**：`ContentView` 自帶 `@State coreSession = CoreSessionFactory.fromEnvironment()`，每個視窗各自啟動一個 core 行程。
- **開不了第二視窗**：`ArchSightApp` 以 `CommandGroup(replacing: .newItem) {}` 把 `New Window` / `Cmd+N` 整組移除。
- **加資料夾整包重掃**：`appendRoots → reopenWorkspace` 每次都用新的 `workspaceId` 重開整個 workspace，大樹會閃爍/卡頓。
- **無法移除資料夾**：沒有任何移除/關閉 root 的途徑。
- **core root id 是位置性的**：`buildRoots` 以 `fmt.Sprintf("root_%d", i+1)` 依索引指派，移除/重排會破壞既有分頁的 `rootID:path` 對應。
- **快捷鍵用隱形按鈕 hack**：以 `opacity(0)` 的 `Button` 註冊快捷鍵，無法進選單列，跨視窗路由也不正確。

---

## 第 1 部分：多視窗 + 共用單一 core

### 架構

- 新增 App 級 `@Observable AppCore`（位於 App target），持有唯一的 `CoreSession`，App 啟動時連線一次，對外只暴露：
  - `endpoint: CoreServiceEndpoint?`
  - `status: CoreSessionStatus`
- `ArchSightApp` 建立 `AppCore`、`.environment(appCore)` 注入；`WindowGroup` 內每個 `ContentView` 透過 `@Environment(AppCore.self)` 取得共用 endpoint。
- `ContentView` 移除自有的 `coreSession`/`coreEndpoint` 狀態。每個視窗仍保有獨立的 `WorkspaceViewState`（roots/tabs/search 各自獨立），但都打同一個 socket → core 內多個 `workspaceId` 並存。
- 視窗關閉時，對應的 workspaceId 留在 core；core 既有的惰性/閒置回收機制負責清理（不在本設計擴張回收策略）。

### New Window 指令

- `ArchSightApp` 改用 `.commands { ... }` 提供 `New Window`（`Cmd+N`），不再用空的 `.newItem` 把它整組砍掉；仍不提供「New File」（read-only）。

### 取捨

唯一合理解法。core 本來就是多 workspace 設計，零 core 改動即可共用。捨棄「每視窗各起一個 core」（違反單一 core、記憶體目標）。

---

## 第 2 部分：多資料夾穩定共存 + 移除/關閉（方案 A）

### core 改動（Go）

`core/internal/workspace/manager.go`：

1. **root id 改為單調穩定**：每個 `Snapshot` 維護自己的 root id 計數器（如 `nextRootID atomic.Uint64` 或 snapshot 欄位）。`addRoots` 接續編號、`removeRoot` 不重編號、不重用已釋出的 id。徹底取代位置性 `root_%d`。
2. **`AddRoots(workspaceId, paths)`**：對既有 snapshot 追加 roots，只掃**新增的 root**並把 entries 併入既有 entries（維持既有排序規則）。回傳更新後的 snapshot（含完整 roots，entries 視 IPC 既有形狀）。
3. **`RemoveRoot(workspaceId, rootId)`**：移除該 root 與其所有 entries；其餘 root 的 id 不變。

`core/internal/ipc/server.go`：新增兩個 RPC：

- `addRoots`：params `{ workspaceId, roots: [path] }`，行為等同 `Open` 的掃描-輪詢-就緒，但作用於既有 workspace、只掃新 root。
- `removeRoot`：params `{ workspaceId, rootId }`，回傳更新後的 roots/entries 或成功狀態。

搜尋 `resolveRoot` 等既有以 roots 迭代的邏輯不變（仍在單一 workspace 內）。

### Swift 端

`ArchSightKit`：

- `CoreServicing` / `CoreClient` 增加 `addRoots`、`removeRoot` 對應方法。
- `WorkspaceController` 增加：
  - `addRoots(workspaceId:paths:)`：呼叫 core `addRoots`、輪詢就緒、回傳更新後的 tree。
  - `removeRoot(workspaceId:rootId:)`：呼叫 core `removeRoot`、回傳更新後的 tree。
- `WorkspaceViewState`：新增純值邏輯
  - `removeRoot(id:)`：自 `roots`/`entries` 移除該 root，並**連帶關閉屬於該 root 的 openTabs**（依 `FileTab.rootID` 比對）、修正 `selectedTabID`、清掉指向該 root 的 references。
  - `closeWorkspace()`：清空 roots/entries/openTabs/search/references/selectedTabID（回到空工作區，但保留同一 workspaceId 供再次 add）。

`ContentView`：

- `appendRoots` 改走 `addRoots`（既有 workspace 存在時）而非 `reopenWorkspace`；首次（尚無 workspaceId）才 `openWorkspace`。
- 側邊欄 root `Section` 加右鍵選單：
  - **Remove Folder from Workspace**（對個別 root）→ 呼叫 `removeRoot`。
  - **Close Folder**（清空整個工作區）→ `closeWorkspace`。
- 移除/關閉後刷新 `sidebarTreeNodes`、`expandedPaths` 內屬於該 root 的路徑可一併清除。

### 取捨

- 採方案 A，最符合 AGENTS.md 增量掃描；前端維持單一 `workspaceId`、搜尋/定義/參考呼叫不變。
- 捨棄方案 B（純前端、仍整包重掃）與方案 C（每 root 一 workspace、需跨 workspace fan-out 搜尋、改動搜尋語意）。

---

## 第 3 部分：快捷鍵補齊（對標 VSCode）

改用 SwiftUI `Commands`（選單列真項目＋快捷鍵）取代 `opacity(0)` 隱形按鈕 hack。跨視窗路由用 `@FocusedValue`：`ContentView` 以 `.focusedValue(...)` 暴露一組指令動作（或一個輕量 command target），`Commands` 讀 `@FocusedValue` 將指令送到**當前作用中視窗**。

### 綁現有功能（基本盤）

| 快捷鍵 | 動作 | 接點 |
|---|---|---|
| `Cmd+O` | 開啟資料夾 | `openFolderPicker()` |
| `Cmd+N` | 新視窗 | SwiftUI New Window |
| `Cmd+B` | 切換側邊欄 | `isSidebarVisible` |
| `Cmd+Shift+E` | 聚焦 Explorer 分頁 | `activeSidebarTab = .explorer` + 顯示側邊欄 |
| `Cmd+Shift+F` | 聚焦 Search 分頁 | `activeSidebarTab = .search` + 顯示側邊欄 |
| `Cmd+\` | 切換分割檢視 | `isSplit` |
| `Cmd+1`~`Cmd+9` | 跳到第 N 個分頁 | `state.openTabs[N-1]` + `history.visit` |
| `Cmd+=` / `Cmd+-` | 字級 A+ / A− | `ReadingPreferencesStore.increaseFont()/decreaseFont()` |
| `Cmd+[` / `Cmd+]` | 上一頁 / 下一頁 | 沿用 `goBack()/goForward()` |
| `Cmd+Shift+[` / `]` | 切上/下分頁 | 沿用 `selectPreviousTab/selectNextTab` |

`Cmd+1~9` 與字級的選取/visit 規則沿用既有 `selectAndRecord`。

### 要新做功能

**`Cmd+P` 快速開檔**

- 新增覆蓋式面板（sheet 或 ZStack overlay）：`TextField` + 模糊比對後的檔案清單（取自 `state.fileEntries`），上下鍵移動選取、Enter 開啟、Esc 關閉，沿用 `FileIconMapper` 顯示圖示。
- 模糊比對演算法放 `ArchSightKit`（純值、可單元測試）：subsequence 比對 + 排序分數（連續命中、起頭命中、檔名命中加權）。
- 元件：`Sources/ArchSightApp/QuickOpenPanel.swift`（UI）、`Sources/ArchSightKit/FuzzyMatch.swift`（演算法）。

**`Cmd+F` 檔內尋找**

- 在 `CodeNSTextView` 啟用原生 find bar：`usesFindBar = true`、`isIncrementalSearchingEnabled = true`；`Cmd+F` 透過 `performTextFinderAction(_:)` 觸發，原生上一個/下一個。
- 純 App target 改動，無 Kit 測試（原生行為）。

**`Cmd+W` 語意修正**

- 有分頁 → 關閉當前分頁（`closeSelectedTab`）；無分頁 → 關閉視窗（`NSApp.keyWindow?.performClose(nil)`）。

---

## 第 4 部分：測試與驗證

### Kit 單元測試（TDD）

- `FuzzyMatchTests`：比對命中/落空、排序（連續命中優先、起頭命中加權、檔名命中優先於路徑命中）、大小寫不敏感、空查詢回傳全集或穩定順序。
- `WorkspaceViewStateTests`（擴充）：`removeRoot(id:)` 移除 roots/entries 並連帶關閉該 root 的分頁、修正 selection；`closeWorkspace()` 清空但保留 workspaceId。

### core 測試（Go，方案 A）

- `AddRoots` 只掃新 root、entries 正確併入、root id 接續且不重用。
- `RemoveRoot` 只刪該 root entries、其餘 root id 不變。
- IPC：`addRoots`/`removeRoot` round-trip（params 解析、回應形狀）。

### 手動驗證

1. `Cmd+N` 開兩個視窗各開不同資料夾；`ps`/`lsof` 確認**只有一個 core 行程**。
2. 加入第二個資料夾：既有分頁/選取/展開不受影響，僅新 root 出現（無整包閃爍）。
3. 右鍵 root → Remove Folder：該 root 與其分頁消失，其餘不動；Close Folder 回到空工作區。
4. 逐項過快捷鍵：`Cmd+O/B/\\`、`Cmd+Shift+E/F`、`Cmd+1~9`、`Cmd+=/-`、`Cmd+[`/`]`、`Cmd+Shift+[`/`]`。
5. `Cmd+P` 模糊開檔、上下鍵 + Enter；`Cmd+F` 在程式碼檢視內尋找上一個/下一個；`Cmd+W` 有/無分頁兩種情境。

### 完成標準

`swift test` + `swift build`（`apps/macos`）與 `go test ./...`（`core`）全綠。

---

## 第 5 部分：拆分為兩份 plan

共用 Commands/`FocusedValue` 基礎建設，先 A 後 B：

- **Plan A — 架構**：共用 core（`AppCore`）+ 多視窗 scene + `New Window` + 多資料夾 add/remove（core RPC `addRoots`/`removeRoot` + 穩定 root id）+ 側邊欄 Remove/Close UI。
- **Plan B — 快捷鍵**：`Commands` + `FocusedValue` 路由、基本盤綁定、`Cmd+P` 快速開檔（含 `FuzzyMatch`）、`Cmd+F` find bar、`Cmd+W` 語意、`Cmd+1~9`。

### 檔案影響速覽

**新增**
- `apps/macos/Sources/ArchSightApp/AppCore.swift`（Plan A）
- `apps/macos/Sources/ArchSightApp/QuickOpenPanel.swift`（Plan B）
- `apps/macos/Sources/ArchSightKit/FuzzyMatch.swift`（Plan B）
- 對應測試檔

**修改**
- `apps/macos/Sources/ArchSightApp/ArchSightApp.swift`（AppCore 注入、Commands、New Window）
- `apps/macos/Sources/ArchSightApp/ContentView.swift`（讀 AppCore、addRoots/removeRoot 接線、右鍵選單、FocusedValue、QuickOpen 觸發）
- `apps/macos/Sources/ArchSightApp/CodeTextView.swift`（find bar）
- `apps/macos/Sources/ArchSightKit/WorkspaceViewState.swift`（removeRoot/closeWorkspace）
- `apps/macos/Sources/ArchSightKit/WorkspaceController.swift`、`CoreClient.swift`、`IPC.swift`（addRoots/removeRoot）
- `core/internal/workspace/manager.go`（穩定 root id、AddRoots、RemoveRoot）
- `core/internal/ipc/server.go`（addRoots/removeRoot RPC）
