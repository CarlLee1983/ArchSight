# ArchSight VS Code-Like 2-Column Layout and Custom Vector Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重構 ArchSight 整體介面，實現仿 VS Code/Cursor 風格的 2 欄式佈局，並設計一組純 SwiftUI 代碼 Path 繪製的自定義向量圖示以取代 Emoji，提升介面整體設計感與質感，同時維持極佳的效能。

**Architecture:** 
1. 新建 `ArchSightIcon.swift` 用 SwiftUI `Path`/`Shape` 繪製自定義圖示。
2. 升級 `FileIconMapper.swift` 的對應邏輯，改為映射至 `CustomIconType` 並取得對應自定義圖示 View。
3. 調整 `HorizontalTabBar.swift` 樣式並引入自定義圖示。
4. 重構 `ContentView.swift`，在最左側加上活動列 (Activity Bar)，將 3 欄式 `NavigationSplitView` 簡化為 2 欄式（側邊欄根據 Activity Bar 項目動態載入 Explorer/搜尋面板），並於底部整合 Status Bar。

**Tech Stack:** Native Swift, SwiftUI, AppKit

---

### Task 1: 實作自定義向量圖示庫 (ArchSightIcon)

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/ArchSightIcon.swift`
- Test: Modify `apps/macos/Tests/ArchSightKitTests/ReadingThemeTests.swift`

- [ ] **Step 1: 建立自定義向量圖示與 Path 形狀**
  在 `apps/macos/Sources/ArchSightApp/` 新增 `ArchSightIcon.swift` 檔案，內容如下：

  ```swift
  import SwiftUI

  // MARK: - Shapes
  struct FolderIconShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let h = rect.height
          path.move(to: CGPoint(x: 1, y: 3))
          path.addLine(to: CGPoint(x: w * 0.4, y: 3))
          path.addLine(to: CGPoint(x: w * 0.5, y: 5))
          path.addLine(to: CGPoint(x: w - 1, y: 5))
          path.addLine(to: CGPoint(x: w - 1, y: h - 2))
          path.addLine(to: CGPoint(x: 1, y: h - 2))
          path.closeSubpath()
          return path
      }
  }

  struct FolderOpenIconShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let h = rect.height
          
          // Rear tab
          path.move(to: CGPoint(x: 1, y: 3))
          path.addLine(to: CGPoint(x: w * 0.35, y: 3))
          path.addLine(to: CGPoint(x: w * 0.45, y: 5))
          path.addLine(to: CGPoint(x: w - 2, y: 5))
          path.addLine(to: CGPoint(x: w - 2, y: 8))
          path.addLine(to: CGPoint(x: 1, y: 8))
          path.closeSubpath()
          
          // Front pocket (slanted)
          path.move(to: CGPoint(x: 1, y: 8))
          path.addLine(to: CGPoint(x: w - 1, y: 8))
          path.addLine(to: CGPoint(x: w - 3, y: h - 2))
          path.addLine(to: CGPoint(x: 3, y: h - 2))
          path.closeSubpath()
          
          return path
      }
  }

  struct FileIconShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let h = rect.height
          let fold = w * 0.35
          path.move(to: CGPoint(x: 1, y: 1))
          path.addLine(to: CGPoint(x: w - fold - 1, y: 1))
          path.addLine(to: CGPoint(x: w - 1, y: fold + 1))
          path.addLine(to: CGPoint(x: w - 1, y: h - 1))
          path.addLine(to: CGPoint(x: 1, y: h - 1))
          path.closeSubpath()
          return path
      }
  }

  struct FileIconFoldShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let fold = w * 0.35
          path.move(to: CGPoint(x: w - fold - 1, y: 1))
          path.addLine(to: CGPoint(x: w - fold - 1, y: fold + 1))
          path.addLine(to: CGPoint(x: w - 1, y: fold + 1))
          path.closeSubpath()
          return path
      }
  }

  struct SearchIconShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let h = rect.height
          let r = w * 0.3
          let cx = w * 0.4
          let cy = h * 0.4
          
          path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
          
          path.move(to: CGPoint(x: cx + r * 0.707, y: cy + r * 0.707))
          path.addLine(to: CGPoint(x: w - 2, y: h - 2))
          return path
      }
  }

  struct ExplorerIconShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let h = rect.height
          
          path.addRect(CGRect(x: 1, y: 1, width: w * 0.6, height: h * 0.6))
          path.addRect(CGRect(x: w * 0.35, y: h * 0.35, width: w * 0.6, height: h * 0.6))
          return path
      }
  }

  struct SettingsIconShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let h = rect.height
          let cx = w / 2
          let cy = h / 2
          let rOut = min(w, h) * 0.45
          let rIn = min(w, h) * 0.25
          
          path.addEllipse(in: CGRect(x: cx - rIn, y: cy - rIn, width: rIn * 2, height: rIn * 2))
          
          for i in 0..<8 {
              let angle = Double(i) * Double.pi / 4
              let x1 = cx + CGFloat(cos(angle)) * rIn
              let y1 = cy + CGFloat(sin(angle)) * rIn
              let x2 = cx + CGFloat(cos(angle)) * rOut
              let y2 = cy + CGFloat(sin(angle)) * rOut
              path.move(to: CGPoint(x: x1, y: y1))
              path.addLine(to: CGPoint(x: x2, y: y2))
          }
          return path
      }
  }

  struct CloseIconShape: Shape {
      func path(in rect: CGRect) -> Path {
          var path = Path()
          let w = rect.width
          let h = rect.height
          path.move(to: CGPoint(x: 1, y: 1))
          path.addLine(to: CGPoint(x: w - 1, y: h - 1))
          path.move(to: CGPoint(x: w - 1, y: 1))
          path.addLine(to: CGPoint(x: 1, y: h - 1))
          return path
      }
  }

  // MARK: - Components View wrappers
  public enum ArchSightIcon {
      public struct Folder: View {
          public var color: Color = .accentColor
          public init(color: Color = .accentColor) {
              self.color = color
          }
          public var body: some View {
              FolderIconShape()
                  .stroke(color, lineWidth: 1.2)
                  .frame(width: 13, height: 13)
          }
      }
      
      public struct FolderOpen: View {
          public var color: Color = .accentColor
          public init(color: Color = .accentColor) {
              self.color = color
          }
          public var body: some View {
              FolderOpenIconShape()
                  .stroke(color, lineWidth: 1.2)
                  .frame(width: 13, height: 13)
          }
      }
      
      public struct File: View {
          public var color: Color = .secondary
          public init(color: Color = .secondary) {
              self.color = color
          }
          public var body: some View {
              ZStack {
                  FileIconShape()
                      .stroke(color, lineWidth: 1.2)
                  FileIconFoldShape()
                      .stroke(color, lineWidth: 1.2)
              }
              .frame(width: 11, height: 13)
          }
      }
      
      public struct Search: View {
          public var color: Color = .primary
          public init(color: Color = .primary) {
              self.color = color
          }
          public var body: some View {
              SearchIconShape()
                  .stroke(color, lineWidth: 1.2)
                  .frame(width: 14, height: 14)
          }
      }
      
      public struct Explorer: View {
          public var color: Color = .primary
          public init(color: Color = .primary) {
              self.color = color
          }
          public var body: some View {
              ExplorerIconShape()
                  .stroke(color, lineWidth: 1.2)
                  .frame(width: 14, height: 14)
          }
      }
      
      public struct Settings: View {
          public var color: Color = .primary
          public init(color: Color = .primary) {
              self.color = color
          }
          public var body: some View {
              SettingsIconShape()
                  .stroke(color, lineWidth: 1.2)
                  .frame(width: 14, height: 14)
          }
      }
      
      public struct Close: View {
          public var color: Color = .secondary
          public init(color: Color = .secondary) {
              self.color = color
          }
          public var body: some View {
              CloseIconShape()
                  .stroke(color, lineWidth: 1.2)
                  .frame(width: 7, height: 7)
          }
      }
      
      public struct StatusIndicator: View {
          public var color: Color
          public var pulsing: Bool
          @State private var animate = false
          
          public init(color: Color, pulsing: Bool = false) {
              self.color = color
              self.pulsing = pulsing
          }
          
          public var body: some View {
              Circle()
                  .fill(color)
                  .frame(width: 6, height: 6)
                  .scaleEffect(pulsing && animate ? 1.3 : 1.0)
                  .opacity(pulsing && animate ? 0.5 : 1.0)
                  .onAppear {
                      if pulsing {
                          withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                              animate = true
                          }
                      }
                  }
          }
      }
  }
  ```

- [ ] **Step 2: 新增圖示編譯測試以確認架構穩定性**
  在 `apps/macos/Tests/ArchSightKitTests/ReadingThemeTests.swift` 中，新增測試以確保這些 Icon 模組能正常初始化：

  ```swift
  // 新增於 ReadingThemeTests 尾部或作為獨立方法
  func testCustomIconsCompileAndCanBeInstantiated() {
      // 驗證自定義向量圖示可被建立，確保無編譯與結構錯誤
      _ = ArchSightIcon.Folder()
      _ = ArchSightIcon.FolderOpen()
      _ = ArchSightIcon.File()
      _ = ArchSightIcon.Search()
      _ = ArchSightIcon.Explorer()
      _ = ArchSightIcon.Settings()
      _ = ArchSightIcon.Close()
      _ = ArchSightIcon.StatusIndicator(color: .green, pulsing: true)
      XCTAssertTrue(true)
  }
  ```

- [ ] **Step 3: 執行測試並驗證編譯通過**
  執行命令：
  ```bash
  swift test
  ```
  期望輸出：`Executed X tests, with 0 failures`

- [ ] **Step 4: 提交變更**
  ```bash
  git add apps/macos/Sources/ArchSightApp/ArchSightIcon.swift apps/macos/Tests/ArchSightKitTests/ReadingThemeTests.swift
  git commit -m "feat: add SwiftUI Path-based custom vector icons and test case"
  ```

---

### Task 2: 整合 FileIconMapper 改為向量圖示對應

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/FileIconMapper.swift`

- [ ] **Step 1: 重寫 FileIconMapper**
  修改 `apps/macos/Sources/ArchSightApp/FileIconMapper.swift` 的內容，將原有的字串與顏色對應更換為 `CustomIconType`：

  ```swift
  import SwiftUI

  public enum CustomIconType: Sendable {
      case folder
      case folderOpen
      case swift
      case markdown
      case config
      case defaultFile
      
      @ViewBuilder
      public func view(color: Color? = nil) -> some View {
          switch self {
          case .folder:
              ArchSightIcon.Folder(color: color ?? .accentColor)
          case .folderOpen:
              ArchSightIcon.FolderOpen(color: color ?? .accentColor)
          case .swift:
              ArchSightIcon.File(color: color ?? .orange)
          case .markdown:
              ArchSightIcon.File(color: color ?? .blue)
          case .config:
              ArchSightIcon.File(color: color ?? .purple)
          case .defaultFile:
              ArchSightIcon.File(color: color ?? .secondary)
          }
      }
  }

  enum FileIconMapper {
      static func iconType(for filename: String) -> CustomIconType {
          let lower = filename.lowercased()
          if lower == "package.swift" || lower == "go.mod" || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
              return .config
          }
          if lower.hasSuffix(".swift") {
              return .swift
          } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
              return .markdown
          } else {
              return .defaultFile
          }
      }
  }
  ```

- [ ] **Step 2: 執行測試確認無編譯問題**
  執行命令：
  ```bash
  swift test
  ```
  期望輸出：`Executed X tests, with 0 failures`

- [ ] **Step 3: 提交變更**
  ```bash
  git add apps/macos/Sources/ArchSightApp/FileIconMapper.swift
  git commit -m "refactor: upgrade FileIconMapper to support CustomIconType and SwiftUI views"
  ```

---

### Task 3: 調整 HorizontalTabBar 與分頁標籤樣式

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/HorizontalTabBar.swift`

- [ ] **Step 1: 使用自定義圖示並調整 Tab 樣式**
  修改 `apps/macos/Sources/ArchSightApp/HorizontalTabBar.swift`：
  - 將 `Image(systemName: FileIconMapper.iconName(for: filename))` 替換為 `FileIconMapper.iconType(for: filename).view()`。
  - 將關閉按鈕中的 `Image(systemName: "xmark")` 替換為 `ArchSightIcon.Close()`。
  - 微調 Tab 的背景色、圓角、懸停狀態以凸顯設計美感。

  ```swift
  // apps/macos/Sources/ArchSightApp/HorizontalTabBar.swift 的完整替換內容如下
  import SwiftUI
  import ArchSightKit
  import Foundation

  struct HorizontalTabBar: View {
      let openTabs: [FileTab]
      @Binding var selectedTabID: FileTab.ID?
      let onCloseTab: (FileTab.ID) -> Void

      var body: some View {
          ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 0) {
                  ForEach(openTabs) { tab in
                      let isSelected = selectedTabID == tab.id
                      let filename = (tab.path as NSString).lastPathComponent
                      
                      HStack(spacing: 6) {
                          FileIconMapper.iconType(for: filename).view()
                          
                          Text(filename)
                              .font(.system(size: 11, design: .monospaced))
                              .fontWeight(isSelected ? .semibold : .regular)
                              .foregroundColor(isSelected ? .primary : .secondary)
                              .lineLimit(1)
                          
                          Button(action: {
                              onCloseTab(tab.id)
                          }) {
                              ArchSightIcon.Close(color: isSelected ? .primary : .secondary)
                                  .padding(4)
                                  .contentShape(Rectangle())
                          }
                          .buttonStyle(.plain)
                          .help("Close Tab")
                          .opacity(isSelected ? 0.8 : 0.4)
                      }
                      .padding(.horizontal, 10)
                      .frame(height: 32)
                      .background(isSelected ? Color(NSColor.textBackgroundColor) : Color.clear)
                      .contentShape(Rectangle())
                      .onTapGesture {
                          selectedTabID = tab.id
                      }
                      .overlay(alignment: .bottom) {
                          if isSelected {
                              Rectangle()
                                  .fill(Color.accentColor)
                                  .frame(height: 2)
                          }
                      }
                      
                      if tab.id != openTabs.last?.id {
                          Divider()
                              .frame(height: 20)
                              .padding(.vertical, 6)
                      }
                  }
              }
          }
          .frame(height: 32)
          .background(Color(NSColor.windowBackgroundColor))
          .overlay(
              VStack {
                  Spacer()
                  Divider()
              }
          )
      }
  }
  ```

- [ ] **Step 2: 執行測試確認編譯正常**
  執行命令：
  ```bash
  swift test
  ```
  期望輸出：`Executed X tests, with 0 failures`

- [ ] **Step 3: 提交變更**
  ```bash
  git add apps/macos/Sources/ArchSightApp/HorizontalTabBar.swift
  git commit -m "style: polish HorizontalTabBar to use new custom vector icons and refined paddings"
  ```

---

### Task 4: 重構 ContentView 為 VS Code 風格之雙欄版面

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

- [ ] **Step 1: 修改頁面狀態變數與 icon 輔助函數**
  修改 `apps/macos/Sources/ArchSightApp/ContentView.swift`：
  - 新增 `SidebarTab` 列舉與 `activeSidebarTab` 的 `@State`。
  - 將原本的 3 欄式 `NavigationSplitView` 修改為 2 欄式（移除 `content:` 區塊），並將 `middleColumn` 的功能內嵌入側邊欄視圖。
  - 更新側邊欄檔案樹之資料夾圖示為 `ArchSightIcon.Folder()` 與 `ArchSightIcon.FolderOpen()`，以及檔案圖示為 `ArchSightIcon.File()`。
  - 實作左側的 `ActivityBar` 與底部的 `StatusBarView`，並為 Toolbar 做收納與整理。

  以下為 `ContentView.swift` 預計進行的修改細節：
  - 將 24-30 行之原本 3 欄 NavigationSplitView 替換為以 `HStack` 結合 `ActivityBar` 及 2 欄 NavigationSplitView 的代碼。
  - 設計 `sidebarPanel` View：
    - 當 `activeSidebarTab == .explorer` 時，顯示包含 Open Files 面板 (列表) 與 Workspace 檔案樹的 VStack。
    - 當 `activeSidebarTab == .search` 時，顯示包含搜尋輸入框與搜尋結果列表的 VStack。

  在 `apps/macos/Sources/ArchSightApp/ContentView.swift` 作為 TargetFile 使用 replace_file_content 進行修改。

  **程式碼修改對照：**
  在 `ContentView.swift` 內替換為：
  ```swift
  // 在 ContentView 結構體中新增 Tab 定義：
  enum SidebarTab: String, CaseIterable, Sendable {
      case explorer
      case search
  }
  ```
  
  並新增屬性：
  ```swift
  @State private var activeSidebarTab: SidebarTab = .explorer
  ```

  重構 `body` 如下：
  ```swift
  var body: some View {
      HStack(spacing: 0) {
          activityBar
          Divider()
          NavigationSplitView(columnVisibility: $columnVisibility) {
              sidebarPanel
          } detail: {
              editorPane
          }
      }
      .toolbar { toolbarContent }
      .background { keyboardShortcuts }
      .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
          handleDroppedFolders(providers)
      }
      .task {
          connectCoreIfConfigured()
      }
      .safeAreaInset(edge: .bottom) {
          statusBar
      }
  }
  ```

  新增 `activityBar` View：
  ```swift
  private var activityBar: some View {
      VStack(spacing: 16) {
          // Explorer Tab
          Button { handleTabClick(.explorer) } label: {
              VStack {
                  ArchSightIcon.Explorer(color: activeSidebarTab == .explorer ? .accentColor : .secondary)
              }
              .frame(width: 36, height: 36)
              .background(activeSidebarTab == .explorer ? Color.secondary.opacity(0.15) : Color.clear)
              .cornerRadius(6)
          }
          .buttonStyle(.plain)
          .help("File Explorer")
          .overlay(alignment: .leading) {
              if activeSidebarTab == .explorer {
                  Rectangle()
                      .fill(Color.accentColor)
                      .frame(width: 2, height: 20)
              }
          }
          
          // Search Tab
          Button { handleTabClick(.search) } label: {
              VStack {
                  ArchSightIcon.Search(color: activeSidebarTab == .search ? .accentColor : .secondary)
              }
              .frame(width: 36, height: 36)
              .background(activeSidebarTab == .search ? Color.secondary.opacity(0.15) : Color.clear)
              .cornerRadius(6)
          }
          .buttonStyle(.plain)
          .help("Search in Workspace")
          .overlay(alignment: .leading) {
              if activeSidebarTab == .search {
                  Rectangle()
                      .fill(Color.accentColor)
                      .frame(width: 2, height: 20)
              }
          }
          
          Spacer()
      }
      .padding(.top, 40)
      .padding(.horizontal, 6)
      .frame(width: 48)
      .background(Color(NSColor.windowBackgroundColor))
  }
  ```

  新增 `sidebarPanel` View：
  ```swift
  @ViewBuilder
  private var sidebarPanel: some View {
      VStack(spacing: 0) {
          switch activeSidebarTab {
          case .explorer:
              // Open Files
              if !state.openTabs.isEmpty {
                  Section(header: Text("OPEN FILES").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary).padding(.horizontal, 8).padding(.top, 8)) {
                      List(selection: Binding(
                          get: { state.selectedTabID },
                          set: { newValue in
                              state.selectedTabID = newValue
                              if let newValue {
                                  history.visit(newValue)
                                  pendingScrollLine = nil
                              }
                          }
                      )) {
                          ForEach(state.openTabs) { tab in
                              let fileName = (tab.path as NSString).lastPathComponent
                              HStack {
                                  FileIconMapper.iconType(for: fileName).view()
                                  Text(fileName)
                                      .font(.system(size: 11, design: .monospaced))
                                  Spacer()
                                  Button {
                                      state.closeTab(id: tab.id)
                                  } label: {
                                      ArchSightIcon.Close()
                                          .padding(4)
                                  }
                                  .buttonStyle(.plain)
                              }
                              .tag(tab.id)
                          }
                      }
                      .frame(maxHeight: 150)
                  }
                  Divider()
              }
              
              // Folder Tree
              List(selection: $sidebarSelection) {
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
              }
              .navigationTitle("Explorer")
              .overlay {
                  if state.roots.isEmpty {
                      ContentUnavailableView("No Workspace", systemImage: "folder")
                  }
              }
              
          case .search:
              VStack(spacing: 8) {
                  HStack {
                      TextField("Search Pattern", text: $state.searchQuery)
                          .textFieldStyle(.roundedBorder)
                          .onSubmit { runSearch() }
                      Button { runSearch() } label: {
                          Text("Go")
                      }
                  }
                  .padding(8)
                  
                  searchResultsList
              }
              .navigationTitle("Search")
          }
      }
  }
  ```

  修改 `sidebarNode` 的圖示映射：
  ```swift
  private func sidebarNode(_ node: WorkspaceTreeNode) -> AnyView {
      if node.isDirectory {
          return AnyView(DisclosureGroup {
              ForEach(node.children) { child in
                  sidebarNode(child)
              }
          } label: {
              HStack(spacing: 6) {
                  // 改用自定義向量圖示
                  ArchSightIcon.Folder()
                  Text(node.name)
                      .font(.system(.caption, design: .default))
              }
              .help(node.path)
          })
      } else {
          return AnyView(
              HStack(spacing: 6) {
                  // 改用自定義向量圖示
                  FileIconMapper.iconType(for: node.name).view()
                  Text(node.name)
                      .font(.system(.caption, design: .monospaced))
              }
              .help(node.path)
              .tag(node.entry.id)
              .contentShape(Rectangle())
          )
      }
  }
  ```

  修改 `statusBar` View：
  ```swift
  private var statusBar: some View {
      VStack(spacing: 0) {
          Divider()
          HStack {
              // Core connection indicator
              HStack(spacing: 4) {
                  switch coreStatus {
                  case .disconnected:
                      ArchSightIcon.StatusIndicator(color: .gray)
                      Text("Core offline").font(.system(size: 10)).foregroundColor(.secondary)
                  case .connecting:
                      ArchSightIcon.StatusIndicator(color: .yellow, pulsing: true)
                      Text("Core connecting").font(.system(size: 10)).foregroundColor(.secondary)
                  case .connected(let health):
                      ArchSightIcon.StatusIndicator(color: .green)
                      Text("Core \(health.version)").font(.system(size: 10)).foregroundColor(.secondary)
                  case .failed:
                      ArchSightIcon.StatusIndicator(color: .red)
                      Text("Core unavailable").font(.system(size: 10)).foregroundColor(.secondary)
                  }
              }
              
              if let message = state.errorMessage {
                  Spacer()
                  Text(message)
                      .font(.system(size: 10))
                      .foregroundColor(.red)
                      .lineLimit(1)
              }
              
              Spacer()
              
              // Workspace path / Cursor Position
              if let tab = selectedTab {
                  Text(tab.path)
                      .font(.system(size: 10))
                      .foregroundColor(.secondary)
                      .lineLimit(1)
              }
          }
          .padding(.horizontal, 12)
          .frame(height: 22)
          .background(Color(NSColor.windowBackgroundColor))
      }
  }
  ```

  新增點選 Tab 切換收折的方法：
  ```swift
  private func handleTabClick(_ tab: SidebarTab) {
      if activeSidebarTab == tab {
          columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
      } else {
          activeSidebarTab = tab
          columnVisibility = .all
      }
  }
  ```

- [ ] **Step 2: 執行測試與編譯應用程式**
  執行編譯命令：
  ```bash
  swift build
  ```
  確保能順利無編譯錯誤編譯出 ArchSight 可執行檔。

- [ ] **Step 3: 執行單元測試**
  執行命令：
  ```bash
  swift test
  ```
  期望輸出：`Executed X tests, with 0 failures`

- [ ] **Step 4: 提交變更**
  ```bash
  git add apps/macos/Sources/ArchSightApp/ContentView.swift
  git commit -m "feat: complete VS Code-like 2-column layout with ActivityBar and bottom StatusBar"
  ```
