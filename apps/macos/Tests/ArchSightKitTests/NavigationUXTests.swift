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

    func testUTF16OffsetRoundTripsWithLineColumn() {
        let text = "package main\nfunc f() {}\n"
        for offset in 0...text.utf16.count {
            let pos = TextPosition.lineColumn(forUTF16Offset: offset, in: text)
            let back = TextPosition.utf16Offset(forLine: pos.line, column: pos.column, in: text)
            XCTAssertEqual(back, offset, "round trip failed at offset \(offset)")
        }
    }

    func testUTF16OffsetForLineColumnWithMultibyte() {
        let text = "let s = \"é😀\"\nx"
        // navigates past the surrogate pair to find the newline; line 2,
        // column 1 is the unit right after the newline -> 'x'
        let offset = TextPosition.utf16Offset(forLine: 2, column: 1, in: text)
        let units = Array(text.utf16)
        XCTAssertEqual(units[offset], UInt16(UnicodeScalar("x").value))
    }

    func testUTF16OffsetColumnBeyondLineClampsToLineEnd() {
        let text = "ab\ncd\n"
        // column 99 on line 1 should clamp at the newline (offset 2)
        XCTAssertEqual(TextPosition.utf16Offset(forLine: 1, column: 99, in: text), 2)
    }

    func testUTF16OffsetRoundTripsThroughSurrogatePair() {
        let text = "a😀b\nx" // 😀 is a surrogate pair (2 UTF-16 units)
        for offset in 0...text.utf16.count {
            let pos = TextPosition.lineColumn(forUTF16Offset: offset, in: text)
            let back = TextPosition.utf16Offset(forLine: pos.line, column: pos.column, in: text)
            XCTAssertEqual(back, offset, "round trip failed at offset \(offset)")
        }
    }
}
