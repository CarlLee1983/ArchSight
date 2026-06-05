import XCTest
@testable import ArchSightKit

final class FileSystemPathsTests: XCTestCase {
    func testRelativeReturnsChildName() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b/c.txt", under: "/a/b"), "c.txt")
    }

    func testRelativeReturnsNestedPath() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b/sub/c.txt", under: "/a/b"), "sub/c.txt")
    }

    func testRelativeToleratesTrailingSlashRoot() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b/c.txt", under: "/a/b/"), "c.txt")
    }

    func testRelativeOfRootItselfIsEmpty() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/b", under: "/a/b"), "")
    }

    func testRelativeFallsBackToOriginalWhenNotUnderRoot() {
        XCTAssertEqual(FileSystemPaths.relative(of: "/x/y", under: "/a/b"), "/x/y")
    }

    func testRelativeDoesNotMatchSiblingPrefix() {
        // "/a/bc" must not be treated as living under "/a/b".
        XCTAssertEqual(FileSystemPaths.relative(of: "/a/bc/d.txt", under: "/a/b"), "/a/bc/d.txt")
    }
}
