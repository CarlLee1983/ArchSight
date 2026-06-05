# UI/UX Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize ArchSight UI design by replacing emojis with SF Symbols, introducing a customizable vertical/horizontal open files layout switcher via toolbar dropdown, and a modern pulsating status indicator.

**Architecture:** Update `ReadingPreferences` in `ArchSightKit` to persist `tabLayoutMode`, implement new SwiftUI views (`HorizontalTabBar`, card layout items, status pill badge) in `ArchSightApp`, and bind dynamic visibility in `ContentView.swift`.

**Tech Stack:** Swift, SwiftUI, AppKit

---

### Task 1: Add TabLayoutMode to ArchSightKit

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/ReadingPreferences.swift`
- Modify: `apps/macos/Sources/ArchSightKit/ReadingPreferencesStore.swift`
- Modify: `apps/macos/Tests/ArchSightKitTests/ReadingPreferencesTests.swift`

- [ ] **Step 1: Update ReadingPreferences.swift**
  Add the `TabLayoutMode` enum, update `ReadingPreferences` properties, update initializer, coding keys, and implement custom decoding for backward compatibility.
  
  Code change to `apps/macos/Sources/ArchSightKit/ReadingPreferences.swift`:
  ```swift
  public enum TabLayoutMode: String, CaseIterable, Codable, Sendable {
      case verticalList
      case horizontalTabs
      case both

      public var displayName: String {
          switch self {
          case .verticalList: return "Vertical Cards"
          case .horizontalTabs: return "Horizontal Tabs"
          case .both: return "Both Layouts"
          }
      }
  }
  ```
  
  And update `ReadingPreferences`:
  ```swift
  public struct ReadingPreferences: Equatable, Sendable, Codable {
      public var theme: ReadingThemeID
      public var fontScale: Double
      public var lineSpacing: LineSpacing
      public var tabLayoutMode: TabLayoutMode // New property

      public init(theme: ReadingThemeID, fontScale: Double, lineSpacing: LineSpacing, tabLayoutMode: TabLayoutMode = .verticalList) {
          self.theme = theme
          self.fontScale = fontScale
          self.lineSpacing = lineSpacing
          self.tabLayoutMode = tabLayoutMode
      }

      public static let `default` = ReadingPreferences(theme: .system, fontScale: 1.0, lineSpacing: .normal, tabLayoutMode: .verticalList)
      
      private enum CodingKeys: String, CodingKey {
          case theme
          case fontScale
          case lineSpacing
          case tabLayoutMode
      }

      public init(from decoder: Decoder) throws {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          self.theme = try container.decodeIfPresent(ReadingThemeID.self, forKey: .theme) ?? .system
          self.fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
          self.lineSpacing = try container.decodeIfPresent(LineSpacing.self, forKey: .lineSpacing) ?? .normal
          self.tabLayoutMode = try container.decodeIfPresent(TabLayoutMode.self, forKey: .tabLayoutMode) ?? .verticalList
      }

      public func encode(to encoder: Encoder) throws {
          var container = encoder.container(keyedBy: CodingKeys.self)
          try container.encode(theme, forKey: .theme)
          try container.encode(fontScale, forKey: .fontScale)
          try container.encode(lineSpacing, forKey: .lineSpacing)
          try container.encode(tabLayoutMode, forKey: .tabLayoutMode)
      }
  ```

- [ ] **Step 2: Update ReadingPreferencesStore.swift**
  Add the setter method for the layout mode in `ReadingPreferencesStore.swift`:
  ```swift
  public func setTabLayoutMode(_ mode: TabLayoutMode) {
      update { $0.tabLayoutMode = mode }
  }
  ```

- [ ] **Step 3: Update ReadingPreferencesTests.swift**
  Write tests to verify `TabLayoutMode` display names and backward-compatible decoding.
  ```swift
  func testTabLayoutModeDisplayName() {
      XCTAssertEqual(TabLayoutMode.verticalList.displayName, "Vertical Cards")
      XCTAssertEqual(TabLayoutMode.horizontalTabs.displayName, "Horizontal Tabs")
      XCTAssertEqual(TabLayoutMode.both.displayName, "Both Layouts")
  }

  func testDecodingBackwardCompatibility() throws {
      // JSON representation of old preferences without tabLayoutMode
      let oldJSON = """
      {
          "theme": "solarized",
          "fontScale": 1.3,
          "lineSpacing": "relaxed"
      }
      """
      let data = oldJSON.data(using: .utf8)!
      let decoded = try JSONDecoder().decode(ReadingPreferences.self, from: data)
      XCTAssertEqual(decoded.theme, .solarized)
      XCTAssertEqual(decoded.fontScale, 1.3, accuracy: 0.001)
      XCTAssertEqual(decoded.lineSpacing, .relaxed)
      XCTAssertEqual(decoded.tabLayoutMode, .verticalList) // defaulted
  }
  ```

- [ ] **Step 4: Run tests to verify failure**
  Run: `swift test --package-path apps/macos`
  Expected: Compile errors/failures due to missing components if not implemented correctly, or verify successful tests once files are saved.

- [ ] **Step 5: Commit changes**
  Run:
  ```bash
  git add apps/macos/Sources/ArchSightKit/ReadingPreferences.swift apps/macos/Sources/ArchSightKit/ReadingPreferencesStore.swift apps/macos/Tests/ArchSightKitTests/ReadingPreferencesTests.swift
  git commit -m "feat: add TabLayoutMode and backward compatible decoding to ArchSightKit"
  ```

---

### Task 2: Create HorizontalTabBar View Component

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/HorizontalTabBar.swift`

- [ ] **Step 1: Write HorizontalTabBar.swift**
  Create a new file `apps/macos/Sources/ArchSightApp/HorizontalTabBar.swift` with the tab bar and tab item views.
  
  ```swift
  import SwiftUI
  import ArchSightKit

  struct HorizontalTabBar: View {
      let openTabs: [FileTab]
      @Binding var selectedTabID: FileTab.ID?
      let onCloseTab: (FileTab.ID) -> Void
      
      var body: some View {
          ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 0) {
                  ForEach(openTabs) { tab in
                      let fileName = URL(fileURLWithPath: tab.path).lastPathComponent
                      let isActive = tab.id == selectedTabID
                      
                      Button {
                          selectedTabID = tab.id
                      } label: {
                          HStack(spacing: 6) {
                              Image(systemName: fileIconName(for: fileName))
                                  .foregroundColor(fileIconColor(for: fileName))
                                  .font(.system(size: 11))
                              
                              Text(fileName)
                                  .font(.system(size: 11, design: .monospaced))
                                  .fontWeight(isActive ? .semibold : .regular)
                              
                              Button {
                                  onCloseTab(tab.id)
                              } label: {
                                  Image(systemName: "xmark")
                                      .font(.system(size: 8, weight: .bold))
                                      .padding(3)
                                      .contentShape(Rectangle())
                              }
                              .buttonStyle(.plain)
                              .opacity(isActive ? 0.8 : 0.4)
                          }
                          .padding(.horizontal, 10)
                          .frame(height: 32)
                          .background(isActive ? Color(NSColor.textBackgroundColor) : Color.clear)
                          .contentShape(Rectangle())
                      }
                      .buttonStyle(.plain)
                      .overlay(
                          VStack {
                              Spacer()
                              if isActive {
                                  Rectangle()
                                      .fill(Color.accentColor)
                                      .frame(height: 2)
                              } else {
                                  Divider()
                              }
                          }
                      )
                  }
              }
          }
          .background(Color(NSColor.windowBackgroundColor))
          .frame(height: 32)
          .overlay(
              VStack {
                  Spacer()
                  Divider()
              }
          )
      }
      
      private func fileIconName(for fileName: String) -> String {
          let lower = fileName.lowercased()
          if lower.hasSuffix(".swift") {
              return "swift"
          } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
              return "doc.richtext"
          } else if lower == "package.swift" || lower == "go.mod" || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
              return "doc.text.fill"
          } else {
              return "doc.text"
          }
      }
      
      private func fileIconColor(for fileName: String) -> Color {
          let lower = fileName.lowercased()
          if lower.hasSuffix(".swift") {
              return .orange
          } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
              return .blue
          } else if lower == "package.swift" || lower == "go.mod" {
              return .purple
          } else if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
              return .pink
          } else {
              return .secondary
          }
      }
  }
  ```

- [ ] **Step 2: Commit**
  Run:
  ```bash
  git add apps/macos/Sources/ArchSightApp/HorizontalTabBar.swift
  git commit -m "feat: add HorizontalTabBar component for tab layouts"
  ```

---

### Task 3: Implement ContentView Visual Updates

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

- [ ] **Step 1: Update Sidebar tree layout to use SF Symbols**
  Replace emoji icons with SF Symbols in `sidebarNode` method and add the helper methods `iconName(for:)` and `iconColor(for:)`.
  
  Target to replace:
  ```swift
  private func sidebarNode(_ node: WorkspaceTreeNode) -> AnyView {
      if node.isDirectory {
          return AnyView(DisclosureGroup {
              ForEach(node.children) { child in
                  sidebarNode(child)
              }
          } label: {
              Label(node.name, systemImage: "folder")
                  .font(.system(.caption, design: .default))
                  .help(node.path)
          })
      } else {
          return AnyView(Label(node.name, systemImage: "doc.text")
              .font(.system(.caption, design: .monospaced))
              .help(node.path)
              .tag(node.entry.id)
              .contentShape(Rectangle()))
      }
  }
  ```
  
  Replacement implementation:
  ```swift
  private func sidebarNode(_ node: WorkspaceTreeNode) -> AnyView {
      if node.isDirectory {
          return AnyView(DisclosureGroup {
              ForEach(node.children) { child in
                  sidebarNode(child)
              }
          } label: {
              HStack(spacing: 6) {
                  Image(systemName: iconName(for: node))
                      .foregroundColor(iconColor(for: node))
                      .imageScale(.small)
                  Text(node.name)
                      .font(.system(.caption, design: .default))
              }
              .help(node.path)
          })
      } else {
          return AnyView(
              HStack(spacing: 6) {
                  Image(systemName: iconName(for: node))
                      .foregroundColor(iconColor(for: node))
                      .imageScale(.small)
                  Text(node.name)
                      .font(.system(.caption, design: .monospaced))
              }
              .help(node.path)
              .tag(node.entry.id)
              .contentShape(Rectangle())
          )
      }
  }

  private func iconName(for node: WorkspaceTreeNode) -> String {
      if node.isDirectory {
          return "folder"
      }
      let lower = node.name.lowercased()
      if lower.hasSuffix(".swift") {
          return "swift"
      } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
          return "doc.richtext"
      } else if lower == "package.swift" || lower == "go.mod" || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
          return "doc.text.fill"
      } else {
          return "doc.text"
      }
  }

  private func iconColor(for node: WorkspaceTreeNode) -> Color {
      if node.isDirectory {
          return .accentColor
      }
      let lower = node.name.lowercased()
      if lower.hasSuffix(".swift") {
          return .orange
      } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
          return .blue
      } else if lower == "package.swift" || lower == "go.mod" {
          return .purple
      } else if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
          return .pink
      } else {
          return .secondary
      }
  }
  ```

- [ ] **Step 2: Implement double-line cards in middle column**
  Refactor `fileList` in `ContentView.swift` to use the double-line layout and file type icons.
  
  Code change to `fileList`:
  ```swift
  private var fileList: some View {
      let manualSelection = Binding<FileTab.ID?>(
          get: { state.selectedTabID },
          set: { newValue in
              state.selectedTabID = newValue
              if let newValue {
                  history.visit(newValue)
                  pendingScrollLine = nil
              }
          }
      )
      return List(selection: manualSelection) {
          ForEach(state.openTabs) { tab in
              let fileName = URL(fileURLWithPath: tab.path).lastPathComponent
              let relativePath = URL(fileURLWithPath: tab.path).deletingLastPathComponent().path
              
              HStack(spacing: 10) {
                  Image(systemName: fileIconName(for: fileName))
                      .foregroundColor(fileIconColor(for: fileName))
                      .font(.system(size: 14))
                      .frame(width: 18)
                  
                  VStack(alignment: .leading, spacing: 2) {
                      Text(fileName)
                          .font(.system(size: 11, weight: .semibold, design: .monospaced))
                          .lineLimit(1)
                      if !relativePath.isEmpty && relativePath != "." {
                          Text(relativePath)
                              .font(.system(size: 9))
                              .foregroundColor(.secondary)
                              .lineLimit(1)
                      }
                  }
                  
                  Spacer()
                  
                  Button {
                      state.closeTab(id: tab.id)
                  } label: {
                      Image(systemName: "xmark")
                          .font(.system(size: 8, weight: .bold))
                          .padding(4)
                          .background(Color.secondary.opacity(0.1))
                          .clipShape(Circle())
                  }
                  .buttonStyle(.plain)
                  .foregroundStyle(.secondary)
                  .help("Close tab")
              }
              .padding(.vertical, 4)
              .tag(tab.id)
          }
      }
      .navigationTitle("Open Files")
      .overlay {
          if state.openTabs.isEmpty {
              ContentUnavailableView("No File", systemImage: "doc.text")
          }
      }
  }

  private func fileIconName(for fileName: String) -> String {
      let lower = fileName.lowercased()
      if lower.hasSuffix(".swift") {
          return "swift"
      } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
          return "doc.richtext"
      } else if lower == "package.swift" || lower == "go.mod" || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
          return "doc.text.fill"
      } else {
          return "doc.text"
      }
  }

  private func fileIconColor(for fileName: String) -> Color {
      let lower = fileName.lowercased()
      if lower.hasSuffix(".swift") {
          return .orange
      } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
          return .blue
      } else if lower == "package.swift" || lower == "go.mod" {
          return .purple
      } else if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
          return .pink
      } else {
          return .secondary
      }
  }
  ```

- [ ] **Step 3: Implement StatusPill and refactor Core Status Label**
  Create the `StatusPill` subview in `ContentView.swift` and use it in `coreStatusLabel`.
  
  ```swift
  struct StatusPill: View {
      let text: String
      let color: Color
      let pulsing: Bool
      
      @State private var isAnimating = false
      
      var body: some View {
          HStack(spacing: 5) {
              Circle()
                  .fill(color)
                  .frame(width: 6, height: 6)
                  .opacity(pulsing && isAnimating ? 0.4 : 1.0)
                  .scaleEffect(pulsing && isAnimating ? 1.25 : 1.0)
                  .animation(
                      pulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                      value: isAnimating
                  )
                  .onAppear {
                      if pulsing {
                          isAnimating = true
                      }
                  }
              Text(text)
                  .font(.system(size: 10, weight: .semibold))
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Capsule().fill(color.opacity(0.12)))
          .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 0.5))
          .foregroundColor(color)
      }
  }
  ```
  
  Refactor `coreStatusLabel`:
  ```swift
  private var coreStatusLabel: some View {
      Group {
          switch coreStatus {
          case .disconnected:
              StatusPill(text: "Offline", color: .gray, pulsing: false)
          case .connecting:
              StatusPill(text: "Connecting", color: .yellow, pulsing: true)
          case .connected(let health):
              StatusPill(text: "Core \(health.version)", color: .green, pulsing: false)
          case .failed:
              StatusPill(text: "Failed", color: .red, pulsing: false)
          }
      }
      .help("Core Service Status")
  }
  ```

- [ ] **Step 4: Integrate layout visibility & toolbar dropdown menu**
  Add state property `columnVisibility` to `ContentView`:
  ```swift
  @State private var columnVisibility = NavigationSplitViewVisibility.all
  ```
  
  Update `body` to pass `$columnVisibility`:
  ```swift
  NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebar
  } content: {
      middleColumn
  } detail: {
      editorPane
  }
  ```
  
  Add picker in toolbar:
  ```swift
  private func systemImage(for mode: TabLayoutMode) -> String {
      switch mode {
      case .verticalList: return "sidebar.left"
      case .horizontalTabs: return "rectangle.grid.1x2"
      case .both: return "rectangle.split.3x1"
      }
  }
  ```
  
  Inside `toolbarContent` `ToolbarItemGroup` near `coreStatusLabel`:
  ```swift
  Menu {
      Picker("Layout Style", selection: Binding(
          get: { readingStore.preferences.tabLayoutMode },
          set: { readingStore.setTabLayoutMode($0) }
      )) {
          ForEach(TabLayoutMode.allCases, id: \.self) { mode in
              Label(mode.displayName, systemImage: systemImage(for: mode))
                  .tag(mode)
          }
      }
  } label: {
      Image(systemName: systemImage(for: readingStore.preferences.tabLayoutMode))
  }
  .menuStyle(.borderlessButton)
  .help("Layout Style")
  ```

- [ ] **Step 5: Dynamic Visibility Collapse logic**
  Add helper method:
  ```swift
  private func updateColumnVisibility() {
      if readingStore.preferences.tabLayoutMode == .horizontalTabs && state.searchResults.isEmpty {
          columnVisibility = .doubleColumn
      } else {
          columnVisibility = .all
      }
  }
  ```
  
  Add `.onChange` modifiers to the end of `body` of `ContentView`:
  ```swift
  .onChange(of: readingStore.preferences.tabLayoutMode) { _, _ in
      updateColumnVisibility()
  }
  .onChange(of: state.searchResults.isEmpty) { _, _ in
      updateColumnVisibility()
  }
  ```
  
  And call it in `.task`:
  ```swift
  .task {
      connectCoreIfConfigured()
      updateColumnVisibility()
  }
  ```

- [ ] **Step 6: Integrate HorizontalTabBar inside editorPane**
  Modify `editorPane`:
  ```swift
  @ViewBuilder
  private var editorPane: some View {
      VStack(spacing: 0) {
          if readingStore.preferences.tabLayoutMode == .horizontalTabs || readingStore.preferences.tabLayoutMode == .both {
              if !state.openTabs.isEmpty {
                  HorizontalTabBar(
                      openTabs: state.openTabs,
                      selectedTabID: Binding(
                          get: { state.selectedTabID },
                          set: { newValue in
                              selectAndRecord { state.selectedTabID = newValue }
                          }
                      ),
                      onCloseTab: { id in
                          state.closeTab(id: id)
                      }
                  )
              }
          }
          Group {
              if isSplit {
                  HSplitView {
                      primaryPane
                      comparisonPane
                  }
              } else {
                  primaryPane
              }
          }
      }
      .safeAreaInset(edge: .bottom) { referencesPanel }
  }
  ```

- [ ] **Step 7: Clean up middleColumn conditional display**
  Modify `middleColumn`:
  ```swift
  @ViewBuilder
  private var middleColumn: some View {
      if state.searchResults.isEmpty {
          if readingStore.preferences.tabLayoutMode == .horizontalTabs {
              Color.clear.frame(width: 0)
          } else {
              fileList
          }
      } else {
          searchResultsList
      }
  }
  ```

- [ ] **Step 8: Run Swift Build and Test**
  Run: `swift test --package-path apps/macos`
  Expected: All 99+ tests PASS successfully.
  
  Run: `swift build --package-path apps/macos`
  Expected: Successful compilation without warnings.

- [ ] **Step 9: Commit changes**
  Run:
  ```bash
  git add apps/macos/Sources/ArchSightApp/ContentView.swift
  git commit -m "feat: integrate layout mode switching, StatusPill, SF Symbols tree, and HorizontalTabBar"
  ```
