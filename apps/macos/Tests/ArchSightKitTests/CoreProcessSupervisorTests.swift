import XCTest
@testable import ArchSightKit

final class CoreProcessSupervisorTests: XCTestCase {
    func testBuildsCoreLaunchPlanWithoutStartingOnConstruction() {
        let supervisor = CoreProcessSupervisor(
            coreExecutable: URL(fileURLWithPath: "/tmp/archsight-core"),
            socketDirectory: URL(fileURLWithPath: "/tmp/archsight-sockets", isDirectory: true)
        )

        XCTAssertFalse(supervisor.isRunning)
        XCTAssertEqual(supervisor.launchPlan.executable.path, "/tmp/archsight-core")
        XCTAssertTrue(supervisor.launchPlan.socketPath.hasSuffix("archsight-core.sock"))
    }

    func testStopMarksSupervisorNotRunning() throws {
        let supervisor = CoreProcessSupervisor(
            coreExecutable: URL(fileURLWithPath: "/tmp/archsight-core"),
            socketDirectory: URL(fileURLWithPath: "/tmp/archsight-sockets", isDirectory: true)
        )

        supervisor.stop()

        XCTAssertFalse(supervisor.isRunning)
    }
}
