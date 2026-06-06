import XCTest
@testable import ArchSightKit

@MainActor
final class RecentFoldersStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.recent.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshStoreIsEmpty() {
        let store = RecentFoldersStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRecordAddsEntryWithDerivedName() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/Users/x/Dev/ArchSight")
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.path, "/Users/x/Dev/ArchSight")
        XCTAssertEqual(store.entries.first?.name, "ArchSight")
    }

    func testRecordSamePathDeduplicatesAndMovesToFront() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")
        store.record(path: "/a/one")
        XCTAssertEqual(store.entries.map(\.path), ["/a/one", "/a/two"])
    }

    func testRecordOrdersMostRecentFirst() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")
        store.record(path: "/a/three")
        XCTAssertEqual(store.entries.map(\.path), ["/a/three", "/a/two", "/a/one"])
    }

    func testRecordEnforcesStoredCapOfFifteen() {
        let store = RecentFoldersStore(defaults: defaults)
        for i in 0..<20 { store.record(path: "/a/\(i)") }
        XCTAssertEqual(store.entries.count, 15)
        XCTAssertEqual(store.entries.first?.path, "/a/19")
        XCTAssertEqual(store.entries.last?.path, "/a/5")
    }

    func testRemoveDropsSingleEntry() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")
        store.remove(path: "/a/one")
        XCTAssertEqual(store.entries.map(\.path), ["/a/two"])
    }

    func testClearEmptiesEntries() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testEntriesPersistAcrossStores() {
        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/a/one")
        store.record(path: "/a/two")

        let reloaded = RecentFoldersStore(defaults: defaults)
        XCTAssertEqual(reloaded.entries.map(\.path), ["/a/two", "/a/one"])
    }

    func testCorruptStorageFallsBackToEmpty() {
        defaults.set(Data("not json".utf8), forKey: "recentFolders.v1")
        let store = RecentFoldersStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testExistingEntriesFiltersMissingPathsWithoutMutatingStorage() throws {
        let tempDir = NSTemporaryDirectory() + "recent-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = RecentFoldersStore(defaults: defaults)
        store.record(path: "/definitely/missing/path")
        store.record(path: tempDir)

        XCTAssertEqual(store.existingEntries().map(\.path), [tempDir])
        XCTAssertEqual(store.entries.count, 2)
    }
}
