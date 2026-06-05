# Plan B — 快捷鍵補齊（對標 VSCode）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以 SwiftUI `Commands` + `@FocusedValue` 為各視窗提供對標 VSCode 的快捷鍵，含新做的 `Cmd+P` 快速開檔與 `Cmd+F` 檔內尋找，並修正 `Cmd+W` 語意。

**Architecture:** 在 `ArchSightKit` 加可單元測試的 `FuzzyMatch`（subsequence 比對 + 排序）。App target 用 `WorkspaceCommandActions`（一組 closures）透過 `@FocusedValue` 把選單指令送到當前作用中視窗的 `ContentView` 狀態；`WorkspaceMenuCommands: Commands` 定義所有 menu/shortcut。`Cmd+P` 用覆蓋式 `QuickOpenPanel`；`Cmd+F` 啟用 `NSTextView` 原生 find bar；`Cmd+W` 用聚焦的隱形按鈕覆寫（有分頁關分頁、無分頁關視窗）。

**Tech Stack:** Swift 6 / SwiftPM、SwiftUI（`Commands`/`FocusedValue`）、AppKit（`NSTextView` find bar、`NSApp`）、XCTest。

設計來源：`docs/superpowers/specs/2026-06-05-multiwindow-folders-keybindings-design.md`（第 3、4 部分）。**前置依賴：Plan A 已完成**（`AppCore`、多視窗、移除 `.newItem` 空替換）。

工作目錄：`apps/macos`。所有 `swift` 指令在該目錄執行。

---

## 檔案結構

**新增**
- `apps/macos/Sources/ArchSightKit/FuzzyMatch.swift` — 模糊比對與排序（純值、可測）。
- `apps/macos/Sources/ArchSightApp/QuickOpenPanel.swift` — `Cmd+P` 覆蓋式快速開檔面板。
- `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift` — `WorkspaceCommandActions`、`FocusedValues` key、`WorkspaceMenuCommands`。

**修改**
- `apps/macos/Sources/ArchSightApp/ArchSightApp.swift` — 加 `.commands { WorkspaceMenuCommands(...) }`。
- `apps/macos/Sources/ArchSightApp/ContentView.swift` — `focusedValue` 暴露指令、`Cmd+P` overlay、`selectTab`/`closeTabOrWindow` helper、精簡隱形按鈕只剩 `Cmd+W`。
- `apps/macos/Sources/ArchSightApp/CodeTextView.swift` — 啟用原生 find bar（`Cmd+F`）。

**測試**
- `apps/macos/Tests/ArchSightKitTests/FuzzyMatchTests.swift`

---

## 快捷鍵總表（驗收基準）

| 快捷鍵 | 動作 | 實作位置 |
|---|---|---|
| `Cmd+O` | 開啟資料夾 | Commands → `openFolder` |
| `Cmd+N` | 新視窗 | Plan A 已恢復（WindowGroup 預設）|
| `Cmd+B` | 切換側邊欄 | Commands → `toggleSidebar` |
| `Cmd+Shift+E` | 聚焦 Explorer | Commands → `focusExplorer` |
| `Cmd+Shift+F` | 聚焦 Search | Commands → `focusSearch` |
| `Cmd+\` | 切換分割 | Commands → `toggleSplit` |
| `Cmd+1`~`9` | 跳到第 N 分頁 | Commands → `selectTab` |
| `Cmd+=` / `Cmd+-` | 字級 A+ / A− | Commands → `readingStore` |
| `Cmd+[` / `Cmd+]` | 上一頁 / 下一頁 | Commands → `goBack`/`goForward` |
| `Cmd+Shift+[` / `]` | 切上/下分頁 | Commands → `previousTab`/`nextTab` |
| `Cmd+P` | 快速開檔 | `QuickOpenPanel` |
| `Cmd+F` | 檔內尋找 | `NSTextView` find bar |
| `Cmd+W` | 關分頁/關視窗 | 聚焦隱形按鈕 → `closeTabOrWindow` |

---

# Phase 1 — FuzzyMatch（Kit, TDD）

## Task 1: FuzzyMatch 比對與排序

**Files:**
- Create: `apps/macos/Sources/ArchSightKit/FuzzyMatch.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/FuzzyMatchTests.swift`

- [ ] **Step 1: Write the failing test**

`apps/macos/Tests/ArchSightKitTests/FuzzyMatchTests.swift`:
```swift
import XCTest
@testable import ArchSightKit

final class FuzzyMatchTests: XCTestCase {
    func testSubsequenceMatchIsCaseInsensitive() {
        XCTAssertTrue(FuzzyMatch.matches("main", in: "MAIN.go"))
        XCTAssertTrue(FuzzyMatch.matches("mg", in: "main.go"))
        XCTAssertFalse(FuzzyMatch.matches("xyz", in: "main.go"))
        XCTAssertFalse(FuzzyMatch.matches("og", in: "main.go")) // wrong order
    }

    func testEmptyQueryReturnsAllCandidatesInOriginalOrder() {
        let candidates = ["b.txt", "a.txt", "c.txt"]
        XCTAssertEqual(FuzzyMatch.rank("", candidates: candidates), candidates)
    }

    func testNonMatchesAreFilteredOut() {
        let ranked = FuzzyMatch.rank("zz", candidates: ["main.go", "buzz.txt"])
        XCTAssertEqual(ranked, ["buzz.txt"])
    }

    func testConsecutiveMatchOutranksScattered() {
        let a = FuzzyMatch.score("ab", in: "ab_c")!
        let b = FuzzyMatch.score("ab", in: "a_b_c")!
        XCTAssertGreaterThan(a, b)
    }

    func testFilenameMatchOutranksScatteredSegments() {
        let ranked = FuzzyMatch.rank("main", candidates: ["m/a/i/n.txt", "app/main.swift"])
        XCTAssertEqual(ranked.first, "app/main.swift")
    }

    func testTiesPreserveInputOrder() {
        // Identical scoring shape; input order must be preserved.
        let ranked = FuzzyMatch.rank("a", candidates: ["a1", "a2"])
        XCTAssertEqual(ranked, ["a1", "a2"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FuzzyMatchTests`
Expected: FAIL（`cannot find 'FuzzyMatch' in scope`）。

- [ ] **Step 3: Write minimal implementation**

`apps/macos/Sources/ArchSightKit/FuzzyMatch.swift`:
```swift
import Foundation

/// Lightweight fuzzy subsequence matcher for the Quick Open panel. Pure value
/// logic so it is unit-testable without any UI. Scoring favors matches that are
/// consecutive and that land at path-segment starts (filename hits).
public enum FuzzyMatch {
    private static let segmentBonus = 6
    private static let consecutiveBonus = 8

    /// True when every character of `query` appears in `candidate` in order
    /// (case-insensitive).
    public static func matches(_ query: String, in candidate: String) -> Bool {
        score(query, in: candidate) != nil
    }

    /// Greedy subsequence score; higher is better. Returns nil when `candidate`
    /// does not contain `query` as a subsequence. Empty query scores 0.
    public static func score(_ query: String, in candidate: String) -> Int? {
        if query.isEmpty {
            return 0
        }
        let needles = Array(query.lowercased())
        let haystack = Array(candidate.lowercased())
        var needleIndex = 0
        var total = 0
        var previousMatched = false

        for (index, character) in haystack.enumerated() {
            guard needleIndex < needles.count, character == needles[needleIndex] else {
                previousMatched = false
                continue
            }
            var points = 1
            let atSegmentStart = index == 0 || haystack[index - 1] == "/"
            if atSegmentStart {
                points += segmentBonus
            }
            if previousMatched {
                points += consecutiveBonus
            }
            total += points
            needleIndex += 1
            previousMatched = true
        }

        return needleIndex == needles.count ? total : nil
    }

    /// Filters out non-matches and ranks the rest best-first. An empty query
    /// returns the candidates unchanged. Ties preserve input order.
    public static func rank(_ query: String, candidates: [String]) -> [String] {
        if query.isEmpty {
            return candidates
        }
        return candidates
            .enumerated()
            .compactMap { offset, candidate -> (offset: Int, candidate: String, score: Int)? in
                guard let value = score(query, in: candidate) else {
                    return nil
                }
                return (offset, candidate, value)
            }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.offset < rhs.offset
            }
            .map(\.candidate)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FuzzyMatchTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/FuzzyMatch.swift apps/macos/Tests/ArchSightKitTests/FuzzyMatchTests.swift
git commit -m "feat: [macos] add FuzzyMatch subsequence matcher for quick open"
```

---

# Phase 2 — Cmd+P 快速開檔（App, build + 手動）

## Task 2: QuickOpenPanel 與 ContentView overlay

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/QuickOpenPanel.swift`
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

- [ ] **Step 1: 建立 QuickOpenPanel**

`apps/macos/Sources/ArchSightApp/QuickOpenPanel.swift`:
```swift
import ArchSightKit
import SwiftUI

/// VSCode-style Quick Open overlay. Self-contained: owns its query/selection,
/// ranks the workspace's file entries via `FuzzyMatch`, and reports the chosen
/// entry back through `onOpen`.
struct QuickOpenPanel: View {
    let entries: [WorkspaceEntry]
    let onOpen: (WorkspaceEntry) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var matches: [WorkspaceEntry] {
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return Array(
            FuzzyMatch.rank(query, candidates: entries.map(\.path))
                .compactMap { byPath[$0] }
                .prefix(50)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Go to File…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .focused($fieldFocused)
                .onChange(of: query) { _, _ in selection = 0 }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                            row(entry, isSelected: index == selection)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { onOpen(entry) }
                        }
                    }
                }
                .onChange(of: selection) { _, newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 24)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func row(_ entry: WorkspaceEntry, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            FileIconMapper.iconType(for: entry.name).view()
            Text(entry.name)
                .font(.system(size: 12, design: .monospaced))
            Text(entry.path)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
    }

    private func move(_ delta: Int) {
        let count = matches.count
        guard count > 0 else { return }
        selection = max(0, min(count - 1, selection + delta))
    }

    private func openSelected() {
        let list = matches
        guard selection < list.count else { return }
        onOpen(list[selection])
    }
}
```

- [ ] **Step 2: 在 ContentView 加狀態與 overlay**

在 `apps/macos/Sources/ArchSightApp/ContentView.swift`：

(a) 新增 `@State`（放在其他 `@State` 附近）：
```swift
    @State private var isQuickOpenPresented = false
```

(b) `body` 的最外層 `HStack { ... }` 之後（`.safeAreaInset(edge: .bottom) { statusBar }` 之後）加 `.overlay`：
```swift
        .overlay {
            if isQuickOpenPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { isQuickOpenPresented = false }
                    QuickOpenPanel(
                        entries: state.fileEntries,
                        onOpen: { entry in
                            isQuickOpenPresented = false
                            openEntry(entry)
                        },
                        onClose: { isQuickOpenPresented = false }
                    )
                    .padding(.top, 40)
                }
            }
        }
```

- [ ] **Step 3: Build 驗證**

Run: `swift build`
Expected: 編譯成功。

- [ ] **Step 4: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/QuickOpenPanel.swift apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] add Quick Open overlay panel"
```

> 註：`Cmd+P` 觸發（把 `isQuickOpenPresented = true` 接到快捷鍵）在 Task 3 的 Commands 中完成。

---

# Phase 3 — Commands + FocusedValue 路由（App, build + 手動）

## Task 3: WorkspaceCommands、App .commands、ContentView focusedValue

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift`
- Modify: `apps/macos/Sources/ArchSightApp/ArchSightApp.swift`
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

- [ ] **Step 1: 建立指令型別與選單**

`apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift`:
```swift
import ArchSightKit
import SwiftUI

/// Actions the currently focused window exposes to the app-wide command menu.
/// Defaults are no-ops so the menu items stay harmless when no window is focused.
struct WorkspaceCommandActions {
    var openFolder: () -> Void = {}
    var toggleSidebar: () -> Void = {}
    var focusExplorer: () -> Void = {}
    var focusSearch: () -> Void = {}
    var toggleSplit: () -> Void = {}
    var selectTab: (Int) -> Void = { _ in }
    var quickOpen: () -> Void = {}
    var goBack: () -> Void = {}
    var goForward: () -> Void = {}
    var nextTab: () -> Void = {}
    var previousTab: () -> Void = {}
}

struct WorkspaceCommandsKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

extension FocusedValues {
    var workspaceCommands: WorkspaceCommandActions? {
        get { self[WorkspaceCommandsKey.self] }
        set { self[WorkspaceCommandsKey.self] = newValue }
    }
}

/// App-wide menu + keyboard shortcuts. Window-scoped actions route to the key
/// window via `@FocusedValue`; the shared reading store is captured directly.
struct WorkspaceMenuCommands: Commands {
    let readingStore: ReadingPreferencesStore
    @FocusedValue(\.workspaceCommands) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") { actions?.openFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { actions?.toggleSidebar() }
                .keyboardShortcut("b", modifiers: .command)
            Button("Show Explorer") { actions?.focusExplorer() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Show Search") { actions?.focusSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Toggle Split Editor") { actions?.toggleSplit() }
                .keyboardShortcut("\\", modifiers: .command)
            Divider()
            Button("Increase Text Size") { readingStore.increaseFont() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Decrease Text Size") { readingStore.decreaseFont() }
                .keyboardShortcut("-", modifiers: .command)
        }

        CommandMenu("Go") {
            Button("Quick Open…") { actions?.quickOpen() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions == nil)
            Divider()
            Button("Back") { actions?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { actions?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Next Tab") { actions?.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { actions?.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button("Go to Tab \(number)") { actions?.selectTab(number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
        }
    }
}
```

- [ ] **Step 2: App 掛上 .commands**

在 `apps/macos/Sources/ArchSightApp/ArchSightApp.swift` 的 `WindowGroup { ... }` 之後（`Settings` 之前）加：
```swift
        .commands {
            WorkspaceMenuCommands(readingStore: readingPreferences)
        }
```
> 不替換 `.newItem`，故 Plan A 恢復的 New Window（`Cmd+N`）持續有效；`Open Folder…` 以 `after: .newItem` 緊接其後。

- [ ] **Step 3: ContentView 暴露 focusedValue 並加 helper**

在 `apps/macos/Sources/ArchSightApp/ContentView.swift`：

(a) 確保頂部有 `import AppKit`（供 `NSApp`）。在檔案開頭 import 區補：
```swift
import AppKit
```

(b) 在 `body` 最外層 `HStack { ... }` 鏈上（建議放在 `.overlay { ... }` 之後）加：
```swift
        .focusedValue(\.workspaceCommands, WorkspaceCommandActions(
            openFolder: { openFolderPicker() },
            toggleSidebar: {
                withAnimation(.easeInOut(duration: 0.16)) { isSidebarVisible.toggle() }
            },
            focusExplorer: {
                activeSidebarTab = .explorer
                withAnimation(.easeInOut(duration: 0.16)) { isSidebarVisible = true }
            },
            focusSearch: {
                activeSidebarTab = .search
                withAnimation(.easeInOut(duration: 0.16)) { isSidebarVisible = true }
            },
            toggleSplit: { isSplit.toggle() },
            selectTab: { number in selectTab(at: number) },
            quickOpen: { isQuickOpenPresented = true },
            goBack: { goBack() },
            goForward: { goForward() },
            nextTab: { selectAndRecord { state.selectNextTab() } },
            previousTab: { selectAndRecord { state.selectPreviousTab() } }
        ))
```

(c) 在「Keyboard navigation helpers」區（`closeSelectedTab` 附近）新增：
```swift
    private func selectTab(at oneBasedIndex: Int) {
        let index = oneBasedIndex - 1
        guard index >= 0, index < state.openTabs.count else { return }
        selectAndRecord { state.selectedTabID = state.openTabs[index].id }
    }

    private func closeTabOrWindow() {
        if state.selectedTabID != nil {
            closeSelectedTab()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
```

- [ ] **Step 4: 精簡隱形按鈕——只保留 Cmd+W**

把 `ContentView` 既有的 `keyboardShortcuts`（含 back/forward/closeTab/next/prev 五個隱形按鈕）整段替換為僅 `Cmd+W`：
```swift
    /// Cmd+W stays a focused hidden button: overriding the system Close item via
    /// `Commands` is unreliable, but a focused shortcut reliably intercepts it.
    private var keyboardShortcuts: some View {
        Button("") { closeTabOrWindow() }
            .keyboardShortcut("w", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
    }
```
> `.background { keyboardShortcuts }` 維持不變。back/forward/next/prev 改由 Task 3 的「Go」選單提供，避免雙重綁定。

- [ ] **Step 5: Build 驗證**

Run: `swift build`
Expected: 編譯成功。

- [ ] **Step 6: 全測試確認無回歸**

Run: `swift test`
Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift apps/macos/Sources/ArchSightApp/ArchSightApp.swift apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] route VSCode-style shortcuts via Commands and FocusedValue"
```

---

# Phase 4 — Cmd+F 檔內尋找（App, build + 手動）

## Task 4: CodeTextView 啟用原生 find bar

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/CodeTextView.swift`

- [ ] **Step 1: makeNSView 啟用 find bar**

在 `apps/macos/Sources/ArchSightApp/CodeTextView.swift` 的 `makeNSView(context:)` 內，於 `textView.coordinator = context.coordinator` 之前加：
```swift
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
```
> `NSTextView` 為 selectable（即使 read-only）即可成為 first responder，系統 Edit ▸ Find ▸ Find…（`Cmd+F`）會經 responder chain 觸發 `performTextFinderAction(_:)`，因 `usesFindBar = true` 而顯示原生尋找列，支援下一個/上一個。Edit 選單為 SwiftUI 預設提供、未被替換。

- [ ] **Step 2: Build 驗證**

Run: `swift build`
Expected: 編譯成功。

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/CodeTextView.swift
git commit -m "feat: [macos] enable native find bar in the code view"
```

---

# Phase 5 — 全快捷鍵手動驗證

## Task 5: 逐項驗證

**Files:** 無（驗證）

- [ ] **Step 1: 啟動**

Run: `swift run ArchSight`，開一個資料夾、開數個檔成分頁。

- [ ] **Step 2: 逐項過快捷鍵**

1. `Cmd+O` 開資料夾；`Cmd+N` 開新視窗。
2. `Cmd+B` 切側邊欄；`Cmd+Shift+E` / `Cmd+Shift+F` 切 Explorer/Search 分頁並顯示側邊欄。
3. `Cmd+\` 切分割檢視。
4. `Cmd+1`~`Cmd+9` 跳到對應分頁（超出數量則無動作）。
5. `Cmd+=` / `Cmd+-` 字級放大/縮小（Markdown 預覽與程式碼檢視同步、邊界 disable）。
6. `Cmd+[` / `Cmd+]` 上一頁/下一頁；`Cmd+Shift+[` / `Cmd+Shift+]` 切上/下分頁。
7. `Cmd+P` 開快速開檔：輸入過濾、↑/↓ 移動選取、Enter 開檔、Esc 關閉、點背景關閉。
8. `Cmd+F` 在程式碼檢視內叫出原生尋找列，下一個/上一個可用。
9. `Cmd+W`：有分頁→關當前分頁；關到沒有分頁後再 `Cmd+W`→關閉視窗。
10. 多視窗下，快捷鍵都作用在當前作用中（key）視窗。

- [ ] **Step 3: 收尾**

Run: `swift test` 與 `swift build` 各一次確認綠燈。Plan B 完成。

---

## Self-review 對照

- 規格第 3 部分（綁現有功能基本盤）→ Task 3（Commands + focusedValue）。
- 規格第 3 部分（`Cmd+P` 快速開檔 + `FuzzyMatch`）→ Task 1（演算法）、Task 2（UI）、Task 3（`Cmd+P` 觸發）。
- 規格第 3 部分（`Cmd+F` find bar）→ Task 4。
- 規格第 3 部分（`Cmd+W` 語意）→ Task 3 Step 3–4（`closeTabOrWindow` + 聚焦隱形按鈕）。
- 規格第 4 部分（測試與驗證）→ Task 1 TDD + Task 5 手動驗證。
- 型別一致性：`WorkspaceCommandActions` 的方法名（`openFolder`/`toggleSidebar`/`focusExplorer`/`focusSearch`/`toggleSplit`/`selectTab`/`quickOpen`/`goBack`/`goForward`/`nextTab`/`previousTab`）在 `WorkspaceMenuCommands` 與 `ContentView.focusedValue` 兩處一致；`isQuickOpenPresented` 於 Task 2 定義、Task 3 使用。
```
