import Foundation

/// Precomputed UTF-16 offsets where each line begins, so a line-number gutter can
/// map a character offset to its 1-based line in O(log n) instead of rescanning
/// the buffer on every scroll frame. AppKit-free and unit-testable; the gutter
/// rebuilds this only when the file content changes.
public struct LineStarts: Equatable, Sendable {
    /// UTF-16 offset of each line's first character. Always starts with 0, so a
    /// buffer with N newlines has N + 1 entries (an empty buffer has one).
    public let offsets: [Int]

    public init(_ text: String) {
        var starts = [0]
        var index = 0
        for unit in text.utf16 {
            index += 1
            if unit == 0x0A {
                starts.append(index)
            }
        }
        self.offsets = starts
    }

    /// Number of lines (newline count + 1).
    public var lineCount: Int { offsets.count }

    /// 0-based index of the line containing `offset` (the last line start that is
    /// less than or equal to `offset`). Offsets below 0 resolve to the first line.
    public func lineIndex(forUTF16Offset offset: Int) -> Int {
        var low = 0
        var high = offsets.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if offsets[mid] <= offset {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
