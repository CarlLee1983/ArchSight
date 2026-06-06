import XCTest
@testable import ArchSightKit

final class PathBreadcrumbsTests: XCTestCase {
    func testSplitsWorkspaceRelativePath() {
        XCTAssertEqual(
            PathBreadcrumbs.segments(for: "apps/macos/Main.swift"),
            ["apps", "macos", "Main.swift"]
        )
    }

    func testDropsEmptyComponentsFromLeadingAndDoubledSlashes() {
        XCTAssertEqual(PathBreadcrumbs.segments(for: "/a//b/"), ["a", "b"])
    }

    func testSingleFileHasOneSegment() {
        XCTAssertEqual(PathBreadcrumbs.segments(for: "README.md"), ["README.md"])
    }

    func testEmptyPathHasNoSegments() {
        XCTAssertTrue(PathBreadcrumbs.segments(for: "").isEmpty)
    }
}
