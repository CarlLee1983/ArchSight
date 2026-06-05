import XCTest
@testable import ArchSightKit

final class ReadingThemeTests: XCTestCase {
    func testCatalogCoversEveryThemeID() {
        let ids = ReadingTheme.catalog.map(\.id)
        XCTAssertEqual(ids, ReadingThemeID.allCases)
    }

    func testThemeLookupReturnsMatchingID() {
        XCTAssertEqual(ReadingTheme.theme(for: .solarized).id, .solarized)
    }

    func testSystemThemeIsDynamicAndOthersAreNot() {
        XCTAssertTrue(ReadingTheme.theme(for: .system).isDynamic)
        XCTAssertFalse(ReadingTheme.theme(for: .github).isDynamic)
        XCTAssertEqual(ReadingTheme.theme(for: .github).appearance, .light)
        XCTAssertEqual(ReadingTheme.theme(for: .solarized).appearance, .dark)
    }

    func testNamedThemePaletteUsesHexColors() {
        let github = ReadingTheme.theme(for: .github)
        XCTAssertEqual(github.palette.background, "#ffffff")
        XCTAssertEqual(github.palette.foreground, "#1f2328")
        XCTAssertEqual(github.cssColorScheme, "light")
    }

    func testSyntaxColorLookupCoversCanonicalTypes() {
        let p = ReadingTheme.theme(for: .github).palette
        XCTAssertEqual(p.syntaxColor(for: "keyword"), p.keyword)
        XCTAssertEqual(p.syntaxColor(for: "string"), p.string)
        XCTAssertEqual(p.syntaxColor(for: "unknown"), p.foreground) // fallback
    }
}
