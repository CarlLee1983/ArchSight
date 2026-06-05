# ArchSight VS Code-Like 2-Column Layout and Custom Vector Icons Spec

- **Author**: Antigravity (AI Coding Assistant)
- **Date**: 2026-06-05
- **Status**: Proposed / Under Review
- **Reference Issue**: 重構整體介面為 VS Code/Cursor 風格與自定義向量圖示

---

## 1. Background & Goals

ArchSight 是一個原生 macOS 的唯讀代碼觀察工具。本規格書旨在優化其整體介面，仿照 VS Code/Cursor 的經典結構重構版面，提升設計感並維持核心的輕量與低資源佔用特點。

本規格書將落實以下兩大核心改進：
1. **VS Code 風格經典雙欄佈局 (2-Column NavigationSplitView with Activity Bar)**：
   - 建立左側常駐的垂直 **Activity Bar (活動列)**。
   - 將原本的 3 欄式佈局簡化為 **2 欄式佈局**，側邊欄根據 Activity Bar 點選狀態動態切換顯示「檔案瀏覽器 (Explorer)」或「全文搜尋 (Search)」。
   - 側邊欄內部以摺疊面板形式整合「工作區樹狀圖」與「已開啟檔案 (Open Files)」列表。
   - 視窗底部新增精確、緊湊的 **Status Bar (狀態列)**。
2. **純代碼 SwiftUI Vector Icons (完全去 Emoji 化)**：
   - 設計一整套精巧、極簡的向量圖示（包括資料夾、檔案、搜尋、設定、關閉、核心狀態指示燈等），利用 SwiftUI `Path` / `Shape` 以純代碼繪製，實現高性能、零資源包載入的自定義渲染。

---

## 2. Technical Architecture & State Changes

### 2.1 State Model Updates
我們需要在 `ContentView` 中新增活動分頁的狀態管理：

```swift
enum SidebarTab: String, CaseIterable, Sendable {
    case explorer
    case search
}
```

在 `ContentView.swift` 中新增以下 `@State` 屬性：
- `activeSidebarTab: SidebarTab` (預設為 `.explorer`)
- `columnVisibility: NavigationSplitViewVisibility` (預設為 `.all`)

### 2.2 NavigationSplitView 結構調整
將原本的 3 欄式結構：
```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    sidebar
} content: {
    middleColumn
} detail: {
    editorPane
}
```
重構為以 `HStack` 橫向封裝 Activity Bar 與 2 欄式 `NavigationSplitView` 的架構：
```swift
HStack(spacing: 0) {
    activityBar // 左側常駐 48pt
    Divider()
    NavigationSplitView(columnVisibility: $columnVisibility) {
        sidebarPanel // 根據 activeSidebarTab 顯示內容
    } detail: {
        editorPane // 編輯器主要視圖與分頁
    }
}
```

---

## 3. UI Component Details

### 3.1 Activity Bar (左側活動列)
- **視覺規範**：
  - 寬度固定為 `48pt`。
  - 背景採用 `.background(.ultraThinMaterial)` 毛玻璃質感。
  - 上方排列：**Explorer**、**Search** 圖示按鈕；底部排列：**Settings** 圖示按鈕。
  - 當按鈕處於選取狀態時，圖示高亮且左側顯示一條細長的 `2pt` 垂直 AccentColor 標記條。
  - 滑鼠游標 Hover 時，顯示半透明的圓角高亮背景效果。

### 3.2 Dynamic Sidebar (動態側邊欄)
根據 `activeSidebarTab` 的值，側邊欄將動態載入對應的視圖：

1. **Explorer View (檔案瀏覽器)**：
   - **已開啟檔案 (Open Files)** 面板：固定在側邊欄最上方或以摺疊分組顯示。顯示目前已開啟的分頁，每個分頁格式為：`自定義檔案圖示 + 檔案名稱`，右側帶有纖細的 Hover 關閉按鈕。
   - **工作區樹 (Workspace Trees)** 面板：緊接在已開啟檔案下方，使用自定義的 `FolderIcon`（線條圓角資料夾，取代 Emoji）與 `FileIcon`（紙張折角圖示）渲染階層目錄。
2. **Search View (全文搜尋)**：
   - 上方整合一個緊湊的搜尋輸入框 (TextField)，右側帶有正則表達式及大小寫敏感的切換按鈕。
   - 下方直接顯示 `ripgrep` 搜尋結果的列表，點選後在右側編輯器中開啟。

### 3.3 Custom Vector Icons (純 SwiftUI Path 圖示)
在 `ArchSightIcon.swift` 中以純 SwiftUI Path 描繪以下圖示以取代任何 Emoji：
- `ExplorerIcon`：代表檔案總管，兩個重疊的虛線框或檔案圖案。
- `SearchIcon`：放大鏡。
- `SettingsIcon`：齒輪。
- `FolderIcon` (閉合與展開狀態)：
  - 閉合：`Path` 繪製帶有左上角斜切標籤的圓角矩形資料夾。
  - 展開：`Path` 繪製開口且有前後層次感的資料夾。
- `FileIcon`：紙張折角，中心帶有兩條程式碼線條。
- `CloseIcon`：細緻的斜角對稱 `x` 叉號。

### 3.4 Status Bar (狀態列)
- **位置**：貼齊視窗最底部，高度 `22pt`，背景為細緻的半透明灰色或 AccentColor，與上方主畫面以 1px 分割線區分。
- **內容**：
  - 左側：`StatusIndicatorIcon` (連線狀態指示燈) + Core 狀態說明。
  - 右側：當前開啟檔案的游標位置 `Ln X, Col Y`。

---

## 4. Implementation Steps

### Phase 1: 向量圖示庫實作
1. 新建 [ArchSightIcon.swift](file:///Users/carl/Dev/CMG/ArchSight/apps/macos/Sources/ArchSightApp/ArchSightIcon.swift) 並實作自定義向量形狀 (`Shape` / `View` + `Path`)。
2. 更新 [FileIconMapper.swift](file:///Users/carl/Dev/CMG/ArchSight/apps/macos/Sources/ArchSightApp/FileIconMapper.swift) 以回傳自定義向量圖示而非舊的 SF Symbols。

### Phase 2: Activity Bar 與狀態管理
1. 在 `ContentView.swift` 中建立 `SidebarTab` 列舉與 `activeSidebarTab` 狀態。
2. 實作 `ActivityBar` 視圖，處理點選切換邏輯與側邊欄的展開/摺疊。

### Phase 3: 2 欄式 NavigationSplitView 改造與 Sidebar 動態切換
1. 修改 `ContentView.body` 結構，刪除 `content:` 閉包，將 `NavigationSplitView` 改為 2 欄模式。
2. 將 `middleColumn` 的搜尋結果列表與已開啟檔案列表，重新整合到 `sidebarPanel` 中對應的分頁檢視。
3. 調整樣式以融合 Activity Bar、側邊欄和編輯器的分割線。

### Phase 4: Status Bar 與細節美化
1. 實作底部 `StatusBarView`，並在視窗下方使用 `.safeAreaInset(edge: .bottom)` 或佈局容器進行定位。
2. 全面微調元件邊距、懸停效果、字型和色彩層次。

---

## 5. Verification Plan

1. **編譯驗證**：在 `apps/macos` 下執行建置指令以確保無 Swift 編譯錯誤。
2. **版面佈局測試**：點選 Activity Bar 中的按鈕，驗證側邊欄是否能正確在 Explorer 與 Search 之間進行流暢切換；點選當前選取的分頁，驗證側邊欄是否能正確收起與展開。
3. **搜尋整合測試**：在側邊欄 Search 分頁中輸入關鍵字，確認 ripgrep 搜尋結果正常顯示於側邊欄，且雙擊可直接在編輯器開啟檔案並跳轉至指定行數。
4. **效能與記憶體檢查**：驗證在載入大型工作區時，雙欄架構配合自定義向量圖示沒有造成任何記憶體洩漏或效能下降，常駐靜態記憶體保持在 `M <= 50MB` 內。
