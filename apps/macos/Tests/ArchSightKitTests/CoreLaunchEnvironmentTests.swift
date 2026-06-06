import XCTest
@testable import ArchSightKit

final class CoreLaunchEnvironmentTests: XCTestCase {
    private func paths(_ env: [String: String]) -> [String] {
        (env["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    func testAppendsCommonToolDirectoriesToMinimalFinderPath() {
        let env = CoreLaunchEnvironment.resolvedEnvironment(
            base: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            home: "/Users/example"
        )

        let result = paths(env)
        XCTAssertEqual(Array(result.prefix(4)), ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        XCTAssertTrue(result.contains("/opt/homebrew/bin"))
        XCTAssertTrue(result.contains("/usr/local/bin"))
        XCTAssertTrue(result.contains("/Users/example/go/bin"))
    }

    func testPreservesExistingEntriesOrderAndDoesNotDuplicate() {
        let env = CoreLaunchEnvironment.resolvedEnvironment(
            base: ["PATH": "/opt/homebrew/bin:/usr/bin"],
            home: "/Users/example"
        )

        let result = paths(env)
        XCTAssertEqual(result.first, "/opt/homebrew/bin", "existing entry keeps priority")
        XCTAssertEqual(result.filter { $0 == "/opt/homebrew/bin" }.count, 1, "no duplicates")
        XCTAssertEqual(result.firstIndex(of: "/opt/homebrew/bin"), 0)
    }

    func testHonorsCustomGopath() {
        let env = CoreLaunchEnvironment.resolvedEnvironment(
            base: ["PATH": "/usr/bin", "GOPATH": "/custom/gopath"],
            home: "/Users/example"
        )

        XCTAssertTrue(paths(env).contains("/custom/gopath/bin"))
    }

    func testPreservesOtherEnvironmentVariables() {
        let env = CoreLaunchEnvironment.resolvedEnvironment(
            base: ["PATH": "/usr/bin", "ARCHSIGHT_SOCKET_DIR": "/tmp/x", "HOME": "/Users/example"],
            home: "/Users/example"
        )

        XCTAssertEqual(env["ARCHSIGHT_SOCKET_DIR"], "/tmp/x")
        XCTAssertEqual(env["HOME"], "/Users/example")
    }

    func testHandlesEmptyBasePath() {
        let env = CoreLaunchEnvironment.resolvedEnvironment(base: [:], home: "/Users/example")

        let result = paths(env)
        XCTAssertTrue(result.contains("/opt/homebrew/bin"))
        XCTAssertFalse(result.contains(""), "no empty path segments")
    }
}
