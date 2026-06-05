import XCTest
@testable import ArchSightKit

final class ReadingPreferencesStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.reading.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshStoreStartsAtDefaults() {
        let store = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences, .default)
    }

    func testMutationsPersistAcrossStores() {
        let store = ReadingPreferencesStore(defaults: defaults)
        store.setTheme(.github)
        store.increaseFont()
        store.setLineSpacing(.relaxed)

        let reloaded = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.theme, .github)
        XCTAssertEqual(reloaded.preferences.fontScale, 1.15, accuracy: 0.001)
        XCTAssertEqual(reloaded.preferences.lineSpacing, .relaxed)
    }

    func testCorruptStorageFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "reading.preferences")
        let store = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences, .default)
    }

    func testLoadedScaleIsNormalized() throws {
        let messy = ReadingPreferences(theme: .system, fontScale: 1.22, lineSpacing: .normal)
        defaults.set(try JSONEncoder().encode(messy), forKey: "reading.preferences")
        let store = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences.fontScale, 1.15, accuracy: 0.001)
    }
}
