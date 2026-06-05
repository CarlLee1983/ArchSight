# ArchSight UI/UX Design Optimization Spec

- **Author**: Antigravity (AI Coding Assistant)
- **Date**: 2026-06-05
- **Status**: Proposed / Under Review
- **Reference Issue**: 優化 app 介面設計感

---

## 1. Background & Goals

ArchSight is a native macOS read-only code observation tool. The current user interface relies heavily on standard macOS default styles, resulting in a somewhat cluttered and generic appearance. The goal of this specification is to elevate the UI design aesthetic to make it feel **premium, modern, and highly usable for professional developers**.

We will achieve this through three targeted enhancements:
1. **Clean SVG Vector Icons (SF Symbols)**: Replace basic emoji indicators with context-aware, polished vector icons matching the OS environment.
2. **Configurable Open Files Layout**:
   - **Style A (Vertical Cards)**: A compact double-line card view for the middle pane showing file name and path breadcrumbs.
   - **Style B (Horizontal Tabs)**: A modern horizontal tab bar on top of the editor pane, allowing the middle pane to be collapsed when not searching.
   - **Dropdown Selector (D)**: A toolbar dropdown menu to switch between layouts.
3. **Core Status Pill**: A rounded connection badge with a pulsing LED-like status indicator.

---

## 2. Technical Architecture & State Changes

### 2.1 ReadingPreferences & Storage
We will introduce a `TabLayoutMode` preference to persistent configuration.

```swift
// Location: apps/macos/Sources/ArchSightKit/ReadingPreferences.swift

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

We will update `ReadingPreferences` to include `tabLayoutMode`:
```swift
public struct ReadingPreferences: Equatable, Sendable, Codable {
    public var theme: ReadingThemeID
    public var fontScale: Double
    public var lineSpacing: LineSpacing
    public var tabLayoutMode: TabLayoutMode // New property

    // For backward compatibility with older plist/json data
    enum CodingKeys: String, CodingKey {
        case theme
        case fontScale
        case lineSpacing
        case tabLayoutMode
    }
}
```

We will implement a custom `init(from decoder: Decoder)` to ensure old persisted configurations default to `.verticalList` instead of failing to decode:
```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.theme = try container.decodeIfPresent(ReadingThemeID.self, forKey: .theme) ?? .system
    self.fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
    self.lineSpacing = try container.decodeIfPresent(LineSpacing.self, forKey: .lineSpacing) ?? .normal
    self.tabLayoutMode = try container.decodeIfPresent(TabLayoutMode.self, forKey: .tabLayoutMode) ?? .verticalList
}
```

We will expose a setter on `ReadingPreferencesStore`:
```swift
public func setTabLayoutMode(_ mode: TabLayoutMode) {
    update { $0.tabLayoutMode = mode }
}
```

---

## 3. UI Component Details

### 3.1 Sidebar File Tree Icons
We will map file extensions and folders to appropriate SF Symbols inside `sidebarNode` in `ContentView.swift`.
- Directories: `folder` (default) or `folder.fill` (when selected).
- `.swift` files: `swift` (if available in system SF Symbols) or `doc.text.fill` / `curlybraces`.
- `.md` / `.markdown` files: `doc.richtext`.
- Configuration (`Package.swift`, `go.mod`, `JSON` etc): `doc.text.fill` or `gearshape.fill`.
- Default files: `doc.text`.

We will also adjust padding, typography (monospaced for filenames in tree), and hover styles to clean up visual density.

### 3.2 Open Files: Vertical Card List (Style A)
In the middle pane, when `tabLayoutMode` is `.verticalList` or `.both`, we will display a card-based list of open files:
- Each item is rendered as a VStack:
  - Header: Filename in **bold** or regular font (e.g. `ContentView.swift`).
  - Subtitle: Relative path leading to it in a smaller, muted secondary gray font (e.g. `apps/macos/Sources/ArchSightApp`).
  - Leading: An elegant icon (SF Symbol) styled with subtle syntax colors (e.g. Orange for Swift, Blue for markdown).
  - Trailing: A small `xmark` button that is highlighted on hover.
- Selected item will have a highlighted background with standard system accent colors.

### 3.3 Open Files: Horizontal Tab Bar (Style B)
A new horizontal tab bar will be implemented and rendered at the top of `editorPane`:
- Fits on top of the editor content.
- Displays each open file as a tab: `Icon + Filename + Close Button`.
- Active tab has a distinct background and bottom border matching the theme.
- Inactive tabs are slightly transparent and dim.
- Supports horizontal scrolling if tabs exceed window width.

### 3.4 Middle Column Auto-Collapse Behavior
When `tabLayoutMode` is `.horizontalTabs`:
- If the search results list is empty, the middle pane should collapse to save space.
- We will track `NavigationSplitViewVisibility` in `ContentView.swift`:
  ```swift
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  ```
  And update it inside `.onChange(of: readingStore.preferences.tabLayoutMode)` and `.onChange(of: state.searchResults.isEmpty)`:
  - If `tabLayoutMode == .horizontalTabs` and `state.searchResults.isEmpty` -> `columnVisibility = .doubleColumn` (hides content pane).
  - Else -> `columnVisibility = .all`.

### 3.5 Core Connection Status Pill
In the toolbar, we will replace the plain status labels with a pill-shaped indicator:
- Style: A rounded pill badge with background alpha matching the connection state.
- Icon: A small circular LED dot.
- Animation:
  - **Connected**: Green dot, solid.
  - **Connecting**: Orange/yellow dot, pulsing.
  - **Offline/Failed**: Gray/red dot, solid.
- Text: e.g. "Core v1.1.0" or "Connecting..." in a compact size.

### 3.6 Toolbar Dropdown Menu Selector
We will add a layout layout selector in the toolbar:
- Button: `Image(systemName: "rectangle.split.3x1")` or `Image(systemName: "sidebar.left")`.
- Action: Dropdown Menu showing:
  - `[✓] Vertical Cards List`
  - `[ ] Horizontal Tabs`
  - `[ ] Split / Both`
- Clicking any option updates `readingStore.setTabLayoutMode(...)`.

---

## 4. Implementation Steps & Verification Plan

### Phase 1: ArchSightKit Modifications
- Add `TabLayoutMode` enum in `ReadingPreferences.swift`.
- Add `tabLayoutMode` property and custom `Codable` compliance.
- Implement `setTabLayoutMode` in `ReadingPreferencesStore.swift`.
- Verify with unit tests that `ReadingPreferences` correctly falls back to `.verticalList` when decoding older versions.

### Phase 2: ContentView Layout Updates
- Introduce `columnVisibility` state.
- Implement `HorizontalTabBar` component.
- Update `middleColumn` to render the clean vertical double-line card list.
- Integrate middle column auto-collapse logic.
- Integrate toolbar dropdown menu.
- Integrate the new Core Status Pill.
- Build the app and run tests to ensure no regressions.

---

## 5. Self-Review & Verification Check

1. **Placeholder Scan**: No TODOs or TBDs. All interfaces and variables are explicitly defined.
2. **Consistency**: The toggle menu in the toolbar maps directly to state variables, which automatically trigger SwiftUI re-renders and auto-collapsing.
3. **Scope Check**: Clear visual enhancement scope focused on `ContentView.swift`, `ReadingControlsView.swift`, and `ReadingPreferences.swift`. No unnecessary refactoring of the backend core.
