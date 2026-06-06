# Recent Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist recently opened workspace folders and let users quickly reopen them from a File ▸ Open Recent submenu and a welcome screen.

**Architecture:** A testable `RecentFoldersStore` (`@MainActor @Observable`, `UserDefaults`-backed, mirroring `ReadingPreferencesStore`) holds an MRU list of `RecentFolder` values in ArchSightKit. The App layer records each opened root, surfaces the list in the File menu and a new `WelcomeView` shown when no workspace is open, and reopens a folder through the existing `appendRoots` → `reopenWorkspace` path.

**Tech Stack:** Swift 6 / SwiftUI / SwiftPM, `Observation` framework, `UserDefaults` + `JSONEncoder`, XCTest.

---

## File Structure

- **Create** `apps/macos/Sources/ArchSightKit/RecentFolder.swift` — immutable Codable value type (one entry).
- **Create** `apps/macos/Sources/ArchSightKit/RecentFoldersStore.swift` — observable, persistent MRU store + missing-path filtering.
- **Create** `apps/macos/Tests/ArchSightKitTests/RecentFoldersStoreTests.swift` — unit tests for the store.
- **Create** `apps/macos/Sources/ArchSightApp/WelcomeView.swift` — empty-state welcome screen with recent list.
- **Modify** `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift` — add `openRecent` action + "Open Recent" submenu, pass `recentStore`.
- **Modify** `apps/macos/Sources/ArchSightApp/ArchSightApp.swift` — own + inject `RecentFoldersStore`.
- **Modify** `apps/macos/Sources/ArchSightApp/ContentView.swift` — record on open, wire `openRecent`, show `WelcomeView` when no roots.

Notes for the engineer:
- ArchSightKit is the unit-tested layer; SwiftUI views are **not** unit-tested in this project — they get a build check + manual verification instead.
- All builds run from the repo root with `--package-path apps/macos`. The Go core is irrelevant to these Swift-only changes.
- Commit after each task. Commit message format: `<type>: [macos] <subject>`.

---

## Task 1: `RecentFolder` value type

**Files:**
- Create: `apps/macos/Sources/ArchSightKit/RecentFolder.swift`

- [ ] **Step 1: Create the value type**

```swift
import Foundation

/// One persisted "recently opened folder" entry. Immutable; `id` is the path so
/// the same folder de-duplicates regardless of when it was last opened.
public struct RecentFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let lastOpened: Date

    public init(path: String, name: String, lastOpened: Date) {
        self.path = path
        self.name = name
        self.lastOpened = lastOpened
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build --package-path apps/macos --target ArchSightKit`
Expected: Build succeeds (the new file compiles; no other code references it yet).

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/RecentFolder.swift
git commit -m "feat: [macos] add RecentFolder value type"
```

---

## Task 2: `RecentFoldersStore` (TDD)

**Files:**
- Create: `apps/macos/Tests/ArchSightKitTests/RecentFoldersStoreTests.swift`
- Create: `apps/macos/Sources/ArchSightKit/RecentFoldersStore.swift`

Design constraints encoded by the tests:
- MRU order (most recent first), de-dupe by `path`.
- Stored cap = 15 (oldest trimmed).
- `existingEntries()` filters out paths that are not currently directories, **without** mutating stored `entries`.
- Persistence round-trips through `UserDefaults`.
- Corrupt JSON falls back to empty list.

- [ ] **Step 1: Write the failing tests**

Create `apps/macos/Tests/ArchSightKitTests/RecentFoldersStoreTests.swift`:

```swift
import XCTest
@testable import ArchSightKit

@MainActor
final class RecentFoldersStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.recent.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshStoreIsEmpty() {
        let store = RecentFoldersStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRecordAddsEntryWithDerivedName() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/Users/x/Dev/ArchSight")
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.path, "/Users/x/Dev/ArchSight")
        XCTAssertEqual(store.entries.first?.name, "ArchSight")
    }

    func testRecordSamePathDeduplicatesAndMovesToFront() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")
        store.record(path: "/a/one")
        XCTAssertEqual(store.entries.map(\.path), ["/a/one", "/a/two"])
    }

    func testRecordOrdersMostRecentFirst() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")
        store.record(path: "/a/three")
        XCTAssertEqual(store.entries.map(\.path), ["/a/three", "/a/two", "/a/one"])
    }

    func testRecordEnforcesStoredCapOfFifteen() {
        let store = RecentFoldersStore(defaults: defaults)
        for i in 0..<20 { store.record(path: "/a/\(i)") }
        XCTAssertEqual(store.entries.count, 15)
        // Newest first, oldest five trimmed.
        XCTAssertEqual(store.entries.first?.path, "/a/19")
        XCTAssertEqual(store.entries.last?.path, "/a/5")
    }

    func testRemoveDropsSingleEntry() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")
        store.remove(path: "/a/one")
        XCTAssertEqual(store.entries.map(\.path), ["/a/two"])
    }

    func testClearEmptiesEntries() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testEntriesPersistAcrossStores() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")

        let reloaded = RecentFoldersStore(defaults: defaults)
        XCTAssertEqual(reloaded.entries.map(\.path), ["/a/two", "/a/one"])
    }

    func testCorruptStorageFallsBackToEmpty() {
        defaults.set(Data("not json".utf8), forKey: "recentFolders.v1")
        let store = RecentFoldersStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testExistingEntriesFiltersMissingPathsWithoutMutatingStorage() throws {
        let tempDir = NSTemporaryDirectory() + "recent-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/definitely/missing/path")
        store.record(path: tempDir)

        XCTAssertEqual(store.existingEntries().map(\.path), [tempDir])
        // Stored entries are untouched so a remounted volume reappears.
        XCTAssertEqual(store.entries.count, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path apps/macos --filter RecentFoldersStoreTests`
Expected: FAIL — compile error, `cannot find 'RecentFoldersStore' in scope`.

- [ ] **Step 3: Implement the store**

Create `apps/macos/Sources/ArchSightKit/RecentFoldersStore.swift`:

```swift
import Foundation
import Observation

/// Observable, persistent most-recently-used list of opened folders. Mirrors
/// `ReadingPreferencesStore`'s `UserDefaults` + JSON persistence. `@MainActor`
/// because it is only ever read/written from SwiftUI views and menu actions.
@MainActor
@Observable
public final class RecentFoldersStore {
    public private(set) var entries: [RecentFolder]

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "recentFolders.v1"
    private static let storedCap = 15

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    /// Inserts (or refreshes) `path` at the front, de-duplicating by path and
    /// trimming the oldest entries beyond the stored cap.
    public func record(path: String) {
        let entry = RecentFolder(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            lastOpened: Date()
        )
        let withoutDuplicate = entries.filter { $0.path != path }
        entries = Array(([entry] + withoutDuplicate).prefix(Self.storedCap))
        persist()
    }

    public func remove(path: String) {
        entries = entries.filter { $0.path != path }
        persist()
    }

    public func clear() {
        entries = []
        persist()
    }

    /// Entries whose path is currently an existing directory. Used by the UI so
    /// stale paths hide without being deleted (e.g. a temporarily unmounted volume).
    public func existingEntries() -> [RecentFolder] {
        let fileManager = FileManager.default
        return entries.filter { entry in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [RecentFolder] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentFolder].self, from: data)
        else {
            return []
        }
        return Array(decoded.prefix(storedCap))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path apps/macos --filter RecentFoldersStoreTests`
Expected: PASS — all 10 tests green.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Sources/ArchSightKit/RecentFoldersStore.swift apps/macos/Tests/ArchSightKitTests/RecentFoldersStoreTests.swift
git commit -m "feat: [macos] add RecentFoldersStore with MRU persistence"
```

---

## Task 3: Inject the store at app scope

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ArchSightApp.swift`

- [ ] **Step 1: Own and inject `RecentFoldersStore`**

Edit `apps/macos/Sources/ArchSightApp/ArchSightApp.swift` to add the state, environment injection, and command wiring. The full file should read:

```swift
import ArchSightKit
import SwiftUI

@main
struct ArchSightApp: App {
    @State private var readingPreferences = ReadingPreferencesStore()
    @State private var recentFolders = RecentFoldersStore()
    @State private var appCore = AppCore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(readingPreferences)
                .environment(recentFolders)
                .environment(appCore)
                .task { appCore.connectIfNeeded() }
        }
        .commands {
            WorkspaceMenuCommands(readingStore: readingPreferences, recentStore: recentFolders)
        }

        Settings {
            ReadingSettingsView()
                .environment(readingPreferences)
        }
    }
}
```

- [ ] **Step 2: Build to verify the new parameter is expected next**

Run: `swift build --package-path apps/macos --product ArchSight`
Expected: FAIL — `WorkspaceMenuCommands` has no `recentStore:` parameter yet (added in Task 4) and `ContentView` has no `RecentFoldersStore` environment requirement yet. This failure is expected; it is fixed by Tasks 4 and 6.

Do **not** commit yet — Tasks 3, 4, and 6 land together as one compiling change. Proceed to Task 4.

---

## Task 4: "Open Recent" submenu + action

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift`

- [ ] **Step 1: Add the `openRecent` action field**

In `WorkspaceCommandActions`, add a new field next to the other actions (after `openFolder`):

```swift
struct WorkspaceCommandActions {
    var openFolder: () -> Void = {}
    var openRecent: (String) -> Void = { _ in }
    var toggleSidebar: () -> Void = {}
    var focusExplorer: () -> Void = {}
    var focusSearch: () -> Void = {}
    var toggleSplit: () -> Void = {}
    var collapseAll: () -> Void = {}
    var selectTab: (Int) -> Void = { _ in }
    var quickOpen: () -> Void = {}
    var goBack: () -> Void = {}
    var goForward: () -> Void = {}
    var nextTab: () -> Void = {}
    var previousTab: () -> Void = {}
    var showShortcuts: () -> Void = {}
}
```

- [ ] **Step 2: Accept `recentStore` and render the submenu**

Change `WorkspaceMenuCommands` to take the store and add the submenu after "Open Folder…". Replace the struct's stored properties and the `CommandGroup(after: .newItem)` block:

```swift
struct WorkspaceMenuCommands: Commands {
    let readingStore: ReadingPreferencesStore
    let recentStore: RecentFoldersStore
    @FocusedValue(\.workspaceCommands) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") { actions?.openFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)

            let recents = Array(recentStore.existingEntries().prefix(10))
            Menu("Open Recent") {
                ForEach(recents) { folder in
                    Button(folder.name) { actions?.openRecent(folder.path) }
                        .help(folder.path)
                }
                Divider()
                Button("Clear Menu") { recentStore.clear() }
            }
            .disabled(actions == nil || recents.isEmpty)
        }

        // ...rest of body unchanged (CommandGroup(after: .sidebar), CommandMenu("Go"), CommandGroup(after: .help))
    }
}
```

Leave every other `CommandGroup` / `CommandMenu` in the body exactly as-is.

- [ ] **Step 3: Do not build standalone**

`ContentView` still does not provide `openRecent` or read the store; that lands in Task 6. Proceed to Task 5 then Task 6, then build once.

---

## Task 5: `WelcomeView`

**Files:**
- Create: `apps/macos/Sources/ArchSightApp/WelcomeView.swift`

- [ ] **Step 1: Create the welcome screen**

Create `apps/macos/Sources/ArchSightApp/WelcomeView.swift`:

```swift
import ArchSightKit
import SwiftUI

/// Empty-state shown in the editor pane when no workspace folder is open.
/// Offers an Open Folder action plus a clickable list of recently opened folders.
struct WelcomeView: View {
    let recents: [RecentFolder]
    let onOpenFolder: () -> Void
    let onOpenRecent: (String) -> Void
    let onRemoveRecent: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ArchSightIcon.FolderOpen(color: .accentColor)
                    .frame(width: 56, height: 56)
                Text("ArchSight")
                    .font(.title2.weight(.semibold))
                Button("Open Folder…", action: onOpenFolder)
                    .controlSize(.large)
            }

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    ForEach(recents) { folder in
                        RecentRow(
                            folder: folder,
                            onOpen: { onOpenRecent(folder.path) },
                            onRemove: { onRemoveRecent(folder.path) }
                        )
                    }
                }
                .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// One recent-folder row: name + abbreviated path, with a hover-revealed remove button.
private struct RecentRow: View {
    let folder: RecentFolder
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    private var abbreviatedPath: String {
        (folder.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 8) {
            ArchSightIcon.Folder(color: .accentColor)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                Text(abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from Recent")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.secondary.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 2: Proceed to Task 6**

This view is not referenced yet; it is wired into `ContentView` in Task 6. Build happens at the end of Task 6.

---

## Task 6: Wire recording, `openRecent`, and the welcome screen into `ContentView`

**Files:**
- Modify: `apps/macos/Sources/ArchSightApp/ContentView.swift`

- [ ] **Step 1: Add the store to the environment reads**

Near the other `@Environment` lines (`apps/macos/Sources/ArchSightApp/ContentView.swift:33-34`), add:

```swift
    @Environment(ReadingPreferencesStore.self) private var readingStore
    @Environment(AppCore.self) private var appCore
    @Environment(RecentFoldersStore.self) private var recentStore
```

- [ ] **Step 2: Provide the `openRecent` focused action**

In the `.focusedValue(\.workspaceCommands, WorkspaceCommandActions(...))` builder, add `openRecent` right after `openFolder` (around `ContentView.swift:89`):

```swift
            openFolder: { openFolderPicker() },
            openRecent: { path in appendRoots([URL(fileURLWithPath: path)]) },
```

- [ ] **Step 3: Record opened roots in `reopenWorkspace`**

In `reopenWorkspace` (`ContentView.swift:454`), after `state.roots = result.roots` in the success branch, record each root path:

```swift
                state.workspaceId = result.workspaceId
                state.roots = result.roots
                result.roots.forEach { recentStore.record(path: $0.path) }
                state.entries = result.entries
                refreshSidebarTreeNodes()
                state.isLoading = false
```

- [ ] **Step 4: Record opened roots in `addRoots`**

In `addRoots` (`ContentView.swift:477`), after `state.roots = result.roots` in the success branch, record each root path:

```swift
                state.roots = result.roots
                result.roots.forEach { recentStore.record(path: $0.path) }
                state.entries = result.entries
                refreshSidebarTreeNodes()
                state.isLoading = false
```

- [ ] **Step 5: Show `WelcomeView` when no workspace is open**

Replace `primaryPane` (`ContentView.swift:259-267`) so an empty workspace shows the welcome screen:

```swift
    @ViewBuilder
    private var primaryPane: some View {
        if state.roots.isEmpty {
            WelcomeView(
                recents: Array(recentStore.existingEntries().prefix(10)),
                onOpenFolder: { openFolderPicker() },
                onOpenRecent: { path in appendRoots([URL(fileURLWithPath: path)]) },
                onRemoveRecent: { path in recentStore.remove(path: path) }
            )
        } else if let tab = selectedTab {
            filePane(for: tab, scrollLine: pendingScrollLine)
        } else {
            ContentUnavailableView("Read Only", systemImage: "eye")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
```

- [ ] **Step 6: Build the whole app (Tasks 3–6 together)**

Run: `swift build --package-path apps/macos --product ArchSight`
Expected: PASS — the app compiles with the store injected, submenu rendered, welcome screen wired.

- [ ] **Step 7: Run the full test suite**

Run: `swift test --package-path apps/macos`
Expected: PASS — existing tests plus `RecentFoldersStoreTests` all green.

- [ ] **Step 8: Commit**

```bash
git add apps/macos/Sources/ArchSightApp/ArchSightApp.swift \
        apps/macos/Sources/ArchSightApp/WorkspaceCommands.swift \
        apps/macos/Sources/ArchSightApp/WelcomeView.swift \
        apps/macos/Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] surface recent folders in menu and welcome screen"
```

---

## Task 7: Manual verification

**Files:** none (manual run).

- [ ] **Step 1: Build and launch the app bundle**

Run: `scripts/build-app.sh && open dist/ArchSight.app`
Expected: App launches showing the `WelcomeView` (icon + "Open Folder…", no Recent section on first run).

- [ ] **Step 2: Open folders and confirm recording**

In the app: open two or three different folders (⌘O). After each, confirm the sidebar populates. Then check **File ▸ Open Recent** — the folders appear, most-recent first.

- [ ] **Step 3: Confirm persistence**

Quit the app (⌘Q) and relaunch with `open dist/ArchSight.app`. The welcome screen now lists the recent folders, and File ▸ Open Recent still shows them.

- [ ] **Step 4: Confirm reopen works from both surfaces**

Click a row on the welcome screen → the folder opens. Open a new window/quit-relaunch, then use File ▸ Open Recent ▸ <folder> → the folder opens.

- [ ] **Step 5: Confirm remove + clear**

On the welcome screen, hover a row and click the ✕ → it disappears. Then File ▸ Open Recent ▸ Clear Menu → the submenu becomes disabled and the welcome screen's Recent section is gone.

- [ ] **Step 6: Update the README features/shortcuts (if present)**

Open `apps/macos/README.md`. If it enumerates features or menus, add a short "Recent Folders" note under the relevant section (File menu / Open Recent + welcome screen). Keep it to 1–2 lines consistent with existing entries. Commit:

```bash
git add apps/macos/README.md
git commit -m "docs: [macos] note recent folders in README"
```

---

## Self-Review Notes

- **Spec coverage:** `RecentFolder` + store (spec §元件 1–2) → Tasks 1–2. Injection (spec §元件 5) → Task 3. Open Recent submenu (spec §元件 4) → Task 4. WelcomeView (spec §元件 3) → Task 5. Recording on open + openRecent wiring + welcome placement (spec §元件 5, §資料流) → Task 6. Manual verification (spec §測試) → Task 7. Store unit tests (spec §測試) → Task 2.
- **Cap behavior:** stored cap 15 (`storedCap`), UI shows `prefix(10)` in both the menu (Task 4) and welcome screen (Tasks 5–6) — consistent.
- **Method names** are consistent across tasks: `record(path:)`, `remove(path:)`, `clear()`, `existingEntries()`, `entries`.
- **Build ordering:** Tasks 3–6 are intentionally one compiling unit; only Task 6 builds green. This is called out in Tasks 3–5 so an out-of-order reader does not expect an intermediate green build.
