import XCTest
@testable import ArchSightKit

final class FuzzyMatchTests: XCTestCase {
    func testSubsequenceMatchIsCaseInsensitive() {
        XCTAssertTrue(FuzzyMatch.matches("main", in: "MAIN.go"))
        XCTAssertTrue(FuzzyMatch.matches("mg", in: "main.go"))
        XCTAssertFalse(FuzzyMatch.matches("xyz", in: "main.go"))
        XCTAssertFalse(FuzzyMatch.matches("og", in: "main.go")) // wrong order
    }

    func testEmptyQueryReturnsAllCandidatesInOriginalOrder() {
        let candidates = ["b.txt", "a.txt", "c.txt"]
        XCTAssertEqual(FuzzyMatch.rank("", candidates: candidates), candidates)
    }

    func testNonMatchesAreFilteredOut() {
        let ranked = FuzzyMatch.rank("zz", candidates: ["main.go", "buzz.txt"])
        XCTAssertEqual(ranked, ["buzz.txt"])
    }

    func testConsecutiveMatchOutranksScattered() {
        let a = FuzzyMatch.score("ab", in: "ab_c")!
        let b = FuzzyMatch.score("ab", in: "a_b_c")!
        XCTAssertGreaterThan(a, b)
    }

    func testFilenameMatchOutranksScatteredSegments() {
        let ranked = FuzzyMatch.rank("main", candidates: ["m/a/i/n.txt", "app/main.swift"])
        XCTAssertEqual(ranked.first, "app/main.swift")
    }

    func testTiesPreserveInputOrder() {
        // Identical scoring shape; input order must be preserved.
        let ranked = FuzzyMatch.rank("a", candidates: ["a1", "a2"])
        XCTAssertEqual(ranked, ["a1", "a2"])
    }
}
