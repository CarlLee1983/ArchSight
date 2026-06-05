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
    public static func spans(for tokens: [SyntaxToken], in content: String) -> [HighlightSpan] {
        let unitCount = content.utf16.count
        var spans: [HighlightSpan] = []
        spans.reserveCapacity(tokens.count)
        for token in tokens {
            let start = TextPosition.utf16Offset(forLine: token.startLine, column: token.startColumn, in: content)
            let end = TextPosition.utf16Offset(forLine: token.endLine, column: token.endColumn, in: content)
            guard start >= 0, end > start, end <= unitCount else { continue }
            spans.append(HighlightSpan(range: NSRange(location: start, length: end - start), type: token.type))
        }
        return spans
    }
}
