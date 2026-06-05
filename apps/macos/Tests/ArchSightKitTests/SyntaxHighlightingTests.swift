import XCTest
@testable import ArchSightKit

final class SyntaxHighlightingTests: XCTestCase {
    private func token(_ sl: Int, _ sc: Int, _ el: Int, _ ec: Int, _ type: String) -> SyntaxToken {
        // Decode through JSON to build a SyntaxToken (its memberwise init is synthesized).
        let json = """
        {"startLine":\(sl),"startColumn":\(sc),"endLine":\(el),"endColumn":\(ec),"type":"\(type)"}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(SyntaxToken.self, from: json)
    }

    func testSpansMapTokenToUTF16Range() {
        let content = "func f() {}\n"
        // "func" is line 1, columns 1..5 (end exclusive)
        let tokens = [token(1, 1, 1, 5, "keyword")]
        let spans = SyntaxHighlighting.spans(for: tokens, in: content)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].type, "keyword")
        XCTAssertEqual(spans[0].range, NSRange(location: 0, length: 4))
    }

    func testSpansDropInvalidRanges() {
        let content = "abc"
        let tokens = [
            token(1, 3, 1, 2, "keyword"),  // end before start
            token(9, 1, 9, 5, "string"),   // beyond content
        ]
        XCTAssertTrue(SyntaxHighlighting.spans(for: tokens, in: content).isEmpty)
    }

    func testSpansHandleMultibyteContent() {
        let content = "x = \"é\" // c\n"
        // Columns: x(1) space(2) =(3) space(4) "(5) é(6) "(7) space(8) /(9)/(10) space(11) c(12)
        // comment "// c" spans columns 9..13 (end exclusive)
        let tokens = [token(1, 9, 1, 13, "comment")]
        let spans = SyntaxHighlighting.spans(for: tokens, in: content)
        XCTAssertEqual(spans.count, 1)
        let ns = content as NSString
        XCTAssertEqual(ns.substring(with: spans[0].range), "// c")
    }

    func testSpansEmptyForEmptyTokens() {
        XCTAssertTrue(SyntaxHighlighting.spans(for: [], in: "anything").isEmpty)
    }
}
