import Foundation
import Observation

/// Observable, persistent most-recently-used list of opened folders. Mirrors
/// `ReadingPreferencesStore`'s `UserDefaults` + JSON persistence. `@MainActor`
/// because it is only ever read/written from SwiftUI views and menu actions.
@MainActor
@Observable
public final class RecentFoldersStore {
    public private(set) var entries: [RecentFolder]
    public private(set) var visibleEntries: [RecentFolder] = []

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "recentFolders.v1"
    private static let storedCap = 15
    public static let displayCap = 10

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
        refreshVisible()
    }

    /// Inserts (or refreshes) `path` at the front, de-duplicating by path and
    /// trimming the oldest entries beyond the stored cap.
    public func record(path: String) {
        let entry = RecentFolder(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            lastOpened: Date()
        )
        let withoutDuplicate = entries.filter { $0.path != path }
        entries = Array(([entry] + withoutDuplicate).prefix(Self.storedCap))
        persist()
        refreshVisible()
    }

    public func remove(path: String) {
        entries = entries.filter { $0.path != path }
        persist()
        refreshVisible()
    }

    public func clear() {
        entries = []
        persist()
        refreshVisible()
    }

    /// Recomputes `visibleEntries` = entries whose path is currently an existing
    /// directory. Cached (rather than filtered per-render) so SwiftUI never does
    /// filesystem I/O inside a view `body`. Stale only across external filesystem
    /// changes while no store mutation occurs — acceptable for this empty-state UI.
    private func refreshVisible() {
        let fileManager = FileManager.default
        visibleEntries = entries.filter { entry in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [RecentFolder] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentFolder].self, from: data)
        else {
            return []
        }
        return Array(decoded.prefix(storedCap))
    }
}
