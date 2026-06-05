import XCTest
@testable import ArchSightKit

final class NavigationHistoryTests: XCTestCase {
    func testVisitAppendsAndTracksCurrent() {
        var history = NavigationHistory()
        history.visit("a")
        history.visit("b")

        XCTAssertEqual(history.current, "b")
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testBackAndForwardWalkTheStack() {
        var history = NavigationHistory()
        history.visit("a")
        history.visit("b")
        history.visit("c")

        XCTAssertEqual(history.back(), "b")
        XCTAssertEqual(history.back(), "a")
        XCTAssertNil(history.back())
        XCTAssertEqual(history.forward(), "b")
        XCTAssertEqual(history.current, "b")
    }

    func testVisitingAfterBackTruncatesForwardBranch() {
        var history = NavigationHistory()
        history.visit("a")
        history.visit("b")
        history.visit("c")
        _ = history.back() // now at "b"

        history.visit("d")

        XCTAssertEqual(history.current, "d")
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.back(), "b")
    }

    func testVisitingCurrentIdIsNoOp() {
        var history = NavigationHistory()
        history.visit("a")
        history.visit("a")

        XCTAssertEqual(history.current, "a")
        XCTAssertFalse(history.canGoBack)
    }

    func testEmptyHistoryHasNoCurrentOrMoves() {
        var history = NavigationHistory()

        XCTAssertNil(history.current)
        XCTAssertNil(history.back())
        XCTAssertNil(history.forward())
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }
}

final class TextPositionTests: XCTestCase {
    func testOffsetZeroIsLineOneColumnOne() {
        let pos = TextPosition.lineColumn(forUTF16Offset: 0, in: "let x = 1")
        XCTAssertEqual(pos.line, 1)
        XCTAssertEqual(pos.column, 1)
    }

    func testOffsetWithinFirstLine() {
        let pos = TextPosition.lineColumn(forUTF16Offset: 4, in: "let x = 1")
        XCTAssertEqual(pos.line, 1)
        XCTAssertEqual(pos.column, 5)
    }

    func testOffsetAtStartOfSecondLine() {
        // "ab\ncd" -> offset 3 is 'c'
        let pos = TextPosition.lineColumn(forUTF16Offset: 3, in: "ab\ncd")
        XCTAssertEqual(pos.line, 2)
        XCTAssertEqual(pos.column, 1)
    }

    func testOffsetInsideSecondLine() {
        let pos = TextPosition.lineColumn(forUTF16Offset: 4, in: "ab\ncd")
        XCTAssertEqual(pos.line, 2)
        XCTAssertEqual(pos.column, 2)
    }

    func testOffsetBeyondLengthClampsToEnd() {
        let pos = TextPosition.lineColumn(forUTF16Offset: 999, in: "ab\ncd")
        XCTAssertEqual(pos.line, 2)
        XCTAssertEqual(pos.column, 3)
    }

    func testNegativeOffsetClampsToStart() {
        let pos = TextPosition.lineColumn(forUTF16Offset: -5, in: "ab\ncd")
        XCTAssertEqual(pos.line, 1)
        XCTAssertEqual(pos.column, 1)
    }
}
