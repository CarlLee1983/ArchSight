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

    public mutating func openFile(rootID: String, path: String, content: String) {
        let tab = FileTab(rootID: rootID, path: path, content: content)
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
