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
}
