import Foundation

public struct WorkspaceViewState: Equatable, Sendable {
    public var workspaceId: String?
    public var roots: [WorkspaceRoot]
    public var entries: [WorkspaceEntry]
    public var openTabs: [FileTab]
    public var selectedTabID: FileTab.ID?
    public var searchQuery: String
    public var searchResults: [SearchMatch]
    public var references: [Location]
    public var referencesContext: String?
    public var isLoading: Bool
    public var errorMessage: String?

    public let allowsEditing: Bool
    public let showsDiagnostics: Bool
    public let showsCodeActions: Bool

    public init(
        workspaceId: String? = nil,
        roots: [WorkspaceRoot] = [],
        entries: [WorkspaceEntry] = [],
        openTabs: [FileTab] = [],
        selectedTabID: FileTab.ID? = nil,
        searchQuery: String = "",
        searchResults: [SearchMatch] = [],
        references: [Location] = [],
        referencesContext: String? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.workspaceId = workspaceId
        self.roots = roots
        self.entries = entries
        self.openTabs = openTabs
        self.selectedTabID = selectedTabID
        self.searchQuery = searchQuery
        self.searchResults = searchResults
        self.references = references
        self.referencesContext = referencesContext
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.allowsEditing = false
        self.showsDiagnostics = false
        self.showsCodeActions = false
    }

    /// File entries only, preserving the flattened scan order from the core.
    public var fileEntries: [WorkspaceEntry] {
        entries.filter { !$0.isDirectory }
    }

    public func treeEntries(for root: WorkspaceRoot) -> [WorkspaceTreeNode] {
        let rootEntries = entries.filter { $0.rootId == root.id }
        var directories: [String: WorkspaceTreeNode] = [:]
        var files: [WorkspaceTreeNode] = []

        for entry in rootEntries {
            if entry.isDirectory {
                directories[entry.path] = WorkspaceTreeNode(entry: entry, children: [])
            } else {
                files.append(WorkspaceTreeNode(entry: entry, children: []))
            }
        }

        for file in files {
            let parentPath = Self.parentPath(for: file.path)
            if parentPath != nil, directories[parentPath!] == nil {
                directories[parentPath!] = WorkspaceTreeNode(
                    rootId: root.id,
                    rootPath: root.path,
                    path: parentPath!,
                    name: Self.name(for: parentPath!),
                    kind: "directory",
                    children: []
                )
            }
        }

        for path in directories.keys {
            var parent = Self.parentPath(for: path)
            while let parentPath = parent, directories[parentPath] == nil {
                directories[parentPath] = WorkspaceTreeNode(
                    rootId: root.id,
                    rootPath: root.path,
                    path: parentPath,
                    name: Self.name(for: parentPath),
                    kind: "directory",
                    children: []
                )
                parent = Self.parentPath(for: parentPath)
            }
        }

        var childrenByParent: [String?: [WorkspaceTreeNode]] = [:]
        for directory in directories.values {
            childrenByParent[Self.parentPath(for: directory.path), default: []].append(directory)
        }
        for file in files {
            childrenByParent[Self.parentPath(for: file.path), default: []].append(file)
        }

        func build(_ node: WorkspaceTreeNode) -> WorkspaceTreeNode {
            var next = node
            next.children = sorted(childrenByParent[node.path, default: []]).map(build)
            return next
        }

        return sorted(childrenByParent[nil, default: []]).map(build)
    }

    public mutating func openFile(rootID: String, path: String, content: String, tokens: [SyntaxToken] = []) {
        let tab = FileTab(rootID: rootID, path: path, content: content, tokens: tokens)
        if let existing = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[existing] = tab
        } else {
            openTabs.append(tab)
        }
        selectedTabID = tab.id
    }

    /// Closes a tab; when the closed tab was selected, selection falls to the
    /// next neighbor, then the previous one, then clears.
    public mutating func closeTab(id: FileTab.ID) {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let wasSelected = selectedTabID == id
        openTabs.remove(at: index)
        guard wasSelected else {
            return
        }
        if openTabs.isEmpty {
            selectedTabID = nil
        } else {
            let neighbor = min(index, openTabs.count - 1)
            selectedTabID = openTabs[neighbor].id
        }
    }

    public mutating func selectNextTab() {
        moveSelection(by: 1)
    }

    public mutating func selectPreviousTab() {
        moveSelection(by: -1)
    }

    private mutating func moveSelection(by step: Int) {
        guard !openTabs.isEmpty else {
            selectedTabID = nil
            return
        }
        guard let current = selectedTabID,
              let index = openTabs.firstIndex(where: { $0.id == current })
        else {
            selectedTabID = openTabs.first?.id
            return
        }
        let count = openTabs.count
        let next = ((index + step) % count + count) % count
        selectedTabID = openTabs[next].id
    }

    private static func parentPath(for path: String) -> String? {
        guard let slash = path.lastIndex(of: "/") else {
            return nil
        }
        return String(path[..<slash])
    }

    private static func name(for path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func sorted(_ nodes: [WorkspaceTreeNode]) -> [WorkspaceTreeNode] {
        nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

public struct WorkspaceTreeNode: Equatable, Identifiable, Sendable {
    public var id: String { entry.id }
    public var rootId: String { entry.rootId }
    public var rootPath: String { entry.rootPath }
    public var path: String { entry.path }
    public var name: String { entry.name }
    public var kind: String { entry.kind }
    public var isDirectory: Bool { entry.isDirectory }
    public var children: [WorkspaceTreeNode]

    public let entry: WorkspaceEntry

    public init(entry: WorkspaceEntry, children: [WorkspaceTreeNode]) {
        self.entry = entry
        self.children = children
    }

    public init(rootId: String, rootPath: String, path: String, name: String, kind: String, children: [WorkspaceTreeNode]) {
        self.entry = WorkspaceEntry(rootId: rootId, rootPath: rootPath, path: path, name: name, kind: kind)
        self.children = children
    }
}

public struct FileTab: Equatable, Identifiable, Sendable {
    public let id: String
    public let rootID: String
    public let path: String
    public let content: String
    public let tokens: [SyntaxToken]
    public let isReadOnly: Bool

    public init(rootID: String, path: String, content: String, tokens: [SyntaxToken] = [], isReadOnly: Bool = true) {
        self.id = rootID + ":" + path
        self.rootID = rootID
        self.path = path
        self.content = content
        self.tokens = tokens
        self.isReadOnly = isReadOnly
    }
}
