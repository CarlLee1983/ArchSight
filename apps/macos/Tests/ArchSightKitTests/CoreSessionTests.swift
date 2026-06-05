import Foundation
import XCTest
@testable import ArchSightKit

final class CoreSessionTests: XCTestCase {
    func testConnectStartsCoreAndChecksHealth() throws {
        let supervisor = FakeCoreSupervisor(socketPath: "/tmp/archsight-core.sock")
        let session = CoreSession(
            supervisor: supervisor,
            clientFactory: { socketPath in
                XCTAssertEqual(socketPath, "/tmp/archsight-core.sock")
                return FakeCoreHealthChecking(version: "0.1.0", pid: 42)
            }
        )

        let health = try session.connect()

        XCTAssertEqual(health.version, "0.1.0")
        XCTAssertEqual(health.pid, 42)
        XCTAssertTrue(supervisor.didStart)
        XCTAssertEqual(session.status, .connected(health))
    }

    func testDisconnectStopsCoreAndClearsStatus() throws {
        let supervisor = FakeCoreSupervisor(socketPath: "/tmp/archsight-core.sock")
        let session = CoreSession(
            supervisor: supervisor,
            clientFactory: { _ in FakeCoreHealthChecking(version: "0.1.0", pid: 42) }
        )
        _ = try session.connect()

        session.disconnect()

        XCTAssertTrue(supervisor.didStop)
        XCTAssertEqual(session.status, .disconnected)
    }

    func testConnectFailureStopsCoreAndRecordsFailedStatus() {
        let supervisor = FakeCoreSupervisor(socketPath: "/tmp/archsight-core.sock")
        let session = CoreSession(
            supervisor: supervisor,
            clientFactory: { _ in ThrowingCoreHealthChecking() }
        )

        XCTAssertThrowsError(try session.connect())
        XCTAssertTrue(supervisor.didStop)
        guard case .failed(let message) = session.status else {
            return XCTFail("expected failed status, got \(session.status)")
        }
        XCTAssertTrue(message.contains("boom"))
    }

    func testConnectRetriesTransientHealthFailuresWhileCoreStarts() throws {
        let supervisor = FakeCoreSupervisor(socketPath: "/tmp/archsight-core.sock")
        let healthChecker = TransientCoreHealthChecking(failuresBeforeSuccess: 2)
        let session = CoreSession(
            supervisor: supervisor,
            clientFactory: { _ in healthChecker },
            healthRetryLimit: 5,
            healthRetryDelay: {}
        )

        let health = try session.connect()

        XCTAssertEqual(health.version, "0.1.0")
        XCTAssertEqual(healthChecker.attempts, 3)
        XCTAssertTrue(supervisor.didStart)
        XCTAssertFalse(supervisor.didStop)
        XCTAssertEqual(session.status, .connected(health))
    }

    func testFactoryReturnsNilWithoutCorePath() {
        let session = CoreSessionFactory.fromEnvironment(environment: [:], coreExecutable: nil)

        XCTAssertNil(session)
    }

    func testFactoryBuildsSessionWhenCoreResolved() {
        let session = CoreSessionFactory.fromEnvironment(
            environment: [:],
            coreExecutable: URL(fileURLWithPath: "/resolved/archsight-core")
        )

        XCTAssertNotNil(session)
    }
}

private final class FakeCoreSupervisor: CoreSupervising {
    let socketPath: String
    private(set) var didStart = false
    private(set) var didStop = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws -> Process {
        didStart = true
        return Process()
    }

    func stop() {
        didStop = true
    }
}

private final class FakeCoreHealthChecking: CoreHealthChecking {
    private let version: String
    private let pid: Int

    init(version: String, pid: Int) {
        self.version = version
        self.pid = pid
    }

    func health() throws -> HealthResult {
        HealthResult(version: version, pid: pid)
    }
}

private final class ThrowingCoreHealthChecking: CoreHealthChecking {
    func health() throws -> HealthResult {
        throw CoreClientError(code: "test", message: "boom")
    }
}

private final class TransientCoreHealthChecking: CoreHealthChecking {
    private let failuresBeforeSuccess: Int
    private(set) var attempts = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func health() throws -> HealthResult {
        attempts += 1
        if attempts <= failuresBeforeSuccess {
            throw CoreClientError(code: "connect", message: "socket not ready")
        }
        return HealthResult(version: "0.1.0", pid: 42)
    }
}
