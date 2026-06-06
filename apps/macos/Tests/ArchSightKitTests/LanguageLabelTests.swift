import XCTest
@testable import ArchSightKit

final class LanguageLabelTests: XCTestCase {
    func testKnownExtensionsMapToDisplayNames() {
        XCTAssertEqual(LanguageLabel.forPath("src/main.swift"), "Swift")
        XCTAssertEqual(LanguageLabel.forPath("core/server.go"), "Go")
        XCTAssertEqual(LanguageLabel.forPath("app/index.tsx"), "TypeScript JSX")
        XCTAssertEqual(LanguageLabel.forPath("README.md"), "Markdown")
        XCTAssertEqual(LanguageLabel.forPath("config.yml"), "YAML")
    }

    func testIsCaseInsensitiveOnExtension() {
        XCTAssertEqual(LanguageLabel.forPath("Main.SWIFT"), "Swift")
    }

    func testUnknownExtensionFallsBackToUppercasedExtension() {
        XCTAssertEqual(LanguageLabel.forPath("data.parquet"), "PARQUET")
    }

    func testNoExtensionIsPlainText() {
        XCTAssertEqual(LanguageLabel.forPath("LICENSE"), "Plain Text")
        XCTAssertEqual(LanguageLabel.forPath("path/to/Makefile"), "Plain Text")
    }
}
