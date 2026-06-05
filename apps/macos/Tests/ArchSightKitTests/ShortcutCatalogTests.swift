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
}
