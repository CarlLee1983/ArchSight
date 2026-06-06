import Foundation

/// Parses "Go to Line" overlay input into a navigable 1-based line. AppKit-free
/// so it is unit-testable. Mirrors VSCode's input shapes: a bare line number, an
/// optional leading colon (`:42`), and a `line:column` form whose column is
/// ignored for read-only scroll navigation.
public enum GoToLineQuery {
    /// Resolves `input` to a 1-based line clamped to `[1, totalLines]`.
    ///
    /// Returns `nil` when there is no line number to act on (empty, bare colon,
    /// non-numeric) or when the buffer has no lines (`totalLines < 1`).
    public static func resolve(_ input: String, totalLines: Int) -> Int? {
        guard totalLines >= 1 else { return nil }
        var body = input.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix(":") { body.removeFirst() }
        let linePart = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let line = Int(linePart) else { return nil }
        return min(max(line, 1), totalLines)
    }
}
