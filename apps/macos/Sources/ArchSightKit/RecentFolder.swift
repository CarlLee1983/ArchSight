import Foundation

/// One persisted "recently opened folder" entry. Immutable; `id` is the path so
/// the same folder de-duplicates regardless of when it was last opened.
public struct RecentFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let lastOpened: Date

    public init(path: String, name: String, lastOpened: Date) {
        self.path = path
        self.name = name
        self.lastOpened = lastOpened
    }
}
