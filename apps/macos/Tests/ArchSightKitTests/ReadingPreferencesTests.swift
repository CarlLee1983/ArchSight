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
}
