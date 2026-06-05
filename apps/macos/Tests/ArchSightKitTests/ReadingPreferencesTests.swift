import XCTest
@testable import ArchSightKit

final class ReadingPreferencesTests: XCTestCase {
    func testThemeIDsAreStableAndComplete() {
        XCTAssertEqual(
            ReadingThemeID.allCases,
            [.system, .github, .solarized, .highContrast]
        )
        XCTAssertEqual(ReadingThemeID.github.rawValue, "github")
    }

    func testLineSpacingMapsToCSSAndMultiple() {
        XCTAssertEqual(LineSpacing.compact.cssLineHeight, 1.4, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.normal.cssLineHeight, 1.55, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.relaxed.cssLineHeight, 1.8, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.compact.lineHeightMultiple, 1.0, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.relaxed.lineHeightMultiple, 1.45, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.compact.textInset, 6, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.relaxed.textInset, 12, accuracy: 0.001)
    }

    func testDefaultPreferences() {
        let prefs = ReadingPreferences.default
        XCTAssertEqual(prefs.theme, .system)
        XCTAssertEqual(prefs.fontScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(prefs.lineSpacing, .normal)
    }

    func testFontSteppingClampsAtBounds() {
        var prefs = ReadingPreferences.default
        prefs = prefs.increasedFont()
        XCTAssertEqual(prefs.fontScale, 1.15, accuracy: 0.001)
        prefs = prefs.increasedFont().increasedFont().increasedFont().increasedFont()
        XCTAssertEqual(prefs.fontScale, 1.5, accuracy: 0.001) // clamps at top
        prefs = ReadingPreferences.default
        prefs = prefs.decreasedFont().decreasedFont()
        XCTAssertEqual(prefs.fontScale, 0.85, accuracy: 0.001) // clamps at bottom
    }

    func testNormalizedSnapsArbitraryScaleToNearestStep() {
        let messy = ReadingPreferences(theme: .github, fontScale: 1.22, lineSpacing: .compact)
        XCTAssertEqual(messy.normalized().fontScale, 1.15, accuracy: 0.001)
        XCTAssertEqual(ReadingPreferences(theme: .system, fontScale: 9.0, lineSpacing: .normal)
            .normalized().fontScale, 1.5, accuracy: 0.001)
    }

    func testCodableRoundTrip() throws {
        let prefs = ReadingPreferences(theme: .solarized, fontScale: 1.3, lineSpacing: .relaxed)
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ReadingPreferences.self, from: data)
        XCTAssertEqual(decoded, prefs)
    }
}
