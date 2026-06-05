import XCTest
@testable import ArchSightKit

final class CoreBinaryLocatorTests: XCTestCase {
    private let resources = URL(fileURLWithPath: "/app/ArchSight.app/Contents/Resources", isDirectory: true)
    private let executableDir = URL(fileURLWithPath: "/app/ArchSight.app/Contents/MacOS", isDirectory: true)

    func testEnvironmentOverrideWinsFirst() {
        let resolved = CoreBinaryLocator.resolve(
            environment: ["ARCHSIGHT_CORE_PATH": "/custom/archsight-core"],
            resourceDirectory: resources,
            executableDirectory: executableDir,
            fileExists: { _ in true }
        )
        XCTAssertEqual(resolved, URL(fileURLWithPath: "/custom/archsight-core"))
    }

    func testIgnoresEmptyEnvironmentOverride() {
        let bundled = resources
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("archsight-core")
        let resolved = CoreBinaryLocator.resolve(
            environment: ["ARCHSIGHT_CORE_PATH": ""],
            resourceDirectory: resources,
            executableDirectory: executableDir,
            fileExists: { $0 == bundled.path }
        )
        XCTAssertEqual(resolved, bundled)
    }

    func testResolvesBundledBinary() {
        let bundled = resources
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("archsight-core")
        let resolved = CoreBinaryLocator.resolve(
            environment: [:],
            resourceDirectory: resources,
            executableDirectory: executableDir,
            fileExists: { $0 == bundled.path }
        )
        XCTAssertEqual(resolved, bundled)
    }

    func testResolvesSiblingBinaryWhenNoBundledResource() {
        let sibling = executableDir.appendingPathComponent("archsight-core")
        let resolved = CoreBinaryLocator.resolve(
            environment: [:],
            resourceDirectory: resources,
            executableDirectory: executableDir,
            fileExists: { $0 == sibling.path }
        )
        XCTAssertEqual(resolved, sibling)
    }

    func testReturnsNilWhenNothingFound() {
        let resolved = CoreBinaryLocator.resolve(
            environment: [:],
            resourceDirectory: resources,
            executableDirectory: executableDir,
            fileExists: { _ in false }
        )
        XCTAssertNil(resolved)
    }
}
