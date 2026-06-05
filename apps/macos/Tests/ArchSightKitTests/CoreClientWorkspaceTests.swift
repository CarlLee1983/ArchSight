import XCTest
@testable import ArchSightKit

final class CoreClientWorkspaceTests: XCTestCase {
    func testOpenWorkspaceSendsRootsAndDecodesResult() throws {
        let transport = ScriptedTransport(responseLine: """
        {"id":"req_1","ok":true,"result":{"workspaceId":"ws_1","status":"scanning","roots":[{"id":"root_1","name":"a","path":"/tmp/a"}]}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_1" })

        let result = try client.openWorkspace(roots: ["/tmp/a"])

        XCTAssertEqual(result.workspaceId, "ws_1")
        XCTAssertEqual(result.status, "scanning")
        XCTAssertEqual(transport.sentLines.count, 1)
        XCTAssertTrue(transport.sentLines[0].contains("\"method\":\"openWorkspace\""))
        XCTAssertTrue(transport.sentLines[0].contains("\"roots\":[\"/tmp/a\"]"))
    }

    func testListTreeSendsWorkspaceIdAndDecodesEntries() throws {
        let transport = ScriptedTransport(responseLine: """
        {"id":"req_1","ok":true,"result":{"workspaceId":"ws_1","status":"ready","roots":[],"entries":[{"rootId":"root_1","rootPath":"/tmp/a","path":"main.go","name":"main.go","kind":"file"}]}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_1" })

        let result = try client.listTree(workspaceId: "ws_1")

        XCTAssertEqual(result.status, "ready")
        XCTAssertEqual(result.entries.first?.path, "main.go")
        XCTAssertTrue(transport.sentLines[0].contains("\"method\":\"listTree\""))
        XCTAssertTrue(transport.sentLines[0].contains("\"workspaceId\":\"ws_1\""))
    }

    func testOpenFileSendsTargetAndDecodesContent() throws {
        let transport = ScriptedTransport(responseLine: """
        {"id":"req_1","ok":true,"result":{"rootId":"root_1","rootPath":"/tmp/a","path":"main.go","language":"go","content":"package main\\n","tokens":[]}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_1" })

        let result = try client.openFile(workspaceId: "ws_1", rootId: "root_1", path: "main.go")

        XCTAssertEqual(result.content, "package main\n")
        XCTAssertEqual(result.language, "go")
        let sent = transport.sentLines[0]
        XCTAssertTrue(sent.contains("\"method\":\"openFile\""))
        XCTAssertTrue(sent.contains("\"workspaceId\":\"ws_1\""))
        XCTAssertTrue(sent.contains("\"rootId\":\"root_1\""))
        XCTAssertTrue(sent.contains("\"path\":\"main.go\""))
    }

    func testSearchSendsPatternAndDecodesMatches() throws {
        let transport = ScriptedTransport(responseLine: """
        {"id":"req_1","ok":true,"result":{"matches":[{"rootId":"root_1","rootPath":"/tmp/a","path":"main.go","line":2,"column":3,"preview":"func main","ranges":[{"start":0,"end":4}]}]}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_1" })

        let result = try client.search(workspaceId: "ws_1", pattern: "func")

        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.matches.first?.path, "main.go")
        let sent = transport.sentLines[0]
        XCTAssertTrue(sent.contains("\"method\":\"search\""))
        XCTAssertTrue(sent.contains("\"pattern\":\"func\""))
    }

    func testSearchPropagatesStructuredIPCError() {
        let transport = ScriptedTransport(responseLine: """
        {"id":"req_1","ok":false,"error":{"code":"invalid_pattern","message":"bad regex"}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_1" })

        XCTAssertThrowsError(try client.search(workspaceId: "ws_1", pattern: "(")) { error in
            guard let ipcError = error as? CoreClientError else {
                return XCTFail("expected CoreClientError, got \(type(of: error))")
            }
            XCTAssertEqual(ipcError.code, "invalid_pattern")
        }
    }
}

private final class ScriptedTransport: CoreTransport {
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
