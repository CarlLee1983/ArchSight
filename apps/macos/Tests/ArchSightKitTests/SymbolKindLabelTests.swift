import XCTest
@testable import ArchSightKit

final class SymbolKindLabelTests: XCTestCase {
    func testKnownKindsMapToNames() {
        XCTAssertEqual(SymbolKindLabel.name(for: 5), "Class")
        XCTAssertEqual(SymbolKindLabel.name(for: 6), "Method")
        XCTAssertEqual(SymbolKindLabel.name(for: 12), "Function")
        XCTAssertEqual(SymbolKindLabel.name(for: 23), "Struct")
        XCTAssertEqual(SymbolKindLabel.name(for: 26), "Type Parameter")
    }

    func testUnknownKindFallsBackToSymbol() {
        XCTAssertEqual(SymbolKindLabel.name(for: 0), "Symbol")
        XCTAssertEqual(SymbolKindLabel.name(for: 99), "Symbol")
    }

    func testKnownKindsHaveSystemImages() {
        XCTAssertEqual(SymbolKindLabel.systemImage(for: 12), "function")
        XCTAssertFalse(SymbolKindLabel.systemImage(for: 5).isEmpty)
    }

    func testUnknownKindHasFallbackSystemImage() {
        XCTAssertEqual(SymbolKindLabel.systemImage(for: 0), "smallcircle.filled.circle")
    }
}
