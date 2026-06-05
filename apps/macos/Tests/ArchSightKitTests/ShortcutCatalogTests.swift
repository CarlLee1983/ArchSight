import XCTest
@testable import ArchSightKit

final class ShortcutCatalogTests: XCTestCase {
    func testKeyChordDisplayUsesCanonicalModifierOrder() {
        // macOS canonical order is ⌃⌥⇧⌘ immediately before the key.
        XCTAssertEqual(KeyChord(key: "P", command: true).display, "⌘P")
        XCTAssertEqual(KeyChord(key: "[", command: true, shift: true).display, "⇧⌘[")
        XCTAssertEqual(KeyChord(key: "E", command: true, shift: true).display, "⇧⌘E")
        XCTAssertEqual(KeyChord(key: "\\", command: true).display, "⌘\\")
        XCTAssertEqual(KeyChord(key: "/", command: true).display, "⌘/")
        XCTAssertEqual(
            KeyChord(key: "K", command: true, shift: true, option: true, control: true).display,
            "⌃⌥⇧⌘K"
        )
    }

    func testCatalogIsNonEmptyAndEveryCategoryHasEntries() {
        XCTAssertFalse(ShortcutCatalog.all.isEmpty)
        for category in ShortcutCategory.allCases {
            XCTAssertTrue(
                ShortcutCatalog.all.contains { $0.category == category },
                "category \(category) has no shortcuts"
            )
        }
    }

    func testCatalogIdsAreUnique() {
        let ids = ShortcutCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate shortcut id")
    }

    func testCatalogChordsAreUnique() {
        // No two hints should claim the same physical chord (catches double-binding).
        let chords = ShortcutCatalog.all.map(\.chord)
        XCTAssertEqual(chords.count, Set(chords.map(\.display)).count, "duplicate chord")
    }

    func testHintLookupHitAndMiss() {
        XCTAssertEqual(ShortcutCatalog.hint("quickOpen")?.chord.display, "⌘P")
        XCTAssertNil(ShortcutCatalog.hint("nope"))
    }

    func testGroupedCoversAllCategoriesInDeclaredOrder() {
        let grouped = ShortcutCatalog.grouped()
        XCTAssertEqual(grouped.map(\.0), ShortcutCategory.allCases)
        let flattenedCount = grouped.reduce(0) { $0 + $1.1.count }
        XCTAssertEqual(flattenedCount, ShortcutCatalog.all.count)
    }

    func testCollapseFoldersHintIsRegistered() {
        let hint = ShortcutCatalog.hint("collapseFolders")
        XCTAssertEqual(hint?.category, .view)
        XCTAssertEqual(hint?.label, "Collapse Folders")
        XCTAssertEqual(hint?.chord.display, "⌥⌘0")
    }
}
