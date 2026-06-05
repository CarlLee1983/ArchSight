import Darwin
import Foundation
import XCTest
@testable import ArchSightKit

final class UnixSocketTransportTests: XCTestCase {
    func testRoundTripsAgainstUnixDomainSocketServer() throws {
        let socketPath = "/tmp/as-\(UUID().uuidString).sock"
        let server = try TestUnixSocketServer(socketPath: socketPath) { request in
            XCTAssertTrue(request.contains("\"method\":\"health\""))
            return """
            {"id":"req_health","ok":true,"result":{"version":"test-core","pid":99}}
            """
        }
        defer {
            server.stop()
        }
        try server.start()

        let client = CoreClient(
            transport: UnixSocketTransport(socketPath: socketPath),
            idGenerator: { "req_health" }
        )

        let health = try client.health()

        XCTAssertEqual(health.version, "test-core")
        XCTAssertEqual(health.pid, 99)
    }
}

private final class TestUnixSocketServer {
    private let socketPath: String
    private let handler: @Sendable (String) -> String
    private var descriptor: Int32 = -1
    private var thread: Thread?

    init(socketPath: String, handler: @Sendable @escaping (String) -> String) throws {
        self.socketPath = socketPath
        self.handler = handler
    }

    func start() throws {
        unlink(socketPath)
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        if descriptor < 0 {
            throw POSIXSocketError(operation: "socket", errnoCode: errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        try withUnsafeMutableBytes(of: &address.sun_path) { rawPath in
            guard let base = rawPath.baseAddress else {
                throw POSIXSocketError(operation: "socket_path", errnoCode: EINVAL)
            }
            _ = socketPath.withCString { source in
                strncpy(base.assumingMemoryBound(to: CChar.self), source, rawPath.count)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bindResult < 0 {
            throw POSIXSocketError(operation: "bind", errnoCode: errno)
        }
        if listen(descriptor, 1) < 0 {
            throw POSIXSocketError(operation: "listen", errnoCode: errno)
        }

        let thread = Thread { [descriptor, handler] in
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else {
                return
            }
            defer {
                close(client)
            }
            let request = Self.readLine(from: client)
            let response = handler(request)
            _ = (response + "\n").withCString { pointer in
                Darwin.write(client, pointer, strlen(pointer))
            }
        }
        self.thread = thread
        thread.start()
    }

    func stop() {
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        unlink(socketPath)
    }

    private static func readLine(from descriptor: Int32) -> String {
        var data = Data()
        var byte = UInt8(0)
        while true {
            let count = Darwin.read(descriptor, &byte, 1)
            if count <= 0 || byte == 0x0A {
                break
            }
            data.append(byte)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
