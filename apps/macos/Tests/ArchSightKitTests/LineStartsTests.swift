import XCTest
@testable import ArchSightKit

final class LineStartsTests: XCTestCase {
    func testEmptyStringHasSingleLineStartingAtZero() {
        let starts = LineStarts("")
        XCTAssertEqual(starts.offsets, [0])
        XCTAssertEqual(starts.lineCount, 1)
        XCTAssertEqual(starts.lineIndex(forUTF16Offset: 0), 0)
    }

    func testOffsetsAtEachLineStart() {
        let starts = LineStarts("a\nb\nc")
        XCTAssertEqual(starts.offsets, [0, 2, 4])
        XCTAssertEqual(starts.lineCount, 3)
    }

    func testTrailingNewlineAddsTrailingLine() {
        let starts = LineStarts("a\n")
        XCTAssertEqual(starts.offsets, [0, 2])
        XCTAssertEqual(starts.lineCount, 2)
    }

    func testLineIndexResolvesWithinAndAcrossLines() {
        let starts = LineStarts("ab\ncd\nef")
        XCTAssertEqual(starts.lineIndex(forUTF16Offset: 0), 0)
        XCTAssertEqual(starts.lineIndex(forUTF16Offset: 2), 0) // the newline still belongs to line 0
        XCTAssertEqual(starts.lineIndex(forUTF16Offset: 3), 1)
        XCTAssertEqual(starts.lineIndex(forUTF16Offset: 5), 1)
        XCTAssertEqual(starts.lineIndex(forUTF16Offset: 6), 2)
        XCTAssertEqual(starts.lineIndex(forUTF16Offset: 999), 2) // clamps to last line
    }

    func testNegativeOffsetResolvesToFirstLine() {
        XCTAssertEqual(LineStarts("a\nb").lineIndex(forUTF16Offset: -5), 0)
    }

    func testCountsNewlinesInMultibyteContent() {
        // 😀 is a surrogate pair (2 UTF-16 units); line starts are UTF-16 offsets.
        let starts = LineStarts("a😀\nb")
        XCTAssertEqual(starts.offsets, [0, 4])
        XCTAssertEqual(starts.lineCount, 2)
    }
}
