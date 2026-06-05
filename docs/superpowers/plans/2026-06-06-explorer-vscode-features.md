# Explorer VSCode-Borrowed Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Borrow four VSCode Explorer behaviours into the ArchSight sidebar — collapsible root folders, one-click "Collapse Folders" (⌥⌘0 + header button), Reveal in Finder, and Copy Path / Copy Relative Path — while staying read-only.

**Architecture:** Pure path logic lives in `ArchSightKit` (unit-tested); AppKit side-effects (Finder reveal, pasteboard) live in a small `ArchSightApp` helper. `ContentView` gains a `collapsedRoots` state set so each root renders as a collapsible `Section(_:isExpanded:)`, a "FOLDERS" header row hosting the collapse button, and context menus reusing the helpers. The collapse shortcut routes through the existing `WorkspaceCommandActions` / `WorkspaceMenuCommands` / `ShortcutCatalog` pattern.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest (Swift Package at `apps/macos`). Target macOS 14.

**Spec:** `docs/superpowers/specs/2026-06-06-explorer-vscode-features-design.md`

**Conventions:**
- Run all build/test commands from `apps/macos`.
- `WorkspaceTreeNode` already exposes `rootPath` and `path`, so no recursion signature change is needed.
- Only `ArchSightKitTests` exists; the `ArchSightApp` executable target has no test target, so pure logic that needs tests goes in `ArchSightKit`.

---

## Task 1: Relative-path pure function (ArchSightKit)

**Files:**
- Create: `apps/macos/Sources/ArchSightKit/FileSystemPaths.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/FileSystemPathsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `apps/macos/Tests/ArchSightKitTests/FileSystemPathsTests.swift`:

```swift
import XCTest
@testable import ArchSightKit

final class FileSystemPathsTests: XCTestCase {
    func testRelativeReturnsChildName() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b/c.txt", under: "/a/b"), "c.txt")
    }

    func testRelativeReturnsNestedPath() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b/sub/c.txt", under: "/a/b"), "sub/c.txt")
    }

    func testRelativeToleratesTrailingSlashRoot() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b/c.txt", under: "/a/b/"), "c.txt")
    }

    func testRelativeOfRootItselfIsEmpty() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b", under: "/a/b"), "")
    }

    func testRelativeFallsBackToOriginalWhenNotUnderRoot() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/x/y", under: "/a/b"), "/x/y")
    }

    func testRelativeDoesNotMatchSiblingPrefix() {
        // "/a/bc" must not be treated as living under "/a/b".
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/bc/d.txt", under: "/a/b"), "/a/bc/d.txt")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos && swift test --filter FileSystemPathsTests`
Expected: FAIL — `cannot find 'FileSystemPaths' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `apps/macos/Sources/ArchSightKit/FileSystemPaths.swift`:

```swift
import Foundation

/// Pure path helpers for the workspace sidebar. Side-effect-free so they can be
/// unit-tested; AppKit actions (Finder reveal, pasteboard) live in the App target.
public enum FileSystemPaths {
    /// Path of `path` relative to `rootPath`. Returns "" when they are equal and
    /// falls back to the original `path` when `path` is not under `rootPath`.
    public static func relative(of path: String, under rootPath: String) -> String {
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        if path == normalizedRoot { return "" }
        let prefix = normalizedRoot + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos && swift test --filter FileSystemPathsTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/FileSystemPaths.swift apps/macos/Tests/ArchSightKitTests/FileSystemPathsTests.swift
git commit -m "feat: [macos] add FileSystemPaths.relative for sidebar path helpers"
```

---

## Task 2: Register the Collapse Folders shortcut hint (ArchSightKit)

**Files:**
- Modify: `apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift`
- Test: `apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift`

- [ ] **Step 1: Write the failing test**

Append this method inside `final class ShortcutCatalogTests` in `apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift`:

```swift
    func testCollapseFoldersHintIsRegistered() {
        let hint = ShortcutCatalog.hint("collapseFolders")
        XCTAssertEqual(hint?.category, .view)
        XCTAssertEqual(hint?.label, "Collapse Folders")
        XCTAssertEqual(hint?.chord.display, "⌥⌘0")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos && swift test --filter ShortcutCatalogTests/testCollapseFoldersHintIsRegistered`
Expected: FAIL — `hint` is nil, so the first `XCTAssertEqual` fails.

- [ ] **Step 3: Write minimal implementation**

In `apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift`, add a new entry in the `// View` block of `ShortcutCatalog.all`, immediately after the `splitEditor` hint:

```swift
        ShortcutHint(id: "collapseFolders", category: .view, label: "Collapse Folders", chord: KeyChord(key: "0", command: true, option: true)),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/macos && swift test --filter ShortcutCatalogTests`
Expected: PASS — including `testCatalogChordsAreUnique` (⌥⌘0 is a new unique chord) and `testCatalogIdsAreUnique`.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/ShortcutCatalog.swift apps/macos/Tests/ArchSightKitTests/ShortcutCatalogTests.swift
git commit -m "feat: [macos] add Collapse Folders shortcut hint (⌥⌘0)"
```

---

## Task 3: AppKit file-system actions helper (ArchSightApp)

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/FileSystemActions.swift`

No unit test: `NSWorkspace` / `NSPasteboard` side-effects are not exercised in the headless test target. Verified via build + manual run.

- [ ] **Step 1: Write the helper**

Create `apps/macos/Sources/ArchSightApp/FileSystemActions.swift`:

```swift
import AppKit

/// Best-effort, low-friction AppKit actions for the sidebar context menus.
/// Invalid paths simply do nothing — consistent with the read-only product feel.
enum FileSystemActions {
    static func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd apps/macos && swift build`
Expected: Build succeeds (the new file is unused so far — acceptable; it is wired up in Task 6).

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/FileSystemActions.swift
git commit -m "feat: [macos] add FileSystemActions for reveal-in-Finder and copy"
```

---

## Task 4: Collapsible root folder sections (ContentView)

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

This makes each dragged-in root collapsible via `Section(_:isExpanded:)` (the bug fix). Verified by build + manual toggle.

- [ ] **Step 1: Add the collapsed-roots state**

In `ContentView`, immediately after the `expandedPaths` declaration (`apps/macos/Sources/ArchSightApp/ContentView.swift:8`):

```swift
    @State private var expandedPaths: Set<String> = []
    /// Root ids the user has collapsed. Empty = all roots expanded, so newly
    /// dragged-in folders default to expanded without seeding state.
    @State private var collapsedRoots: Set<WorkspaceRoot.ID> = []
```

- [ ] **Step 2: Render roots as collapsible sections**

In `sidebarPanel`, replace the root loop. Change this (around `ContentView.swift:233-251`):

```swift
                    ForEach(state.roots) { root in
                        Section(root.name) {
```

to:

```swift
                    ForEach(state.roots) { root in
                        let rootExpanded = Binding<Bool>(
                            get: { !collapsedRoots.contains(root.id) },
                            set: { expanded in
                                if expanded {
                                    collapsedRoots.remove(root.id)
                                } else {
                                    collapsedRoots.insert(root.id)
                                }
                            }
                        )
                        Section(root.name, isExpanded: rootExpanded) {
```

(Leave the section body, `.contextMenu`, and closing braces unchanged.)

- [ ] **Step 3: Clean up collapsed state on root removal / close**

In `removeRoot(_:)` (`ContentView.swift:765`), after the `expandedPaths` filter assignment and before `state.removeRoot(id: root.id)`:

```swift
        collapsedRoots.remove(root.id)
        state.removeRoot(id: root.id)
```

In `closeWorkspace()` (`ContentView.swift:785-787`), add the reset:

```swift
    private func closeWorkspace() {
        expandedPaths = []
        collapsedRoots = []
        state.closeWorkspace()
        refreshSidebarTreeNodes()
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cd apps/macos && swift build`
Expected: Build succeeds.

- [ ] **Step 5: Manual smoke check**

Run: `cd apps/macos && swift run ArchSight`
Drag in two folders. Confirm each root header now shows a disclosure triangle and collapses/expands independently when clicked. Quit the app.

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "fix: [macos] make sidebar root folders collapsible"
```

---

## Task 5: Collapse-all action, FOLDERS header button, and shortcut wiring

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`
- Modify: `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift`

Depends on Task 2 (catalog hint) and Task 4 (`collapsedRoots`).

- [ ] **Step 1: Add the `collapseAll` action to the command struct**

In `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift`, add a field to `WorkspaceCommandActions` (after `toggleSplit`):

```swift
    var toggleSplit: () -> Void = {}
    var collapseAll: () -> Void = {}
```

- [ ] **Step 2: Add the menu item + keyboard shortcut**

In `WorkspaceMenuCommands.body`, inside the `CommandGroup(after: .sidebar)` block, add after the `Toggle Split Editor` button (before the `Divider()` that precedes text-size items):

```swift
            Button("Toggle Split Editor") { actions?.toggleSplit() }
                .keyboardShortcut("\\", modifiers: .command)
            Button("Collapse Folders") { actions?.collapseAll() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(actions == nil)
            Divider()
```

- [ ] **Step 3: Add the `collapseAll()` method to ContentView**

In `ContentView`, next to `closeWorkspace()` (`apps/macos/Sources/ArchSightApp/ContentView.swift`):

```swift
    private func collapseAll() {
        // Match VSCode "Collapse Folders in Explorer": collapse nested folders
        // and the root sections together.
        expandedPaths = []
        collapsedRoots = Set(state.roots.map(\.id))
    }
```

- [ ] **Step 4: Wire the action into the focused-value command set**

In the `.focusedValue(\.workspaceCommands, WorkspaceCommandActions(...))` initializer (`ContentView.swift:84-112`), add the parameter after `toggleSplit:`:

```swift
            toggleSplit: { isSplit.toggle() },
            collapseAll: { collapseAll() },
```

- [ ] **Step 5: Add the FOLDERS header row with the collapse button**

In `ContentView`, add this computed view (near `openFilesPanel`):

```swift
    private var foldersHeader: some View {
        HStack(spacing: 6) {
            Text("FOLDERS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: collapseAll) {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse Folders \(ShortcutCatalog.hint("collapseFolders")?.chord.display ?? "")")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
```

Then show it in the `.explorer` case of `sidebarPanel`, immediately before the `List(selection: $sidebarSelection)` and after the `openFilesPanel` block:

```swift
                if !state.openTabs.isEmpty {
                    openFilesPanel
                }

                if !state.roots.isEmpty {
                    foldersHeader
                }

                List(selection: $sidebarSelection) {
```

- [ ] **Step 6: Build to verify it compiles**

Run: `cd apps/macos && swift build`
Expected: Build succeeds.

- [ ] **Step 7: Manual smoke check**

Run: `cd apps/macos && swift run ArchSight`
Drag in a folder, expand a few subfolders. Click the collapse icon in the FOLDERS row — all subfolders and root sections collapse. Re-expand, then press ⌥⌘0 — same result. Quit.

- [ ] **Step 8: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/ContentView.swift apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift
git commit -m "feat: [macos] add Collapse Folders button and ⌥⌘0 shortcut"
```

---

## Task 6: Reveal in Finder / Copy Path context menus

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

Depends on Task 1 (`FileSystemPaths`) and Task 3 (`FileSystemActions`).

- [ ] **Step 1: Add a reusable context-menu builder**

In `ContentView`, add this helper (near `sidebarNode`):

```swift
    @ViewBuilder
    private func entryContextMenu(path: String, rootPath: String) -> some View {
        Button("Reveal in Finder") { FileSystemActions.revealInFinder(path: path) }
        Divider()
        Button("Copy Path") { FileSystemActions.copyToPasteboard(path) }
        Button("Copy Relative Path") {
            FileSystemActions.copyToPasteboard(FileSystemPaths.relative(of: path, under: rootPath))
        }
    }
```

- [ ] **Step 2: Attach the menu to the directory disclosure label**

In `sidebarNode(_:)`, on the directory branch, add `.contextMenu` to the `DisclosureGroup`'s `label` `HStack` (the one containing the folder icon + `Text(node.name)` ending with `.help(node.path)`):

```swift
                .help(node.path)
                .contextMenu { entryContextMenu(path: node.path, rootPath: node.rootPath) }
            })
```

- [ ] **Step 3: Attach the menu to the file row**

In `sidebarNode(_:)`, on the file branch `HStack` (ends with `.contentShape(Rectangle())`), add:

```swift
                .help(node.path)
                .tag(node.entry.id)
                .contentShape(Rectangle())
                .contextMenu { entryContextMenu(path: node.path, rootPath: node.rootPath) }
            )
```

- [ ] **Step 4: Add Reveal / Copy Path to the root section menu**

In `sidebarPanel`, extend the root `Section`'s existing `.contextMenu` (`ContentView.swift:246-250`) — a root's relative path is empty, so it gets Reveal + Copy Path only:

```swift
                        .contextMenu {
                            Button("Reveal in Finder") { FileSystemActions.revealInFinder(path: root.path) }
                            Button("Copy Path") { FileSystemActions.copyToPasteboard(root.path) }
                            Divider()
                            Button("Remove Folder from Workspace") { removeRoot(root) }
                            Divider()
                            Button("Close All Folders") { closeWorkspace() }
                        }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `cd apps/macos && swift build`
Expected: Build succeeds.

- [ ] **Step 6: Manual smoke check**

Run: `cd apps/macos && swift run ArchSight`
Drag in a folder. Right-click a file → "Reveal in Finder" opens Finder with it selected; "Copy Path" then ⌘V in a terminal pastes the absolute path; "Copy Relative Path" pastes the path relative to its root. Right-click a folder and the root header — same actions present. Quit.

- [ ] **Step 7: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] add Reveal in Finder and Copy Path sidebar menus"
```

---

## Final verification

- [ ] **Full test + build**

Run: `cd apps/macos && swift test && swift build`
Expected: All tests pass (including `FileSystemPathsTests` and `ShortcutCatalogTests`), build succeeds.

- [ ] **Confirm the cheat sheet shows the new shortcut**

Run: `cd apps/macos && swift run ArchSight`, press ⌘/ to open the Keyboard Shortcuts cheat sheet, confirm "Collapse Folders ⌥⌘0" appears under the View category. Quit.

---

## Spec coverage check

- Collapsible root folders → Task 4.
- One-click Collapse All (collapses subfolders + roots) → Task 5 (`collapseAll()`).
- FOLDERS header button → Task 5 (Step 5).
- ⌥⌘0 shortcut + menu + catalog/cheat-sheet/tooltip consistency → Task 2 + Task 5.
- Reveal in Finder → Task 6.
- Copy Path / Copy Relative Path → Task 6 (+ Task 1 pure helper).
- Code organization (pure logic in Kit, AppKit side-effects in App helper) → Task 1 + Task 3.
- Tests for `relativePath` + catalog entry → Task 1 + Task 2.
