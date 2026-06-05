import Foundation

/// A UTF-16 range over file content paired with its canonical token type, ready
/// for the read-only code viewer to colorize. AppKit-free so it is unit-testable.
public struct HighlightSpan: Equatable, Sendable {
    public let range: NSRange
    public let type: String

    public init(range: NSRange, type: String) {
        self.range = range
        self.type = type
    }
}

public enum SyntaxHighlighting {
    /// Converts syntax tokens (1-based line / UTF-16 column) into UTF-16 ranges.
    /// Tokens whose range is empty, inverted, or out of bounds are dropped.
    ///
    /// Resolves every token in a single pass: the UTF-16 line structure is
    /// computed once, then each (line, column) maps to an offset in O(1). This
    /// avoids re-scanning the whole buffer per token, which matters for large
    /// files with many highlight tokens.
    public static func spans(for tokens: [SyntaxToken], in content: String) -> [HighlightSpan] {
        guard !tokens.isEmpty else { return [] }
        let units = Array(content.utf16)
        // UTF-16 offset where each 1-based line begins (line 1 at index 0).
        var lineStarts: [Int] = [0]
        for i in 0..<units.count where units[i] == 0x0A {
            lineStarts.append(i + 1)
        }
        // 1-based (line, column) -> UTF-16 offset, clamped to the line end (the
        // position of the line's newline, or end of text) and to text bounds.
        func offset(line: Int, column: Int) -> Int {
            guard line >= 1, line <= lineStarts.count else { return units.count }
            let base = lineStarts[line - 1]
            let lineEnd = line < lineStarts.count ? lineStarts[line] - 1 : units.count
            let target = base + max(0, column - 1)
            return min(max(base, target), lineEnd)
        }
        var spans: [HighlightSpan] = []
        spans.reserveCapacity(tokens.count)
        for token in tokens {
            let start = offset(line: token.startLine, column: token.startColumn)
            let end = offset(line: token.endLine, column: token.endColumn)
            guard end > start else { continue }
            spans.append(HighlightSpan(range: NSRange(location: start, length: end - start), type: token.type))
        }
        return spans
    }
}
