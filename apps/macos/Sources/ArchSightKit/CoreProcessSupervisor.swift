import Foundation

public struct CoreLaunchPlan: Equatable, Sendable {
    public let executable: URL
    public let socketPath: String

    public init(executable: URL, socketPath: String) {
        self.executable = executable
        self.socketPath = socketPath
    }
}

public final class CoreProcessSupervisor {
    public let launchPlan: CoreLaunchPlan
    private var process: Process?

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    public var socketPath: String {
        launchPlan.socketPath
    }

    public init(coreExecutable: URL, socketDirectory: URL) {
        self.launchPlan = CoreLaunchPlan(
            executable: coreExecutable,
            socketPath: socketDirectory.appendingPathComponent("archsight-core.sock").path
        )
    }

    @discardableResult
    public func start() throws -> Process {
        if let process, process.isRunning {
            return process
        }

        let process = Process()
        process.executableURL = launchPlan.executable
        process.arguments = ["--socket", launchPlan.socketPath]
        // GUI launches inherit the empty launchd PATH, which hides Homebrew/Go
        // language servers from the core's exec.LookPath. Augment it so symbol
        // navigation works from a packaged build, not just `swift run`.
        process.environment = CoreLaunchEnvironment.resolvedEnvironment()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: launchPlan.socketPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try process.run()
        self.process = process
        return process
    }

    public func stop() {
        guard let process else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    deinit {
        stop()
    }
}

extension CoreProcessSupervisor: CoreSupervising {}
