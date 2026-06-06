import ArchSightKit
import SwiftUI

/// Actions the currently focused window exposes to the app-wide command menu.
/// Defaults are no-ops so the menu items stay harmless when no window is focused.
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
    let recentStore: RecentFoldersStore
    @FocusedValue(\.workspaceCommands) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") { actions?.openFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)

            let recents = Array(recentStore.visibleEntries.prefix(RecentFoldersStore.displayCap))
            Menu("Open Recent") {
                ForEach(recents) { folder in
                    Button(folder.name) { actions?.openRecent(folder.path) }
                        .help(folder.path)
                        .disabled(actions == nil)
                }
                Divider()
                Button("Clear Menu") { recentStore.clear() }
            }
            .disabled(recents.isEmpty)
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
            Button("Collapse Folders") { actions?.collapseAll() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(actions == nil)
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

        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { actions?.showShortcuts() }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}
