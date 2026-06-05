import Foundation

/// Converts a UTF-16 character offset (as reported by AppKit text views) into a
/// 1-based line and column, matching the position contract the core expects for
/// definition and references requests.
public enum TextPosition {
    public static func lineColumn(forUTF16Offset rawOffset: Int, in text: String) -> (line: Int, column: Int) {
        let units = Array(text.utf16)
        let offset = max(0, min(rawOffset, units.count))

        var line = 1
        var column = 1
        var index = 0
        while index < offset {
            if units[index] == 0x0A {
                line += 1
                column = 1
            } else {
                column += 1
            }
            index += 1
        }
        return (line, column)
    }

    /// Inverse of `lineColumn`: converts a 1-based line and 1-based UTF-16 column
    /// into a UTF-16 offset. Lines and columns beyond the text clamp to the
    /// nearest valid offset (line end for an over-long column). The result is
    /// always clamped to `[0, content.utf16.count]`.
    public static func utf16Offset(forLine line: Int, column: Int, in text: String) -> Int {
        let units = Array(text.utf16)
        var currentLine = 1
        var index = 0
        while currentLine < line && index < units.count {
            if units[index] == 0x0A {
                currentLine += 1
            }
            index += 1
        }
        var col = 1
        while col < column && index < units.count && units[index] != 0x0A {
            index += 1
            col += 1
        }
        return index
    }
}
