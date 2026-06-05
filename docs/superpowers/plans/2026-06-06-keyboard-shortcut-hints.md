# 快捷鍵提示（Cheat Sheet + Tooltip）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增可發現快捷鍵的兩種提示：`Cmd+/` 叫出的分類一覽表浮層，以及工具列 tooltip 補上快捷鍵符號，兩者共用一份 `ShortcutCatalog` 顯示來源。

**Architecture:** 在 `ArchSightKit` 以純值型別 `KeyChord` / `ShortcutHint` / `ShortcutCatalog` 定義「顯示用單一目錄」（單元測試守住格式與無重複綁定）；App target 以 `ShortcutCheatSheet` 覆蓋式視圖渲染目錄，並透過既有 `WorkspaceCommandActions` + `@FocusedValue` 接 `Cmd+/`；工具列 `.help()` 從目錄補快捷鍵。實際 `keyboardShortcut` 綁定不動。

**Tech Stack:** Swift 6 / SwiftPM、SwiftUI（`Commands`/`FocusedValue`/`onKeyPress`）、XCTest。

設計來源：`docs/superpowers/specs/2026-06-06-keyboard-shortcut-hints-design.md`。**前置依賴：Plan B 已完成**（`WorkspaceCommands.swift`、`WorkspaceCommandActions`、`ContentView` 的 `.focusedValue` 與 Quick Open overlay 皆已存在）。

工作目錄：`apps/macos`。所有 `swift` 指令在該目錄執行。

---

## 檔案結構

**新增**
- `apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift` — `ShortcutCategory`、`KeyChord`（含 `.display`）、`ShortcutHint`、`ShortcutCatalog`（`all` / `hint(_:)` / `grouped()`）。
- `apps/macos/Sources/ArchSightApp/ShortcutCheatSheet.swift` — 覆蓋式一覽表視圖。

**修改**
- `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift` — `WorkspaceCommandActions` 加 `showShortcuts`；Help 選單加「Keyboard Shortcuts」（`Cmd+/`）。
- `apps/macos/Sources/ArchSightApp/ContentView.swift` — `isShortcutsPresented` 狀態、overlay、`focusedValue` 接線、工具列 tooltip 補快捷鍵。

**測試**
- `apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift`

---

# Phase 1 — ShortcutCatalog（Kit, TDD）

## Task 1: KeyChord 顯示格式

**Files:**
- Create: `apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift`

- [x] **Step 1: Write the failing test**

`apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift`:
```swift
import XCTest
@testable import ArchSightKit

final class ShortcutCatalogTests: XCTestCase {
    func testKeyChordDisplayUsesCanonicalModifierOrder() {
        // macOS canonical order is ⌃⌥⇧⌘ immediately before the key.
        XCTAssertEqual(KeyChord(key: "P", command: true).display, "⌘P")
        XCTAssertEqual(KeyChord(key: "[", command: true, shift: true).display, "⇧⌘[")
        XCTAssertEqual(KeyChord(key: "E", command: true, shift: true).display, "⇧⌘E")
        XCTAssertEqual(KeyChord(key: "\\", command: true).display, "⌘\\")
        XCTAssertEqual(KeyChord(key: "/", command: true).display, "⌘/")
        XCTAssertEqual(
            KeyChord(key: "K", command: true, shift: true, option: true, control: true).display,
            "⌃⌥⇧⌘K"
        )
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShortcutCatalogTests`
Expected: FAIL（`cannot find 'KeyChord' in scope`）。

- [x] **Step 3: Write minimal implementation**

`apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift`:
```swift
import Foundation

/// A keyboard chord for *display* purposes only (cheat sheet + tooltips). The
/// actual `keyboardShortcut` bindings live in the App target; this mirrors them
/// so the on-screen hints stay consistent in one place.
public struct KeyChord: Equatable, Sendable {
    public let key: String
    public let command: Bool
    public let shift: Bool
    public let option: Bool
    public let control: Bool

    public init(
        key: String,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// macOS-canonical glyph order ⌃⌥⇧⌘ immediately preceding the key.
    public var display: String {
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        result += key
        return result
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter ShortcutCatalogTests`
Expected: PASS。

- [x] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift
git commit -m "feat: [macos] add KeyChord display formatter for shortcut hints"
```

---

## Task 2: ShortcutHint、ShortcutCategory、ShortcutCatalog

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift`

- [x] **Step 1: Write the failing test**

在 `ShortcutCatalogTests` 內新增：
```swift
    func testCatalogIsNonEmptyAndEveryCategoryHasEntries() {
        XCTAssertFalse(ShortcutCatalog.all.isEmpty)
        for category in ShortcutCategory.allCases {
            XCTAssertTrue(
                ShortcutCatalog.all.contains { $0.category == category },
                "category \(category) has no shortcuts"
            )
        }
    }

    func testCatalogIdsAreUnique() {
        let ids = ShortcutCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate shortcut id")
    }

    func testCatalogChordsAreUnique() {
        // No two hints should claim the same physical chord (catches double-binding).
        let chords = ShortcutCatalog.all.map(\.chord)
        XCTAssertEqual(chords.count, Set(chords.map(\.display)).count, "duplicate chord")
    }

    func testHintLookupHitAndMiss() {
        XCTAssertEqual(ShortcutCatalog.hint("quickOpen")?.chord.display, "⌘P")
        XCTAssertNil(ShortcutCatalog.hint("nope"))
    }

    func testGroupedCoversAllCategoriesInDeclaredOrder() {
        let grouped = ShortcutCatalog.grouped()
        XCTAssertEqual(grouped.map(\.0), ShortcutCategory.allCases)
        let flattenedCount = grouped.reduce(0) { $0 + $1.1.count }
        XCTAssertEqual(flattenedCount, ShortcutCatalog.all.count)
    }
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShortcutCatalogTests`
Expected: FAIL（`cannot find 'ShortcutCatalog' / 'ShortcutCategory' / 'ShortcutHint'`）。

- [x] **Step 3: Write minimal implementation**

在 `apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift` 末端新增：
```swift
public enum ShortcutCategory: String, CaseIterable, Sendable {
    case navigation
    case view
    case tabs
    case help

    public var title: String {
        switch self {
        case .navigation: return "Navigation"
        case .view: return "View"
        case .tabs: return "Tabs"
        case .help: return "Help"
        }
    }
}

public struct ShortcutHint: Equatable, Sendable, Identifiable {
    public let id: String
    public let category: ShortcutCategory
    public let label: String
    public let chord: KeyChord

    public init(id: String, category: ShortcutCategory, label: String, chord: KeyChord) {
        self.id = id
        self.category = category
        self.label = label
        self.chord = chord
    }
}

/// Single display source for keyboard hints. Mirrors the bindings declared in
/// `WorkspaceMenuCommands` / `ContentView`; kept consistent via unit tests.
public enum ShortcutCatalog {
    public static let all: [ShortcutHint] = [
        // Navigation
        ShortcutHint(id: "newWindow", category: .navigation, label: "New Window", chord: KeyChord(key: "N", command: true)),
        ShortcutHint(id: "openFolder", category: .navigation, label: "Open Folder", chord: KeyChord(key: "O", command: true)),
        ShortcutHint(id: "quickOpen", category: .navigation, label: "Quick Open", chord: KeyChord(key: "P", command: true)),
        ShortcutHint(id: "findInFile", category: .navigation, label: "Find in File", chord: KeyChord(key: "F", command: true)),
        ShortcutHint(id: "back", category: .navigation, label: "Back", chord: KeyChord(key: "[", command: true)),
        ShortcutHint(id: "forward", category: .navigation, label: "Forward", chord: KeyChord(key: "]", command: true)),
        // View
        ShortcutHint(id: "toggleSidebar", category: .view, label: "Toggle Sidebar", chord: KeyChord(key: "B", command: true)),
        ShortcutHint(id: "showExplorer", category: .view, label: "Show Explorer", chord: KeyChord(key: "E", command: true, shift: true)),
        ShortcutHint(id: "showSearch", category: .view, label: "Show Search", chord: KeyChord(key: "F", command: true, shift: true)),
        ShortcutHint(id: "splitEditor", category: .view, label: "Split Editor", chord: KeyChord(key: "\\", command: true)),
        ShortcutHint(id: "increaseText", category: .view, label: "Increase Text Size", chord: KeyChord(key: "=", command: true)),
        ShortcutHint(id: "decreaseText", category: .view, label: "Decrease Text Size", chord: KeyChord(key: "-", command: true)),
        // Tabs
        ShortcutHint(id: "goToTab", category: .tabs, label: "Go to Tab 1–9", chord: KeyChord(key: "1–9", command: true)),
        ShortcutHint(id: "previousTab", category: .tabs, label: "Previous Tab", chord: KeyChord(key: "[", command: true, shift: true)),
        ShortcutHint(id: "nextTab", category: .tabs, label: "Next Tab", chord: KeyChord(key: "]", command: true, shift: true)),
        ShortcutHint(id: "closeTab", category: .tabs, label: "Close Tab / Window", chord: KeyChord(key: "W", command: true)),
        // Help
        ShortcutHint(id: "shortcuts", category: .help, label: "Keyboard Shortcuts", chord: KeyChord(key: "/", command: true)),
    ]

    public static func hint(_ id: String) -> ShortcutHint? {
        all.first { $0.id == id }
    }

    public static func grouped() -> [(ShortcutCategory, [ShortcutHint])] {
        ShortcutCategory.allCases.map { category in
            (category, all.filter { $0.category == category })
        }
    }
}
```

> 註：`KeyChord` 已是 `Equatable`，但測試用 `Set(chords.map(\.display))` 比對顯示字串以涵蓋「不同欄位但顯示相同」的情況。

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter ShortcutCatalogTests`
Expected: PASS。

- [x] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift
git commit -m "feat: [macos] add ShortcutCatalog display source for shortcut hints"
```

---

# Phase 2 — Cheat sheet 浮層 + Cmd+/（App, build + 手動）

## Task 3: ShortcutCheatSheet 視圖

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/ShortcutCheatSheet.swift`

> App target 無單元測試慣例；以 `swift build` 與 Task 6 手動驗證把關。

- [x] **Step 1: 建立 ShortcutCheatSheet**

`apps/macos/Sources/ArchSightApp/ShortcutCheatSheet.swift`:
```swift
import ArchSightKit
import SwiftUI

/// Overlay listing all keyboard shortcuts grouped by category. Style mirrors
/// `QuickOpenPanel` (material, rounded, shadow). Reads `ShortcutCatalog` so the
/// hints never drift from the tooltips.
struct ShortcutCheatSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("esc")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ShortcutCatalog.grouped(), id: \.0) { category, hints in
                        if !hints.isEmpty {
                            section(category, hints)
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 24)
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func section(_ category: ShortcutCategory, _ hints: [ShortcutHint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            ForEach(hints) { hint in
                HStack {
                    Text(hint.label)
                        .font(.system(size: 12))
                    Spacer(minLength: 16)
                    Text(hint.chord.display)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```
> `ForEach(..., id: \.0)`：`ShortcutCategory` 為 `Hashable`（`String` raw enum），可作為 id。

- [x] **Step 2: Build 驗證**

Run: `swift build`
Expected: 編譯成功（此時尚未有人呈現它，Task 4–5 接線）。

- [x] **Step 3: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/ShortcutCheatSheet.swift
git commit -m "feat: [macos] add keyboard shortcut cheat sheet view"
```

---

## Task 4: WorkspaceCommands 加 showShortcuts + Help 選單

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift`

- [x] **Step 1: WorkspaceCommandActions 加 showShortcuts**

在 `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift` 的 `struct WorkspaceCommandActions` 內，於 `previousTab` 之後新增一行：
```swift
    var previousTab: () -> Void = {}
    var showShortcuts: () -> Void = {}
```

- [x] **Step 2: 加 Help 選單項（Cmd+/）**

在 `WorkspaceMenuCommands.body` 的 `CommandMenu("Go") { ... }` 之後新增：
```swift
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { actions?.showShortcuts() }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(actions == nil)
        }
```

- [x] **Step 3: Build 驗證**

Run: `swift build`
Expected: 編譯成功。

- [x] **Step 4: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift
git commit -m "feat: [macos] add Keyboard Shortcuts help menu command (Cmd+/)"
```

---

## Task 5: ContentView 接 overlay、focusedValue、tooltip

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

- [x] **Step 1: 新增狀態**

在 `apps/macos/Sources/ArchSightApp/ContentView.swift`，於 `@State private var isQuickOpenPresented = false` 之後新增：
```swift
    @State private var isQuickOpenPresented = false
    @State private var isShortcutsPresented = false
```

- [x] **Step 2: 加 cheat sheet overlay**

在 `body` 既有的 Quick Open `.overlay { ... }`（內含 `QuickOpenPanel`）之後，緊接新增第二個 overlay：
```swift
        .overlay {
            if isShortcutsPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { isShortcutsPresented = false }
                    ShortcutCheatSheet(onClose: { isShortcutsPresented = false })
                        .padding(.top, 48)
                }
            }
        }
```

- [x] **Step 3: focusedValue 接 showShortcuts**

在既有 `.focusedValue(\.workspaceCommands, WorkspaceCommandActions( ... ))` 中，於 `previousTab:` 那一行之後新增：
```swift
            previousTab: { selectAndRecord { state.selectPreviousTab() } },
            showShortcuts: { isShortcutsPresented = true }
```
> 注意：上一行原本結尾無逗號（是最後一個參數），新增後需在 `previousTab` 那行末補逗號，`showShortcuts` 成為最後一個參數（無逗號）。

- [x] **Step 4: 工具列 tooltip 補快捷鍵**

在 `toolbarContent` 內，把四個按鈕的 `.help(...)` 改為帶快捷鍵：

Back 按鈕：
```swift
            Button { goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!history.canGoBack)
                .help("Back \(ShortcutCatalog.hint("back")?.chord.display ?? "")")
```
Forward 按鈕：
```swift
            Button { goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!history.canGoForward)
                .help("Forward \(ShortcutCatalog.hint("forward")?.chord.display ?? "")")
```
Open Folder 按鈕（既有無 `.help`，新增一個）：
```swift
            Button { openFolderPicker() } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .help("Open Folder \(ShortcutCatalog.hint("openFolder")?.chord.display ?? "")")
```
Split 切換（既有 `.help("Compare two files side by side")` 改為附帶快捷鍵）：
```swift
            Toggle(isOn: $isSplit) {
                Label("Split", systemImage: "rectangle.split.2x1")
            }
            .help("Split Editor \(ShortcutCatalog.hint("splitEditor")?.chord.display ?? "") · compare two files")
```

- [x] **Step 5: Build 驗證**

Run: `swift build`
Expected: 編譯成功。

- [x] **Step 6: 全測試確認無回歸**

Run: `swift test`
Expected: PASS。

- [x] **Step 7: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] present shortcut cheat sheet and add shortcut tooltips"
```

---

# Phase 3 — 手動驗證

## Task 6: 逐項驗證

**Files:** 無（驗證）

- [x] **Step 1: 啟動**

Run: `swift run ArchSight`，開一個資料夾、開數個檔成分頁。

- [x] **Step 2: 逐項確認**

1. `Cmd+/` 叫出一覽表浮層；分類（Navigation / View / Tabs / Help）與每項快捷鍵符號正確。
2. `Esc` 關閉；再開後點半透明背景也能關閉。
3. 選單列 Help → 有「Keyboard Shortcuts ⌘/」可點，亦能叫出一覽表。
4. 工具列懸停 Back / Forward / Open Folder / Split → tooltip 顯示對應快捷鍵（⌘[ / ⌘] / ⌘O / ⌘\）。
5. 在 Quick Open（`Cmd+P`）或 Search 輸入框打 `/` → 不會誤觸一覽表（只有 `Cmd+/` 會）。
6. 一覽表內顯示的每個快捷鍵，實際按下去行為相符（抽查 `⌘P`、`⌘B`、`⌘\`、`⌘1`）。

- [x] **Step 3: 收尾**

Run: `swift test` 與 `swift build` 各一次確認綠燈。功能完成。

---

## Self-review 對照

- 規格「一覽表浮層」→ Task 3（視圖）、Task 4（`Cmd+/` + Help 選單）、Task 5 Step 2–3（overlay + 接線）。
- 規格「工具列 tooltip 加快捷鍵」→ Task 5 Step 4。
- 規格「顯示用單一目錄 + 一致性測試」→ Task 1（`KeyChord.display`）、Task 2（`ShortcutCatalog` + 無重複綁定測試）。
- 規格目錄共 17 項（Navigation 6：New Window/Open Folder/Quick Open/Find in File/Back/Forward；View 6：Toggle Sidebar/Show Explorer/Show Search/Split Editor/Increase/Decrease；Tabs 4：Go to Tab/Previous/Next/Close；Help 1：Keyboard Shortcuts）→ Task 2 `all` 完整列出。
- 型別一致性：`KeyChord(key:command:shift:option:control:)`、`ShortcutHint(id:category:label:chord:)`、`ShortcutCatalog.hint(_:)` / `grouped()`、`WorkspaceCommandActions.showShortcuts`、`isShortcutsPresented` 在各 Task 命名一致。
