import XCTest
@testable import ArchSightKit

final class CoreClientTests: XCTestCase {
    func testHealthSendsRequestAndDecodesResult() throws {
        let transport = RecordingTransport(responseLine: """
        {"id":"req_health","ok":true,"result":{"version":"0.1.0","pid":42}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_health" })

        let health = try client.health()

        XCTAssertEqual(health.version, "0.1.0")
        XCTAssertEqual(health.pid, 42)
        XCTAssertEqual(transport.sentLines.count, 1)
        XCTAssertTrue(transport.sentLines[0].contains("\"method\":\"health\""))
    }

    func testHealthThrowsStructuredIPCError() {
        let transport = RecordingTransport(responseLine: """
        {"id":"req_health","ok":false,"error":{"code":"unsupported_method","message":"Unsupported method: health"}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_health" })

        XCTAssertThrowsError(try client.health()) { error in
            guard let ipcError = error as? CoreClientError else {
                return XCTFail("expected CoreClientError, got \(type(of: error))")
            }
            XCTAssertEqual(ipcError.code, "unsupported_method")
        }
    }
}

private final class RecordingTransport: CoreTransport {
    private let responseLine: String
    private(set) var sentLines: [String] = []

    init(responseLine: String) {
        self.responseLine = responseLine
    }

    func roundTrip(_ request: Data) throws -> Data {
        if let line = String(data: request, encoding: .utf8) {
            sentLines.append(line)
        }
        return Data((responseLine + "\n").utf8)
    }
}
