import XCTest
@testable import ArchSightKit

final class IPCEnvelopeTests: XCTestCase {
    func testEncodesHealthRequestAsNewlineDelimitedJSON() throws {
        let request = IPCRequest(id: "req_health", method: .health)

        let data = try IPCCodec.encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.hasSuffix("\n"))
        XCTAssertTrue(json.contains("\"id\":\"req_health\""))
        XCTAssertTrue(json.contains("\"method\":\"health\""))
        XCTAssertTrue(json.contains("\"params\":{}"))
    }

    func testDecodesOpenWorkspaceResponse() throws {
        let line = """
        {"id":"req_open","ok":true,"result":{"workspaceId":"ws_1","status":"scanning","roots":[{"id":"root_1","name":"service","path":"/tmp/service"}]}}
        """

        let response = try IPCCodec.decodeResponse(OpenWorkspaceResult.self, from: Data(line.utf8))

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result?.workspaceId, "ws_1")
        XCTAssertEqual(response.result?.roots.first?.id, "root_1")
    }

    func testEncodesOpenWorkspaceRequestWithRootParams() throws {
        let request = IPCRequest(
            id: "req_open",
            method: .openWorkspace,
            params: OpenWorkspaceParams(roots: ["/tmp/a", "/tmp/b"])
        )

        let data = try IPCCodec.encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.hasSuffix("\n"))
        XCTAssertTrue(json.contains("\"method\":\"openWorkspace\""))
        XCTAssertTrue(json.contains("\"params\":{\"roots\":[\"/tmp/a\",\"/tmp/b\"]}"))
    }

    func testDecodesListTreeResponseWithFlattenedEntries() throws {
        let line = """
        {"id":"req_tree","ok":true,"result":{"workspaceId":"ws_1","status":"ready","roots":[{"id":"root_1","name":"service","path":"/tmp/service"}],"entries":[{"rootId":"root_1","rootPath":"/tmp/service","path":"Sources/App.swift","name":"App.swift","kind":"file"},{"rootId":"root_1","rootPath":"/tmp/service","path":"Sources","name":"Sources","kind":"directory"}]}}
        """

        let response = try IPCCodec.decodeResponse(ListTreeResult.self, from: Data(line.utf8))

        XCTAssertEqual(response.result?.status, "ready")
        XCTAssertEqual(response.result?.entries.count, 2)
        XCTAssertEqual(response.result?.entries.first?.path, "Sources/App.swift")
        XCTAssertEqual(response.result?.entries.first?.kind, "file")
        XCTAssertNil(response.result?.error)
    }

    func testDecodesOpenFileResponseWithTokens() throws {
        let line = """
        {"id":"req_file","ok":true,"result":{"rootId":"root_1","rootPath":"/tmp/service","path":"Sources/App.swift","language":"swift","content":"import SwiftUI\\n","tokens":[{"startLine":1,"startColumn":1,"endLine":1,"endColumn":7,"type":"keyword"}]}}
        """

        let response = try IPCCodec.decodeResponse(OpenFileResult.self, from: Data(line.utf8))

        XCTAssertEqual(response.result?.language, "swift")
        XCTAssertEqual(response.result?.content, "import SwiftUI\n")
        XCTAssertEqual(response.result?.tokens.first?.type, "keyword")
        XCTAssertEqual(response.result?.tokens.first?.endColumn, 7)
    }

    func testDecodesSearchResponseWithMatches() throws {
        let line = """
        {"id":"req_search","ok":true,"result":{"matches":[{"rootId":"root_1","rootPath":"/tmp/service","path":"Sources/App.swift","line":3,"column":5,"preview":"let value = 1","ranges":[{"start":4,"end":9}]}]}}
        """

        let response = try IPCCodec.decodeResponse(SearchResult.self, from: Data(line.utf8))

        XCTAssertEqual(response.result?.matches.count, 1)
        XCTAssertEqual(response.result?.matches.first?.line, 3)
        XCTAssertEqual(response.result?.matches.first?.preview, "let value = 1")
        XCTAssertEqual(response.result?.matches.first?.ranges.first?.end, 9)
    }
}
