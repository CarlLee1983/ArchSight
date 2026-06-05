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
