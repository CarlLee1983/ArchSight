import Darwin
import Foundation

public protocol CoreTransport: AnyObject {
    func roundTrip(_ request: Data) throws -> Data
}

public struct HealthResult: Decodable, Equatable, Sendable {
    public let version: String
    public let pid: Int
}

public struct CoreClientError: Error, Equatable, Sendable {
    public let code: String
    public let message: String
}

public protocol CoreServicing: AnyObject {
    func openWorkspace(roots: [String]) throws -> OpenWorkspaceResult
    func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult
    func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult
    func listTree(workspaceId: String) throws -> ListTreeResult
    func openFile(workspaceId: String, rootId: String, path: String) throws -> OpenFileResult
    func search(workspaceId: String, pattern: String) throws -> SearchResult
    func definition(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult
    func references(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult
}

public final class CoreClient: CoreHealthChecking, CoreServicing {
    private let transport: CoreTransport
    private let idGenerator: () -> String

    public init(
        transport: CoreTransport,
        idGenerator: @escaping () -> String = { "req_\(UUID().uuidString)" }
    ) {
        self.transport = transport
        self.idGenerator = idGenerator
    }

    public func health() throws -> HealthResult {
        try send(.health, params: EmptyParams(), resultType: HealthResult.self)
    }

    public func openWorkspace(roots: [String]) throws -> OpenWorkspaceResult {
        try send(.openWorkspace, params: OpenWorkspaceParams(roots: roots), resultType: OpenWorkspaceResult.self)
    }

    public func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult {
        try send(
            .addRoots,
            params: AddRootsParams(workspaceId: workspaceId, roots: roots),
            resultType: OpenWorkspaceResult.self
        )
    }

    public func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult {
        try send(
            .removeRoot,
            params: RemoveRootParams(workspaceId: workspaceId, rootId: rootId),
            resultType: ListTreeResult.self
        )
    }

    public func listTree(workspaceId: String) throws -> ListTreeResult {
        try send(.listTree, params: ListTreeParams(workspaceId: workspaceId), resultType: ListTreeResult.self)
    }

    public func openFile(workspaceId: String, rootId: String, path: String) throws -> OpenFileResult {
        try send(
            .openFile,
            params: OpenFileParams(workspaceId: workspaceId, rootId: rootId, path: path),
            resultType: OpenFileResult.self
        )
    }

    public func search(workspaceId: String, pattern: String) throws -> SearchResult {
        try send(.search, params: SearchParams(workspaceId: workspaceId, pattern: pattern), resultType: SearchResult.self)
    }

    public func definition(
        workspaceId: String,
        rootId: String,
        path: String,
        line: Int,
        column: Int
    ) throws -> NavigationResult {
        try send(
            .definition,
            params: NavigationParams(workspaceId: workspaceId, rootId: rootId, path: path, line: line, column: column),
            resultType: NavigationResult.self
        )
    }

    public func references(
        workspaceId: String,
        rootId: String,
        path: String,
        line: Int,
        column: Int
    ) throws -> NavigationResult {
        try send(
            .references,
            params: NavigationParams(workspaceId: workspaceId, rootId: rootId, path: path, line: line, column: column),
            resultType: NavigationResult.self
        )
    }

    private func send<Params: Encodable & Sendable, Result: Decodable>(
        _ method: IPCMethod,
        params: Params,
        resultType: Result.Type
    ) throws -> Result {
        let request = IPCRequest(id: idGenerator(), method: method, params: params)
        let responseData = try transport.roundTrip(try IPCCodec.encode(request))
        let response = try IPCCodec.decodeResponse(resultType, from: responseData)
        if let error = response.error {
            throw CoreClientError(code: error.code, message: error.message)
        }
        guard response.ok, let result = response.result else {
            throw CoreClientError(code: "invalid_response", message: "Missing IPC result for \(method.rawValue)")
        }
        return result
    }
}

public final class UnixSocketTransport: CoreTransport {
    private let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func roundTrip(_ request: Data) throws -> Data {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        if descriptor < 0 {
            throw POSIXSocketError(operation: "socket", errnoCode: errno)
        }
        defer {
            close(descriptor)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        try withUnsafeMutableBytes(of: &address.sun_path) { rawPath in
            guard let base = rawPath.baseAddress else {
                throw POSIXSocketError(operation: "socket_path", errnoCode: EINVAL)
            }
            guard socketPath.utf8.count < rawPath.count else {
                throw POSIXSocketError(operation: "socket_path", errnoCode: ENAMETOOLONG)
            }
            _ = socketPath.withCString { source in
                strncpy(base.assumingMemoryBound(to: CChar.self), source, rawPath.count)
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        if connectResult < 0 {
            throw POSIXSocketError(operation: "connect", errnoCode: errno)
        }

        try writeAll(request, to: descriptor)
        return try readLine(from: descriptor)
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: written),
                    buffer.count - written
                )
                if count < 0 {
                    throw POSIXSocketError(operation: "write", errnoCode: errno)
                }
                written += count
            }
        }
    }

    private func readLine(from descriptor: Int32) throws -> Data {
        var data = Data()
        var byte = UInt8(0)
        while true {
            let count = Darwin.read(descriptor, &byte, 1)
            if count < 0 {
                throw POSIXSocketError(operation: "read", errnoCode: errno)
            }
            if count == 0 {
                break
            }
            data.append(byte)
            if byte == 0x0A {
                break
            }
        }
        return data
    }
}

public struct POSIXSocketError: Error, Equatable, Sendable {
    public let operation: String
    public let errnoCode: Int32

    public init(operation: String, errnoCode: Int32) {
        self.operation = operation
        self.errnoCode = errnoCode
    }
}
