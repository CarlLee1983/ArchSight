import XCTest
@testable import ArchSightKit
@testable import ArchSightApp

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

    func testRGBAParsesSixDigitHex() {
        let color = RGBA(hex: "#268bd2")
        XCTAssertNotNil(color)
        XCTAssertEqual(color!.red, 0x26 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color!.green, 0x8b / 255.0, accuracy: 0.001)
        XCTAssertEqual(color!.blue, 0xd2 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color!.alpha, 1.0, accuracy: 0.001)
    }

    func testRGBAAcceptsHexWithoutHashAndIsCaseInsensitive() {
        XCTAssertEqual(RGBA(hex: "FFFFFF"), RGBA(hex: "#ffffff"))
    }

    func testRGBARejectsMalformedHex() {
        XCTAssertNil(RGBA(hex: "#12"))
        XCTAssertNil(RGBA(hex: "#gggggg"))
    }

    func testDarkThemeColorSchemeIsDark() {
        XCTAssertEqual(ReadingTheme.theme(for: .solarized).cssColorScheme, "dark")
        XCTAssertEqual(ReadingTheme.theme(for: .highContrast).cssColorScheme, "dark")
    }

    func testCustomIconsCompileAndCanBeInstantiated() {
        _ = ArchSightIcon.Folder()
        _ = ArchSightIcon.FolderOpen()
        _ = ArchSightIcon.File()
        _ = ArchSightIcon.Search()
        _ = ArchSightIcon.Explorer()
        _ = ArchSightIcon.Settings()
        _ = ArchSightIcon.Close()
        _ = ArchSightIcon.StatusIndicator(color: .green, pulsing: true)
        XCTAssertTrue(true)
    }
}
