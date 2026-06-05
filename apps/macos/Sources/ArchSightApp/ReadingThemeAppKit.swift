import AppKit
import ArchSightKit

/// Bridges a value-type `ReadingTheme` to AppKit drawing primitives for the
/// code view. Dynamic (`.system`) themes return the existing dynamic system
/// colors so light/dark continues to follow the OS automatically.
enum ReadingThemeAppKit {
    static func font(scale: Double) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: CGFloat(12 * scale), weight: .regular)
    }

    static func backgroundColor(for theme: ReadingTheme) -> NSColor {
        theme.isDynamic ? .textBackgroundColor : color(hex: theme.palette.background)
    }

    static func foregroundColor(for theme: ReadingTheme) -> NSColor {
        theme.isDynamic ? .labelColor : color(hex: theme.palette.foreground)
    }

    static func syntaxColor(for type: String, theme: ReadingTheme) -> NSColor {
        if theme.isDynamic {
            return dynamicSyntaxColor(for: type)
        }
        return color(hex: theme.palette.syntaxColor(for: type))
    }

    static func paragraphStyle(for lineSpacing: LineSpacing) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = CGFloat(lineSpacing.lineHeightMultiple)
        return style
    }

    /// Mirrors the original `CodeTextView.color(for:)` mapping.
    private static func dynamicSyntaxColor(for type: String) -> NSColor {
        switch type {
        case "keyword": return .systemPink
        case "string": return .systemRed
        case "comment": return .secondaryLabelColor
        case "number", "constant": return .systemOrange
        case "function": return .systemBlue
        case "type": return .systemPurple
        case "operator": return .secondaryLabelColor
        default: return .labelColor
        }
    }

    static func color(hex: String) -> NSColor {
        guard let rgba = RGBA(hex: hex) else { return .labelColor }
        return NSColor(
            srgbRed: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            alpha: rgba.alpha
        )
    }
}
