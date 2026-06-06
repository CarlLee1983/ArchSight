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

    func testGoToLineHintIsRegistered() {
        let hint = ShortcutCatalog.hint("goToLine")
        XCTAssertEqual(hint?.category, .navigation)
        XCTAssertEqual(hint?.label, "Go to Line")
        XCTAssertEqual(hint?.chord.display, "⌃G")
    }

    func testGoToSymbolHintIsRegistered() {
        let hint = ShortcutCatalog.hint("goToSymbol")
        XCTAssertEqual(hint?.category, .navigation)
        XCTAssertEqual(hint?.label, "Go to Symbol in File")
        XCTAssertEqual(hint?.chord.display, "⇧⌘O")
    }

    func testTooltipAppendsChordInParenthesesWhenHintExists() {
        // VSCode-style: "Label (⇧⌘E)".
        XCTAssertEqual(ShortcutCatalog.tooltip("Back", "back"), "Back (⌘[)")
        XCTAssertEqual(ShortcutCatalog.tooltip("File Explorer", "showExplorer"), "File Explorer (⇧⌘E)")
    }

    func testTooltipReturnsBareLabelWhenHintMissing() {
        // No trailing space, no empty parentheses when the id is unknown.
        XCTAssertEqual(ShortcutCatalog.tooltip("Reading settings", "nope"), "Reading settings")
    }

    func testSidebarAndTabHintsAreRegistered() {
        // Tooltips added in this branch must resolve to real chords.
        XCTAssertEqual(ShortcutCatalog.hint("showSearch")?.chord.display, "⇧⌘F")
        XCTAssertEqual(ShortcutCatalog.hint("closeTab")?.chord.display, "⌘W")
        XCTAssertEqual(ShortcutCatalog.hint("increaseText")?.chord.display, "⌘=")
        XCTAssertEqual(ShortcutCatalog.hint("decreaseText")?.chord.display, "⌘-")
    }

    func testWordWrapHintIsRegistered() {
        let hint = ShortcutCatalog.hint("wordWrap")
        XCTAssertEqual(hint?.category, .view)
        XCTAssertEqual(hint?.label, "Toggle Word Wrap")
        XCTAssertEqual(hint?.chord.display, "⌥Z") // VSCode's word-wrap chord on macOS
    }
}
