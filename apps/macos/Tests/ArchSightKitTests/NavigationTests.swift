import XCTest
@testable import ArchSightKit

final class NavigationTests: XCTestCase {
    // MARK: - IPC envelope

    func testDecodesDefinitionResponseLocations() throws {
        let line = """
        {"id":"req_def","ok":true,"result":{"locations":[{"rootId":"root_1","rootPath":"/tmp/a","path":"lib.go","startLine":10,"startColumn":6,"endLine":10,"endColumn":12}]}}
        """

        let response = try IPCCodec.decodeResponse(NavigationResult.self, from: Data(line.utf8))

        XCTAssertEqual(response.result?.locations.count, 1)
        let location = try XCTUnwrap(response.result?.locations.first)
        XCTAssertEqual(location.path, "lib.go")
        XCTAssertEqual(location.startLine, 10)
        XCTAssertEqual(location.startColumn, 6)
    }

    func testEncodesDefinitionRequestWithPosition() throws {
        let request = IPCRequest(
            id: "req_def",
            method: .definition,
            params: NavigationParams(workspaceId: "ws_1", rootId: "root_1", path: "main.go", line: 3, column: 5)
        )

        let data = try IPCCodec.encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"method\":\"definition\""))
        XCTAssertTrue(json.contains("\"line\":3"))
        XCTAssertTrue(json.contains("\"column\":5"))
        XCTAssertTrue(json.contains("\"path\":\"main.go\""))
    }

    // MARK: - CoreClient

    func testClientDefinitionSendsPositionAndDecodes() throws {
        let transport = StubTransport(responseLine: """
        {"id":"req_1","ok":true,"result":{"locations":[{"rootId":"root_1","rootPath":"/tmp/a","path":"lib.go","startLine":7,"startColumn":1,"endLine":7,"endColumn":4}]}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_1" })

        let result = try client.definition(workspaceId: "ws_1", rootId: "root_1", path: "main.go", line: 3, column: 5)

        XCTAssertEqual(result.locations.first?.path, "lib.go")
        XCTAssertTrue(transport.sentLines[0].contains("\"method\":\"definition\""))
        XCTAssertTrue(transport.sentLines[0].contains("\"column\":5"))
    }

    func testClientReferencesSendsPositionAndDecodes() throws {
        let transport = StubTransport(responseLine: """
        {"id":"req_1","ok":true,"result":{"locations":[{"rootId":"root_1","rootPath":"/tmp/a","path":"a.go","startLine":1,"startColumn":1,"endLine":1,"endColumn":2},{"rootId":"root_1","rootPath":"/tmp/a","path":"b.go","startLine":2,"startColumn":1,"endLine":2,"endColumn":2}]}}
        """)
        let client = CoreClient(transport: transport, idGenerator: { "req_1" })

        let result = try client.references(workspaceId: "ws_1", rootId: "root_1", path: "main.go", line: 3, column: 5)

        XCTAssertEqual(result.locations.count, 2)
        XCTAssertTrue(transport.sentLines[0].contains("\"method\":\"references\""))
    }

    // MARK: - WorkspaceController

    func testControllerDefinitionReturnsLocations() throws {
        let client = StubServicing()
        client.navigationResult = NavigationResult(locations: [
            Location(rootId: "root_1", rootPath: "/tmp/a", path: "lib.go", startLine: 9, startColumn: 2, endLine: 9, endColumn: 8)
        ])
        let controller = WorkspaceController(client: client, pollLimit: 5, sleep: {})

        let locations = try controller.definition(workspaceId: "ws_1", rootId: "root_1", path: "main.go", line: 3, column: 5)

        XCTAssertEqual(locations.first?.path, "lib.go")
        XCTAssertEqual(client.definitionCalls.first?.line, 3)
    }

    func testControllerReferencesReturnsLocations() throws {
        let client = StubServicing()
        client.navigationResult = NavigationResult(locations: [
            Location(rootId: "root_1", rootPath: "/tmp/a", path: "a.go", startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)
        ])
        let controller = WorkspaceController(client: client, pollLimit: 5, sleep: {})

        let locations = try controller.references(workspaceId: "ws_1", rootId: "root_1", path: "main.go", line: 3, column: 5)

        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(client.referencesCalls.first?.column, 5)
    }
}

private final class StubTransport: CoreTransport {
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

private final class StubServicing: CoreServicing {
    var navigationResult = NavigationResult(locations: [])
    private(set) var definitionCalls: [(rootId: String, path: String, line: Int, column: Int)] = []
    private(set) var referencesCalls: [(rootId: String, path: String, line: Int, column: Int)] = []

    func openWorkspace(roots: [String]) throws -> OpenWorkspaceResult {
        OpenWorkspaceResult(workspaceId: "ws_1", status: "ready", roots: [])
    }

    func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult {
        OpenWorkspaceResult(workspaceId: workspaceId, status: "ready", roots: [])
    }

    func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult {
        ListTreeResult(workspaceId: workspaceId, status: "ready", roots: [], entries: [], error: nil)
    }

    func listTree(workspaceId: String) throws -> ListTreeResult {
        ListTreeResult(workspaceId: workspaceId, status: "ready", roots: [], entries: [], error: nil)
    }

    func openFile(workspaceId: String, rootId: String, path: String) throws -> OpenFileResult {
        OpenFileResult(rootId: rootId, rootPath: "", path: path, language: "", content: "", tokens: [])
    }

    func search(workspaceId: String, pattern: String) throws -> SearchResult {
        SearchResult(matches: [])
    }

    func definition(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult {
        definitionCalls.append((rootId, path, line, column))
        return navigationResult
    }

    func references(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult {
        referencesCalls.append((rootId, path, line, column))
        return navigationResult
    }

    func documentSymbol(workspaceId: String, rootId: String, path: String) throws -> DocumentSymbolResult {
        DocumentSymbolResult(symbols: [])
    }
}
