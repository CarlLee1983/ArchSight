import XCTest
@testable import ArchSightKit

final class WorkspaceControllerTests: XCTestCase {
    func testOpenWorkspacePollsListTreeUntilReady() throws {
        let client = FakeCoreClient()
        client.openResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
        client.listTreeResults = [
            makeTree(status: "scanning", entries: []),
            makeTree(status: "scanning", entries: []),
            makeTree(status: "ready", entries: [makeEntry(path: "main.go", kind: "file")]),
        ]
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        let result = try controller.openWorkspace(paths: ["/tmp/a"])

        XCTAssertEqual(result.workspaceId, "ws_1")
        XCTAssertEqual(result.status, "ready")
        XCTAssertEqual(result.entries.first?.path, "main.go")
        XCTAssertEqual(client.openCalls, [["/tmp/a"]])
        XCTAssertEqual(client.listTreeCalls, ["ws_1", "ws_1", "ws_1"])
    }

    func testOpenWorkspaceReturnsImmediatelyWhenAlreadyReady() throws {
        let client = FakeCoreClient()
        client.openResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
        client.listTreeResults = [makeTree(status: "ready", entries: [])]
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        _ = try controller.openWorkspace(paths: ["/tmp/a"])

        XCTAssertEqual(client.listTreeCalls.count, 1)
    }

    func testOpenWorkspaceThrowsOnFailedStatus() {
        let client = FakeCoreClient()
        client.openResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
        client.listTreeResults = [makeTree(status: "failed", entries: [], error: "permission denied")]
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        XCTAssertThrowsError(try controller.openWorkspace(paths: ["/tmp/a"])) { error in
            guard let ipcError = error as? CoreClientError else {
                return XCTFail("expected CoreClientError, got \(type(of: error))")
            }
            XCTAssertEqual(ipcError.code, "workspace_failed")
            XCTAssertEqual(ipcError.message, "permission denied")
        }
    }

    func testOpenWorkspaceThrowsTimeoutWhenNeverReady() {
        let client = FakeCoreClient()
        client.openResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
        client.listTreeResults = Array(repeating: makeTree(status: "scanning", entries: []), count: 3)
        let controller = WorkspaceController(client: client, pollLimit: 3, sleep: {})

        XCTAssertThrowsError(try controller.openWorkspace(paths: ["/tmp/a"])) { error in
            XCTAssertEqual((error as? CoreClientError)?.code, "workspace_timeout")
        }
        XCTAssertEqual(client.listTreeCalls.count, 3)
    }

    func testAddRootsPollsUntilReady() throws {
        let client = FakeCoreClient()
        client.addRootsResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
        client.listTreeResults = [
            makeTree(status: "scanning", entries: []),
            makeTree(status: "ready", entries: [makeEntry(path: "b.txt", kind: "file")]),
        ]
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        let result = try controller.addRoots(workspaceId: "ws_1", paths: ["/tmp/b"])

        XCTAssertEqual(result.status, "ready")
        XCTAssertEqual(result.entries.first?.path, "b.txt")
        XCTAssertEqual(client.addRootsCalls.first?.roots, ["/tmp/b"])
        XCTAssertEqual(client.listTreeCalls.count, 2)
    }

    func testAddRootsThrowsOnFailedStatus() {
        let client = FakeCoreClient()
        client.addRootsResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
        client.listTreeResults = [makeTree(status: "failed", entries: [], error: "index error")]
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        XCTAssertThrowsError(try controller.addRoots(workspaceId: "ws_1", paths: ["/tmp/b"])) { error in
            XCTAssertEqual((error as? CoreClientError)?.code, "workspace_failed")
        }
    }

    func testRemoveRootReturnsUpdatedTree() throws {
        let client = FakeCoreClient()
        client.removeRootResult = ListTreeResult(
            workspaceId: "ws_1",
            status: "ready",
            roots: [WorkspaceRoot(id: "root_2", name: "b", path: "/tmp/b")],
            entries: [],
            error: nil
        )
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        let result = try controller.removeRoot(workspaceId: "ws_1", rootId: "root_1")

        XCTAssertEqual(result.roots.map(\.id), ["root_2"])
        XCTAssertEqual(client.removeRootCalls.first?.rootId, "root_1")
    }

    func testLoadFileReturnsReadOnlyTab() throws {
        let client = FakeCoreClient()
        client.openFileResult = OpenFileResult(
            rootId: "root_1",
            rootPath: "/tmp/a",
            path: "main.go",
            language: "go",
            content: "package main\n",
            tokens: []
        )
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        let tab = try controller.loadFile(workspaceId: "ws_1", rootId: "root_1", path: "main.go")

        XCTAssertEqual(tab.path, "main.go")
        XCTAssertEqual(tab.content, "package main\n")
        XCTAssertTrue(tab.isReadOnly)
        XCTAssertEqual(client.openFileCalls.first?.rootId, "root_1")
    }

    func testSearchReturnsMatches() throws {
        let client = FakeCoreClient()
        client.searchResult = SearchResult(matches: [
            SearchMatch(rootId: "root_1", rootPath: "/tmp/a", path: "main.go", line: 2, column: 1, preview: "func main", ranges: [])
        ])
        let controller = WorkspaceController(client: client, pollLimit: 10, sleep: {})

        let matches = try controller.search(workspaceId: "ws_1", pattern: "func")

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.path, "main.go")
        XCTAssertEqual(client.searchCalls.first?.pattern, "func")
    }

    // MARK: - Helpers

    private func makeTree(status: String, entries: [WorkspaceEntry], error: String? = nil) -> ListTreeResult {
        ListTreeResult(workspaceId: "ws_1", status: status, roots: [], entries: entries, error: error)
    }

    private func makeEntry(path: String, kind: String) -> WorkspaceEntry {
        WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/a", path: path, name: path, kind: kind)
    }
}

private final class FakeCoreClient: CoreServicing {
    var openResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "ready", roots: [])
    var listTreeResults: [ListTreeResult] = []
    var openFileResult = OpenFileResult(rootId: "", rootPath: "", path: "", language: "", content: "", tokens: [])
    var searchResult = SearchResult(matches: [])

    private(set) var openCalls: [[String]] = []
    private(set) var listTreeCalls: [String] = []
    private(set) var openFileCalls: [(workspaceId: String, rootId: String, path: String)] = []
    private(set) var searchCalls: [(workspaceId: String, pattern: String)] = []

    var addRootsResult = OpenWorkspaceResult(workspaceId: "ws_1", status: "scanning", roots: [])
    var removeRootResult = ListTreeResult(workspaceId: "ws_1", status: "ready", roots: [], entries: [], error: nil)
    private(set) var addRootsCalls: [(workspaceId: String, roots: [String])] = []
    private(set) var removeRootCalls: [(workspaceId: String, rootId: String)] = []

    func openWorkspace(roots: [String]) throws -> OpenWorkspaceResult {
        openCalls.append(roots)
        return openResult
    }

    func addRoots(workspaceId: String, roots: [String]) throws -> OpenWorkspaceResult {
        addRootsCalls.append((workspaceId, roots))
        return addRootsResult
    }

    func removeRoot(workspaceId: String, rootId: String) throws -> ListTreeResult {
        removeRootCalls.append((workspaceId, rootId))
        return removeRootResult
    }

    func listTree(workspaceId: String) throws -> ListTreeResult {
        let index = listTreeCalls.count
        listTreeCalls.append(workspaceId)
        guard index < listTreeResults.count else {
            return listTreeResults.last ?? ListTreeResult(workspaceId: workspaceId, status: "scanning", roots: [], entries: [], error: nil)
        }
        return listTreeResults[index]
    }

    func openFile(workspaceId: String, rootId: String, path: String) throws -> OpenFileResult {
        openFileCalls.append((workspaceId, rootId, path))
        return openFileResult
    }

    func search(workspaceId: String, pattern: String) throws -> SearchResult {
        searchCalls.append((workspaceId, pattern))
        return searchResult
    }

    func definition(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult {
        NavigationResult(locations: [])
    }

    func references(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> NavigationResult {
        NavigationResult(locations: [])
    }

    func documentSymbol(workspaceId: String, rootId: String, path: String) throws -> DocumentSymbolResult {
        DocumentSymbolResult(symbols: [])
    }
}
