import Foundation

/// A linear back/forward history of visited tab identifiers, mirroring browser
/// semantics: visiting a new entry after going back truncates the forward branch.
public struct NavigationHistory: Equatable, Sendable {
    private var entries: [String] = []
    private var index: Int = -1

    public init() {}

    public var current: String? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    public var canGoBack: Bool {
        index > 0
    }

    public var canGoForward: Bool {
        index >= 0 && index < entries.count - 1
    }

    public mutating func visit(_ id: String) {
        if current == id {
            return
        }
        if index < entries.count - 1 {
            entries.removeSubrange((index + 1)...)
        }
        entries.append(id)
        index = entries.count - 1
    }

    @discardableResult
    public mutating func back() -> String? {
        guard canGoBack else {
            return nil
        }
        index -= 1
        return entries[index]
    }

    @discardableResult
    public mutating func forward() -> String? {
        guard canGoForward else {
            return nil
        }
        index += 1
        return entries[index]
    }
}
