import Foundation

public protocol CoreSupervising: AnyObject {
    var socketPath: String { get }
    @discardableResult
    func start() throws -> Process
    func stop()
}

public protocol CoreHealthChecking: AnyObject {
    func health() throws -> HealthResult
}

public enum CoreSessionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(HealthResult)
    case failed(String)
}

/// A Sendable handle to the running core service socket. Constructing the blocking
/// IPC client lazily lets the UI hop work onto a background executor while only
/// passing value-typed, Sendable state across the boundary.
public struct CoreServiceEndpoint: Sendable {
    public let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func makeController() -> WorkspaceController {
        WorkspaceController(client: CoreClient(transport: UnixSocketTransport(socketPath: socketPath)))
    }
}

public final class CoreSession {
    private let supervisor: CoreSupervising
    private let clientFactory: (String) -> CoreHealthChecking
    private let healthRetryLimit: Int
    private let healthRetryDelay: () -> Void

    public private(set) var status: CoreSessionStatus = .disconnected

    public var serviceEndpoint: CoreServiceEndpoint {
        CoreServiceEndpoint(socketPath: supervisor.socketPath)
    }

    public init(
        supervisor: CoreSupervising,
        clientFactory: @escaping (String) -> CoreHealthChecking = { socketPath in
            CoreClient(transport: UnixSocketTransport(socketPath: socketPath))
        },
        healthRetryLimit: Int = 20,
        healthRetryDelay: @escaping () -> Void = { usleep(50_000) }
    ) {
        self.supervisor = supervisor
        self.clientFactory = clientFactory
        self.healthRetryLimit = healthRetryLimit
        self.healthRetryDelay = healthRetryDelay
    }

    @discardableResult
    public func connect() throws -> HealthResult {
        status = .connecting
        do {
            _ = try supervisor.start()
            let client = clientFactory(supervisor.socketPath)
            let health = try waitForHealth(client)
            status = .connected(health)
            return health
        } catch {
            supervisor.stop()
            status = .failed(String(describing: error))
            throw error
        }
    }

    public func disconnect() {
        supervisor.stop()
        status = .disconnected
    }

    private func waitForHealth(_ client: CoreHealthChecking) throws -> HealthResult {
        let attempts = max(1, healthRetryLimit)
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try client.health()
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    healthRetryDelay()
                }
            }
        }
        throw lastError ?? CoreClientError(code: "core_unavailable", message: "Core health check failed")
    }
}

public enum CoreSessionFactory {
    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        coreExecutable: URL? = CoreBinaryLocator.resolve()
    ) -> CoreSession? {
        guard let coreExecutable else {
            return nil
        }
        let socketDirectory = URL(fileURLWithPath: environment["ARCHSIGHT_SOCKET_DIR"] ?? "/tmp", isDirectory: true)
        let supervisor = CoreProcessSupervisor(
            coreExecutable: coreExecutable,
            socketDirectory: socketDirectory
        )
        return CoreSession(supervisor: supervisor)
    }
}
