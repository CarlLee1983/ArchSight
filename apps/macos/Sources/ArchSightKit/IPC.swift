import Foundation

public enum IPCMethod: String, Codable, Sendable {
    case health
    case openWorkspace
    case addRoots
    case removeRoot
    case listTree
    case openFile
    case search
    case definition
    case references
    case documentSymbol
    case cancel
}

public struct EmptyParams: Codable, Equatable, Sendable {
    public init() {}
}

public struct IPCRequest<Params: Encodable & Sendable>: Encodable, Sendable {
    public let id: String
    public let method: IPCMethod
    public let params: Params

    public init(id: String, method: IPCMethod, params: Params) {
        self.id = id
        self.method = method
        self.params = params
    }
}

extension IPCRequest where Params == EmptyParams {
    public init(id: String, method: IPCMethod) {
        self.init(id: id, method: method, params: EmptyParams())
    }
}

public struct OpenWorkspaceParams: Encodable, Equatable, Sendable {
    public let roots: [String]

    public init(roots: [String]) {
        self.roots = roots
    }
}

public struct AddRootsParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let roots: [String]

    public init(workspaceId: String, roots: [String]) {
        self.workspaceId = workspaceId
        self.roots = roots
    }
}

public struct RemoveRootParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let rootId: String

    public init(workspaceId: String, rootId: String) {
        self.workspaceId = workspaceId
        self.rootId = rootId
    }
}

public struct ListTreeParams: Encodable, Equatable, Sendable {
    public let workspaceId: String

    public init(workspaceId: String) {
        self.workspaceId = workspaceId
    }
}

public struct OpenFileParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let rootId: String
    public let path: String

    public init(workspaceId: String, rootId: String, path: String) {
        self.workspaceId = workspaceId
        self.rootId = rootId
        self.path = path
    }
}

public struct SearchParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let pattern: String

    public init(workspaceId: String, pattern: String) {
        self.workspaceId = workspaceId
        self.pattern = pattern
    }
}

public struct NavigationParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let rootId: String
    public let path: String
    public let line: Int
    public let column: Int

    public init(workspaceId: String, rootId: String, path: String, line: Int, column: Int) {
        self.workspaceId = workspaceId
        self.rootId = rootId
        self.path = path
        self.line = line
        self.column = column
    }
}

public struct DocumentSymbolParams: Encodable, Equatable, Sendable {
    public let workspaceId: String
    public let rootId: String
    public let path: String

    public init(workspaceId: String, rootId: String, path: String) {
        self.workspaceId = workspaceId
        self.rootId = rootId
        self.path = path
    }
}

public struct IPCResponse<Result: Decodable>: Decodable {
    public let id: String
    public let ok: Bool
    public let result: Result?
    public let error: IPCErrorShape?
}

public struct IPCErrorShape: Decodable, Equatable, Sendable {
    public let code: String
    public let message: String
}

public enum IPCCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static func encode<Params: Encodable & Sendable>(_ request: IPCRequest<Params>) throws -> Data {
        var data = try encoder.encode(request)
        data.append(0x0A)
        return data
    }

    public static func decodeResponse<Result: Decodable>(
        _ resultType: Result.Type,
        from data: Data
    ) throws -> IPCResponse<Result> {
        try JSONDecoder().decode(IPCResponse<Result>.self, from: data)
    }
}

public struct WorkspaceRoot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public struct OpenWorkspaceResult: Decodable, Equatable, Sendable {
    public let workspaceId: String
    public let status: String
    public let roots: [WorkspaceRoot]
}

public struct WorkspaceEntry: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { rootId + ":" + path }
    public let rootId: String
    public let rootPath: String
    public let path: String
    public let name: String
    public let kind: String

    public var isDirectory: Bool { kind == "directory" }

    public init(rootId: String, rootPath: String, path: String, name: String, kind: String) {
        self.rootId = rootId
        self.rootPath = rootPath
        self.path = path
        self.name = name
        self.kind = kind
    }
}

public struct ListTreeResult: Decodable, Equatable, Sendable {
    public let workspaceId: String
    public let status: String
    public let roots: [WorkspaceRoot]
    public let entries: [WorkspaceEntry]
    public let error: String?
}

public struct SyntaxToken: Decodable, Equatable, Sendable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
    public let type: String
}

public struct OpenFileResult: Decodable, Equatable, Sendable {
    public let rootId: String
    public let rootPath: String
    public let path: String
    public let language: String
    public let content: String
    public let tokens: [SyntaxToken]
}

public struct SearchRange: Decodable, Equatable, Sendable {
    public let start: Int
    public let end: Int
}

public struct SearchMatch: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { rootId + ":" + path + ":" + String(line) + ":" + String(column) }
    public let rootId: String
    public let rootPath: String
    public let path: String
    public let line: Int
    public let column: Int
    public let preview: String
    public let ranges: [SearchRange]
}

public struct SearchResult: Decodable, Equatable, Sendable {
    public let matches: [SearchMatch]
}

public struct Location: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(rootId):\(path):\(startLine):\(startColumn)" }
    public let rootId: String
    public let rootPath: String
    public let path: String
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(
        rootId: String,
        rootPath: String,
        path: String,
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int
    ) {
        self.rootId = rootId
        self.rootPath = rootPath
        self.path = path
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

public struct NavigationResult: Decodable, Equatable, Sendable {
    public let locations: [Location]

    public init(locations: [Location]) {
        self.locations = locations
    }
}

/// One entry of a file's outline, as returned by the core's documentSymbol.
/// `depth` is 0 for top-level symbols and increases with nesting.
public struct DocumentSymbol: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(line):\(column):\(name)" }
    public let name: String
    public let kind: Int
    public let detail: String?
    public let line: Int
    public let column: Int
    public let depth: Int

    public init(name: String, kind: Int, detail: String? = nil, line: Int, column: Int, depth: Int = 0) {
        self.name = name
        self.kind = kind
        self.detail = detail
        self.line = line
        self.column = column
        self.depth = depth
    }
}

public struct DocumentSymbolResult: Decodable, Equatable, Sendable {
    public let symbols: [DocumentSymbol]

    public init(symbols: [DocumentSymbol]) {
        self.symbols = symbols
    }
}
