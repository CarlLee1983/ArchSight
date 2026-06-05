import ArchSightKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var state = WorkspaceViewState()
    @State private var coreStatus: CoreSessionStatus = .disconnected
    @State private var coreSession = CoreSessionFactory.fromEnvironment()
    @State private var coreEndpoint: CoreServiceEndpoint?

    @State private var history = NavigationHistory()
    @State private var isSplit = false
    @State private var comparisonTabID: FileTab.ID?
    @State private var sidebarSelection: WorkspaceEntry.ID?
    @State private var searchSelection: SearchMatch.ID?
    @State private var pendingScrollLine: Int?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            middleColumn
        } detail: {
            editorPane
        }
        .toolbar { toolbarContent }
        .background { keyboardShortcuts }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleDroppedFolders(providers)
        }
        .task {
            connectCoreIfConfigured()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = state.errorMessage {
                statusBanner(message)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!history.canGoBack)
                .help("Back")
            Button { goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!history.canGoForward)
                .help("Forward")
        }
        ToolbarItemGroup {
            Button { openFolderPicker() } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            Toggle(isOn: $isSplit) {
                Label("Split", systemImage: "rectangle.split.2x1")
            }
            .help("Compare two files side by side")
            TextField("Search", text: $state.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 260)
                .onSubmit { runSearch() }
                .disabled(!canSearch)
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
            coreStatusLabel
        }
    }

    /// Hidden buttons that register keyboard shortcuts for keyboard-only review.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { goBack() }.keyboardShortcut("[", modifiers: .command)
            Button("") { goForward() }.keyboardShortcut("]", modifiers: .command)
            Button("") { closeSelectedTab() }.keyboardShortcut("w", modifiers: .command)
            Button("") { selectAndRecord(stateMutation: { state.selectNextTab() }) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("") { selectAndRecord(stateMutation: { state.selectPreviousTab() }) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Sidebar (workspace tree)

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            ForEach(state.roots) { root in
                Section(root.name) {
                    let files = state.fileEntries.filter { $0.rootId == root.id }
                    if files.isEmpty {
                        Text("No files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(files) { entry in
                            Text(entry.path)
                                .font(.system(.caption, design: .monospaced))
                                .help(entry.path)
                                .tag(entry.id)
                                .onTapGesture(count: 2) { openEntry(entry) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Workspace")
        .onKeyPress(.return) {
            openSelectedSidebarEntry()
            return .handled
        }
        .overlay {
            if state.roots.isEmpty {
                ContentUnavailableView("No Workspace", systemImage: "folder")
            }
        }
    }

    // MARK: - Middle column (open files / search results)

    @ViewBuilder
    private var middleColumn: some View {
        if state.searchResults.isEmpty {
            fileList
        } else {
            searchResultsList
        }
    }

    private var fileList: some View {
        // Intercepts only user-driven tab selection so it records history and
        // resets the scroll target; programmatic selection (open, back/forward,
        // next/previous) mutates `state.selectedTabID` directly and bypasses this.
        let manualSelection = Binding<FileTab.ID?>(
            get: { state.selectedTabID },
            set: { newValue in
                state.selectedTabID = newValue
                if let newValue {
                    history.visit(newValue)
                    pendingScrollLine = nil
                }
            }
        )
        return List(selection: manualSelection) {
            ForEach(state.openTabs) { tab in
                HStack {
                    Text(tab.path)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        state.closeTab(id: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close tab")
                }
                .tag(tab.id)
            }
        }
        .navigationTitle("Open Files")
        .overlay {
            if state.openTabs.isEmpty {
                ContentUnavailableView("No File", systemImage: "doc.text")
            }
        }
    }

    private var searchResultsList: some View {
        List(selection: $searchSelection) {
            Section("Search Results (\(state.searchResults.count))") {
                ForEach(state.searchResults) { match in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(match.path):\(match.line)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(match.preview)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                    .tag(match.id)
                    .onTapGesture(count: 2) { openMatch(match) }
                }
            }
        }
        .navigationTitle("Search")
        .onKeyPress(.return) {
            openSelectedSearchMatch()
            return .handled
        }
    }

    // MARK: - Editor / detail

    @ViewBuilder
    private var editorPane: some View {
        Group {
            if isSplit {
                HSplitView {
                    primaryPane
                    comparisonPane
                }
            } else {
                primaryPane
            }
        }
        .safeAreaInset(edge: .bottom) { referencesPanel }
    }

    @ViewBuilder
    private var primaryPane: some View {
        if let tab = selectedTab {
            codeView(for: tab, scrollLine: pendingScrollLine)
                .navigationTitle(tab.path)
        } else {
            ContentUnavailableView("Read Only", systemImage: "eye")
        }
    }

    @ViewBuilder
    private var comparisonPane: some View {
        VStack(spacing: 0) {
            HStack {
                Menu(comparisonTab?.path ?? "Pick a file") {
                    ForEach(state.openTabs) { tab in
                        Button(tab.path) { comparisonTabID = tab.id }
                    }
                }
                .frame(maxWidth: 260)
                Spacer()
            }
            .padding(6)
            Divider()
            if let tab = comparisonTab {
                codeView(for: tab, scrollLine: nil)
            } else {
                ContentUnavailableView("Pick a File", systemImage: "rectangle.split.2x1")
            }
        }
    }

    private func codeView(for tab: FileTab, scrollLine: Int?) -> some View {
        CodeTextView(
            content: tab.content,
            scrollToLine: scrollLine,
            onDefinition: { line, column in requestDefinition(on: tab, line: line, column: column) },
            onReferences: { line, column in requestReferences(on: tab, line: line, column: column) }
        )
    }

    @ViewBuilder
    private var referencesPanel: some View {
        if !state.references.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("References\(state.referencesContext.map { " · \($0)" } ?? "") (\(state.references.count))")
                        .font(.caption.bold())
                    Spacer()
                    Button {
                        state.references = []
                        state.referencesContext = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss references")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                Divider()
                List(state.references) { location in
                    Button {
                        openLocation(location)
                    } label: {
                        Text("\(location.path):\(location.startLine):\(location.startColumn)")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 150)
            }
            .background(.bar)
        }
    }

    // MARK: - Derived

    private var selectedTab: FileTab? {
        state.openTabs.first { $0.id == state.selectedTabID }
    }

    private var comparisonTab: FileTab? {
        state.openTabs.first { $0.id == comparisonTabID }
    }

    private var canSearch: Bool {
        coreEndpoint != nil && state.workspaceId != nil
    }

    private var coreStatusLabel: some View {
        Group {
            switch coreStatus {
            case .disconnected:
                Label("Core offline", systemImage: "circle")
            case .connecting:
                Label("Core connecting", systemImage: "circle.dotted")
            case .connected(let health):
                Label("Core \(health.version)", systemImage: "checkmark.circle")
            case .failed:
                Label("Core unavailable", systemImage: "exclamationmark.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
    }

    // MARK: - Core lifecycle

    private func connectCoreIfConfigured() {
        guard let coreSession else {
            return
        }
        coreStatus = .connecting
        do {
            _ = try coreSession.connect()
            coreStatus = coreSession.status
            coreEndpoint = coreSession.serviceEndpoint
        } catch {
            coreStatus = coreSession.status
        }
    }

    // MARK: - Folder intake

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            appendRoots(panel.urls)
        }
    }

    private func handleDroppedFolders(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.hasDirectoryPath
                else {
                    return
                }
                DispatchQueue.main.async {
                    appendRoots([url])
                }
            }
            return true
        }
        return false
    }

    private func appendRoots(_ urls: [URL]) {
        let added = urls.map(\.path)
        guard coreEndpoint != nil else {
            appendRootsLocally(added)
            return
        }
        let existing = state.roots.map(\.path)
        let combined = existing + added.filter { !existing.contains($0) }
        guard combined != existing else { return }
        reopenWorkspace(paths: combined)
    }

    private func appendRootsLocally(_ paths: [String]) {
        let existing = Set(state.roots.map(\.path))
        let nextRoots = paths.filter { !existing.contains($0) }.map { path in
            WorkspaceRoot(
                id: "root_\(abs(path.hashValue))",
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path
            )
        }
        state.roots.append(contentsOf: nextRoots)
        state.errorMessage = "Core service is not connected; tree, file, and search are unavailable."
    }

    // MARK: - Core-backed actions

    private func reopenWorkspace(paths: [String]) {
        guard let endpoint = coreEndpoint else { return }
        state.isLoading = true
        state.errorMessage = nil
        state.searchResults = []
        state.references = []
        Task {
            do {
                let result = try await Task.detached {
                    try endpoint.makeController().openWorkspace(paths: paths)
                }.value
                state.workspaceId = result.workspaceId
                state.roots = result.roots
                state.entries = result.entries
                state.isLoading = false
            } catch {
                state.isLoading = false
                state.errorMessage = Self.describe(error)
            }
        }
    }

    private func openEntry(_ entry: WorkspaceEntry) {
        loadFile(rootId: entry.rootId, path: entry.path, scrollLine: nil)
    }

    private func openMatch(_ match: SearchMatch) {
        loadFile(rootId: match.rootId, path: match.path, scrollLine: match.line)
    }

    private func openLocation(_ location: Location) {
        loadFile(rootId: location.rootId, path: location.path, scrollLine: location.startLine)
    }

    private func loadFile(rootId: String, path: String, scrollLine: Int?) {
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        Task {
            do {
                let tab = try await Task.detached {
                    try endpoint.makeController().loadFile(workspaceId: workspaceId, rootId: rootId, path: path)
                }.value
                state.openFile(rootID: tab.rootID, path: tab.path, content: tab.content)
                if let id = state.selectedTabID {
                    history.visit(id)
                }
                pendingScrollLine = scrollLine
            } catch {
                state.errorMessage = Self.describe(error)
            }
        }
    }

    private func requestDefinition(on tab: FileTab, line: Int, column: Int) {
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        Task {
            do {
                let locations = try await Task.detached {
                    try endpoint.makeController().definition(
                        workspaceId: workspaceId,
                        rootId: tab.rootID,
                        path: tab.path,
                        line: line,
                        column: column
                    )
                }.value
                guard let target = locations.first else {
                    state.errorMessage = "No definition found at \(tab.path):\(line):\(column)."
                    return
                }
                openLocation(target)
            } catch {
                state.errorMessage = Self.describe(error)
            }
        }
    }

    private func requestReferences(on tab: FileTab, line: Int, column: Int) {
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        Task {
            do {
                let locations = try await Task.detached {
                    try endpoint.makeController().references(
                        workspaceId: workspaceId,
                        rootId: tab.rootID,
                        path: tab.path,
                        line: line,
                        column: column
                    )
                }.value
                state.references = locations
                state.referencesContext = "\(tab.path):\(line):\(column)"
                state.errorMessage = locations.isEmpty ? "No references found at \(tab.path):\(line):\(column)." : nil
            } catch {
                state.references = []
                state.errorMessage = Self.describe(error)
            }
        }
    }

    private func runSearch() {
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        let pattern = state.searchQuery
        guard !pattern.isEmpty else {
            state.searchResults = []
            return
        }
        Task {
            do {
                let matches = try await Task.detached {
                    try endpoint.makeController().search(workspaceId: workspaceId, pattern: pattern)
                }.value
                state.searchResults = matches
                state.errorMessage = matches.isEmpty ? "No matches for \"\(pattern)\"." : nil
            } catch {
                state.searchResults = []
                state.errorMessage = Self.describe(error)
            }
        }
    }

    // MARK: - Keyboard navigation helpers

    private func openSelectedSidebarEntry() {
        guard let id = sidebarSelection,
              let entry = state.fileEntries.first(where: { $0.id == id })
        else {
            return
        }
        openEntry(entry)
    }

    private func openSelectedSearchMatch() {
        guard let id = searchSelection,
              let match = state.searchResults.first(where: { $0.id == id })
        else {
            return
        }
        openMatch(match)
    }

    private func closeSelectedTab() {
        guard let id = state.selectedTabID else { return }
        state.closeTab(id: id)
    }

    private func selectAndRecord(stateMutation: () -> Void) {
        stateMutation()
        if let id = state.selectedTabID {
            history.visit(id)
            pendingScrollLine = nil
        }
    }

    private func goBack() {
        if let id = history.back() {
            applyHistorySelection(id)
        }
    }

    private func goForward() {
        if let id = history.forward() {
            applyHistorySelection(id)
        }
    }

    /// Applies a history selection without recording a new visit. If the tab was
    /// closed, the selection is skipped silently.
    private func applyHistorySelection(_ id: String) {
        guard state.openTabs.contains(where: { $0.id == id }) else { return }
        if state.selectedTabID != id {
            state.selectedTabID = id
        }
        pendingScrollLine = nil
    }

    private static func describe(_ error: Error) -> String {
        if let ipcError = error as? CoreClientError {
            return "\(ipcError.code): \(ipcError.message)"
        }
        return String(describing: error)
    }
}
