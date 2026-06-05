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

public enum ShortcutCategory: String, CaseIterable, Hashable, Sendable {
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

/// Single display source for keyboard hints. Mirrors the app's keyboard bindings
/// (most declared in `WorkspaceMenuCommands` / `ContentView`; a few are AppKit or
/// system defaults, e.g. Find ⌘F and New Window ⌘N); kept consistent via unit tests.
public enum ShortcutCatalog {
    public static let all: [ShortcutHint] = [
        // Navigation
        ShortcutHint(id: "newWindow", category: .navigation, label: "New Window", chord: KeyChord(key: "N", command: true)),
        ShortcutHint(id: "openFolder", category: .navigation, label: "Open Folder", chord: KeyChord(key: "O", command: true)),
        ShortcutHint(id: "quickOpen", category: .navigation, label: "Quick Open", chord: KeyChord(key: "P", command: true)),
        ShortcutHint(id: "findInFile", category: .navigation, label: "Find in File", chord: KeyChord(key: "F", command: true)), // AppKit native find bar (usesFindBar), not an explicit app binding
        ShortcutHint(id: "back", category: .navigation, label: "Back", chord: KeyChord(key: "[", command: true)),
        ShortcutHint(id: "forward", category: .navigation, label: "Forward", chord: KeyChord(key: "]", command: true)),
        // View
        ShortcutHint(id: "toggleSidebar", category: .view, label: "Toggle Sidebar", chord: KeyChord(key: "B", command: true)),
        ShortcutHint(id: "showExplorer", category: .view, label: "Show Explorer", chord: KeyChord(key: "E", command: true, shift: true)),
        ShortcutHint(id: "showSearch", category: .view, label: "Show Search", chord: KeyChord(key: "F", command: true, shift: true)),
        ShortcutHint(id: "splitEditor", category: .view, label: "Split Editor", chord: KeyChord(key: "\\", command: true)),
        ShortcutHint(id: "collapseFolders", category: .view, label: "Collapse Folders", chord: KeyChord(key: "0", command: true, option: true)),
        ShortcutHint(id: "increaseText", category: .view, label: "Increase Text Size", chord: KeyChord(key: "=", command: true)),
        ShortcutHint(id: "decreaseText", category: .view, label: "Decrease Text Size", chord: KeyChord(key: "-", command: true)),
        // Tabs
        ShortcutHint(id: "goToTab", category: .tabs, label: "Go to Tab 1–9", chord: KeyChord(key: "1–9", command: true)), // display range only; real bindings are ⌘1…⌘9
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
