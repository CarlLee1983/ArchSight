import Foundation

public enum ThemeAppearance: String, Sendable {
    case light
    case dark
    case system
}

public struct ReadingPalette: Equatable, Sendable {
    public let background: String
    public let foreground: String
    public let secondaryText: String
    public let border: String
    public let blockquote: String
    public let codeBackground: String
    public let keyword: String
    public let string: String
    public let comment: String
    public let number: String
    public let function: String
    public let type: String
    public let op: String

    /// Maps a canonical syntax token type to its hex color, mirroring
    /// `CodeTextView.color(for:)`. Falls back to `foreground`.
    public func syntaxColor(for type: String) -> String {
        switch type {
        case "keyword": return keyword
        case "string": return string
        case "comment": return comment
        case "number", "constant": return number
        case "function": return function
        case "type": return self.type
        case "operator": return op
        default: return foreground
        }
    }
}

public struct ReadingTheme: Sendable {
    public let id: ReadingThemeID
    public let appearance: ThemeAppearance
    public let palette: ReadingPalette

    /// `.system` follows the OS appearance via dynamic colors; adapters emit
    /// system color tokens instead of the placeholder hex palette.
    public var isDynamic: Bool { id == .system }

    /// CSS `color-scheme` value so form controls / scrollbars match the theme.
    public var cssColorScheme: String {
        switch appearance {
        case .light: return "light"
        case .dark: return "dark"
        case .system: return "light dark"
        }
    }

    public static func theme(for id: ReadingThemeID) -> ReadingTheme {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    public static let catalog: [ReadingTheme] = [
        ReadingTheme(
            id: .system,
            appearance: .system,
            palette: ReadingPalette(
                background: "#ffffff", foreground: "#000000", secondaryText: "#3c3c43",
                border: "#d0d0d0", blockquote: "#3c3c43", codeBackground: "#f5f5f5",
                keyword: "#cf222e", string: "#0a3069", comment: "#6e7781",
                number: "#0550ae", function: "#8250df", type: "#953800", op: "#1f2328"
            )
        ),
        ReadingTheme(
            id: .github,
            appearance: .light,
            palette: ReadingPalette(
                background: "#ffffff", foreground: "#1f2328", secondaryText: "#59636e",
                border: "#d1d9e0", blockquote: "#59636e", codeBackground: "#f6f8fa",
                keyword: "#cf222e", string: "#0a3069", comment: "#59636e",
                number: "#0550ae", function: "#8250df", type: "#953800", op: "#1f2328"
            )
        ),
        ReadingTheme(
            id: .solarized,
            appearance: .dark,
            palette: ReadingPalette(
                background: "#002b36", foreground: "#93a1a1", secondaryText: "#657b83",
                border: "#073642", blockquote: "#839496", codeBackground: "#073642",
                keyword: "#859900", string: "#2aa198", comment: "#586e75",
                number: "#d33682", function: "#268bd2", type: "#b58900", op: "#93a1a1"
            )
        ),
        ReadingTheme(
            id: .highContrast,
            appearance: .dark,
            palette: ReadingPalette(
                background: "#000000", foreground: "#ffffff", secondaryText: "#c0c0c0",
                border: "#ffffff", blockquote: "#e0e0e0", codeBackground: "#1a1a1a",
                keyword: "#ff8cc6", string: "#ff6b6b", comment: "#b0b0b0",
                number: "#ffb86c", function: "#6bc7ff", type: "#d39bff", op: "#ffffff"
            )
        ),
    ]
}

public struct RGBA: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// Parses `#rrggbb` (with or without leading `#`, case-insensitive).
    /// Returns nil for any other format.
    public init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6,
              let int = UInt32(value, radix: 16)
        else { return nil }
        red = Double((int >> 16) & 0xff) / 255.0
        green = Double((int >> 8) & 0xff) / 255.0
        blue = Double(int & 0xff) / 255.0
        alpha = 1.0
    }
}
