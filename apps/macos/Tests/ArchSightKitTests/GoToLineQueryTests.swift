import XCTest
@testable import ArchSightKit

final class GoToLineQueryTests: XCTestCase {
    func testPlainLineNumberWithinRange() {
        XCTAssertEqual(GoToLineQuery.resolve("10", totalLines: 100), 10)
    }

    func testClampsBelowOneUpToFirstLine() {
        XCTAssertEqual(GoToLineQuery.resolve("0", totalLines: 100), 1)
        XCTAssertEqual(GoToLineQuery.resolve("-5", totalLines: 100), 1)
    }

    func testClampsAboveTotalDownToLastLine() {
        XCTAssertEqual(GoToLineQuery.resolve("999", totalLines: 100), 100)
    }

    func testAcceptsLeadingColon() {
        XCTAssertEqual(GoToLineQuery.resolve(":42", totalLines: 100), 42)
    }

    func testIgnoresColumnSuffix() {
        XCTAssertEqual(GoToLineQuery.resolve("42:7", totalLines: 100), 42)
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(GoToLineQuery.resolve("  12  ", totalLines: 100), 12)
    }

    func testNonNumericIsNil() {
        XCTAssertNil(GoToLineQuery.resolve("abc", totalLines: 100))
    }

    func testEmptyOrBareColonIsNil() {
        XCTAssertNil(GoToLineQuery.resolve("", totalLines: 100))
        XCTAssertNil(GoToLineQuery.resolve(":", totalLines: 100))
    }

    func testZeroTotalLinesIsNil() {
        XCTAssertNil(GoToLineQuery.resolve("10", totalLines: 0))
    }
}
