import Foundation

/// Coordinates the read-only observation workflow against the out-of-process core:
/// open a workspace, wait for the asynchronous scan to settle, list the flattened
/// tree, open files, and run searches. All calls are synchronous and blocking, so
/// the UI layer is expected to invoke them off the main thread.
public final class WorkspaceController {
    private let client: CoreServicing
    private let pollLimit: Int
    private let sleep: () -> Void

    public init(
        client: CoreServicing,
        pollLimit: Int = 200,
        sleep: @escaping () -> Void = { usleep(50_000) }
    ) {
        self.client = client
        self.pollLimit = pollLimit
        self.sleep = sleep
    }

    /// Opens a fresh workspace snapshot for the given root paths and polls the
    /// flattened tree until the scan reaches a terminal state.
    @discardableResult
    public func openWorkspace(paths: [String]) throws -> ListTreeResult {
        let opened = try client.openWorkspace(roots: paths)

        for _ in 0..<pollLimit {
            let tree = try client.listTree(workspaceId: opened.workspaceId)
            switch tree.status {
            case "scanning":
                sleep()
            case "failed":
                throw CoreClientError(code: "workspace_failed", message: tree.error ?? "Workspace scan failed")
            default:
                return tree
            }
        }

        throw CoreClientError(code: "workspace_timeout", message: "Workspace scan did not finish in time")
    }

    /// Loads a single file's read-only content as a tab.
    public func loadFile(workspaceId: String, rootId: String, path: String) throws -> FileTab {
        let file = try client.openFile(workspaceId: workspaceId, rootId: rootId, path: path)
        return FileTab(rootID: file.rootId, path: file.path, content: file.content, tokens: file.tokens)
    }

    /// Runs a full-text search and returns the accumulated matches.
    public func search(workspaceId: String, pattern: String) throws -> [SearchMatch] {
        try client.search(workspaceId: workspaceId, pattern: pattern).matches
    }

    /// Resolves the definition location(s) for the symbol at the given position.
    public func definition(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> [Location] {
        try client.definition(workspaceId: workspaceId, rootId: rootId, path: path, line: line, column: column).locations
    }

    /// Resolves the reference location(s) for the symbol at the given position.
    public func references(workspaceId: String, rootId: String, path: String, line: Int, column: Int) throws -> [Location] {
        try client.references(workspaceId: workspaceId, rootId: rootId, path: path, line: line, column: column).locations
    }
}
