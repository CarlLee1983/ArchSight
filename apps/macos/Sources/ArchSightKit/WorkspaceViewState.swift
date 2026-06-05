import Foundation

public struct WorkspaceViewState: Equatable, Sendable {
    public var workspaceId: String?
    public var roots: [WorkspaceRoot]
    public var entries: [WorkspaceEntry]
    public var openTabs: [FileTab]
    public var selectedTabID: FileTab.ID?
    public var searchQuery: String
    public var searchResults: [SearchMatch]
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

    public mutating func openFile(rootID: String, path: String, content: String) {
        let tab = FileTab(rootID: rootID, path: path, content: content)
        if let existing = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[existing] = tab
        } else {
            openTabs.append(tab)
        }
        selectedTabID = tab.id
    }
}

public struct FileTab: Equatable, Identifiable, Sendable {
    public let id: String
    public let rootID: String
    public let path: String
    public let content: String
    public let isReadOnly: Bool

    public init(rootID: String, path: String, content: String, isReadOnly: Bool = true) {
        self.id = rootID + ":" + path
        self.rootID = rootID
        self.path = path
        self.content = content
        self.isReadOnly = isReadOnly
    }
}
