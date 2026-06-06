import AppKit
import ArchSightKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State var state = WorkspaceViewState()
    @State var expandedPaths: Set<String> = []
    /// Root ids the user has collapsed. Empty = all roots expanded, so newly
    /// dragged-in folders default to expanded without seeding state.
    @State var collapsedRoots: Set<WorkspaceRoot.ID> = []
    @State private var activeSearchTask: Task<Void, Never>? = nil

    @State var history = NavigationHistory()
    @State private var isSplit = false
    @State var isSidebarVisible = true

    enum SidebarTab: String, CaseIterable, Sendable {
        case explorer
        case search
    }
    @State var activeSidebarTab: SidebarTab = .explorer
    @State private var comparisonTabID: FileTab.ID?
    @State var sidebarSelection: WorkspaceEntry.ID?
    @State var sidebarTreeNodes: [WorkspaceRoot.ID: [WorkspaceTreeNode]] = [:]
    @State var sidebarFileEntriesByID: [WorkspaceEntry.ID: WorkspaceEntry] = [:]
    @State var hoveredOpenTabID: FileTab.ID?
    @State var searchSelection: SearchMatch.ID?
    @State var pendingScrollLine: Int?
    @State private var markdownDisplayMode: MarkdownDisplayMode = .preview
    @State private var isQuickOpenPresented = false
    @State private var isShortcutsPresented = false
    @Environment(ReadingPreferencesStore.self) private var readingStore
    @Environment(RecentFoldersStore.self) private var recentStore
    @Environment(AppCore.self) private var appCore

    private var coreEndpoint: CoreServiceEndpoint? { appCore.endpoint }

    var body: some View {
        HStack(spacing: 0) {
            activityBar
            Divider().opacity(0.55)
            if isSidebarVisible {
                sidebarPanel
                    .frame(width: 268)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider().opacity(0.55)
            }
            editorPane
        }
        .toolbar { toolbarContent }
        .background(Color(NSColor.textBackgroundColor))
        .background { keyboardShortcuts }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleDroppedFolders(providers)
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
        .overlay {
            if isQuickOpenPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { isQuickOpenPresented = false }
                    QuickOpenPanel(
                        entries: state.fileEntries,
                        onOpen: { entry in
                            isQuickOpenPresented = false
                            openEntry(entry)
                        },
                        onClose: { isQuickOpenPresented = false }
                    )
                    .padding(.top, 40)
                }
            }
        }
        .overlay {
            if isShortcutsPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { isShortcutsPresented = false }
                    ShortcutCheatSheet(onClose: { isShortcutsPresented = false })
                        .padding(.top, 48)
                }
            }
        }
        .focusedValue(\.workspaceCommands, WorkspaceCommandActions(
            openFolder: { openFolderPicker() },
            openRecent: { path in appendRoots([URL(fileURLWithPath: path)]) },
            toggleSidebar: {
                withAnimation(.easeInOut(duration: 0.16)) { isSidebarVisible.toggle() }
            },
            focusExplorer: {
                activeSidebarTab = .explorer
                withAnimation(.easeInOut(duration: 0.16)) { isSidebarVisible = true }
            },
            focusSearch: {
                activeSidebarTab = .search
                withAnimation(.easeInOut(duration: 0.16)) { isSidebarVisible = true }
            },
            toggleSplit: { isSplit.toggle() },
            collapseAll: { collapseAll() },
            selectTab: { number in selectTab(at: number) },
            quickOpen: {
                isShortcutsPresented = false
                isQuickOpenPresented = true
            },
            goBack: { goBack() },
            goForward: { goForward() },
            nextTab: { selectAndRecord { state.selectNextTab() } },
            previousTab: { selectAndRecord { state.selectPreviousTab() } },
            showShortcuts: {
                isQuickOpenPresented = false
                isShortcutsPresented = true
            }
        ))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!history.canGoBack)
                .help("Back \(ShortcutCatalog.hint("back")?.chord.display ?? "")")
            Button { goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!history.canGoForward)
                .help("Forward \(ShortcutCatalog.hint("forward")?.chord.display ?? "")")
        }
        ToolbarItemGroup {
            Button { openFolderPicker() } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .help("Open Folder \(ShortcutCatalog.hint("openFolder")?.chord.display ?? "")")
            Toggle(isOn: $isSplit) {
                Label("Split", systemImage: "rectangle.split.2x1")
            }
            .help("Split Editor \(ShortcutCatalog.hint("splitEditor")?.chord.display ?? "") · compare two files")
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Reading Settings")
            .help("Reading settings (theme, text size, line spacing)")
            
            Menu {
                Picker("Layout Style", selection: Binding(
                    get: { readingStore.preferences.tabLayoutMode },
                    set: { readingStore.setTabLayoutMode($0) }
                )) {
                    ForEach(TabLayoutMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: systemImage(for: mode))
                            .tag(mode)
                    }
                }
            } label: {
                Image(systemName: systemImage(for: readingStore.preferences.tabLayoutMode))
            }
            .menuStyle(.borderlessButton)
            .help("Layout Style")
        }
    }

    /// Cmd+W stays a focused hidden button: overriding the system Close item via
    /// `Commands` is unreliable, but a focused shortcut reliably intercepts it.
    /// Back/forward/next/prev moved to the "Go" menu to avoid double-binding.
    private var keyboardShortcuts: some View {
        Button("") { closeTabOrWindow() }
            .keyboardShortcut("w", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                HStack(spacing: 4) {
                    switch appCore.status {
                    case .disconnected:
                        ArchSightIcon.StatusIndicator(color: .gray)
                        Text("Core offline").font(.system(size: 10)).foregroundColor(.secondary)
                    case .connecting:
                        ArchSightIcon.StatusIndicator(color: .yellow, pulsing: true)
                        Text("Core connecting").font(.system(size: 10)).foregroundColor(.secondary)
                    case .connected(let health):
                        ArchSightIcon.StatusIndicator(color: .green)
                        Text("Core \(health.version)").font(.system(size: 10)).foregroundColor(.secondary)
                    case .failed:
                        ArchSightIcon.StatusIndicator(color: .red)
                        Text("Core unavailable").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                
                if let message = state.errorMessage {
                    Spacer()
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if let tab = selectedTab {
                    Text(tab.path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Editor / detail

    @ViewBuilder
    private var editorPane: some View {
        VStack(spacing: 0) {
            if readingStore.preferences.tabLayoutMode == .horizontalTabs || readingStore.preferences.tabLayoutMode == .both {
                if !state.openTabs.isEmpty {
                    HorizontalTabBar(
                        openTabs: state.openTabs,
                        selectedTabID: Binding(
                            get: { state.selectedTabID },
                            set: { newValue in
                                selectAndRecord { state.selectedTabID = newValue }
                            }
                        ),
                        onCloseTab: { id in
                            state.closeTab(id: id)
                        }
                    )
                }
            }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .safeAreaInset(edge: .bottom) { referencesPanel }
    }

    @ViewBuilder
    private var primaryPane: some View {
        if state.roots.isEmpty {
            WelcomeView(
                recents: Array(recentStore.existingEntries().prefix(10)),
                onOpenFolder: { openFolderPicker() },
                onOpenRecent: { path in appendRoots([URL(fileURLWithPath: path)]) },
                onRemoveRecent: { path in recentStore.remove(path: path) }
            )
        } else if let tab = selectedTab {
            filePane(for: tab, scrollLine: pendingScrollLine)
        } else {
            ContentUnavailableView("Read Only", systemImage: "eye")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                filePane(for: tab, scrollLine: nil)
            } else {
                ContentUnavailableView("Pick a File", systemImage: "rectangle.split.2x1")
            }
        }
    }

    @ViewBuilder
    private func filePane(for tab: FileTab, scrollLine: Int?) -> some View {
        if tab.canPreviewMarkdown {
            VStack(spacing: 0) {
                HStack {
                    Picker("Markdown display", selection: $markdownDisplayMode) {
                        Label("Preview", systemImage: "doc.richtext")
                            .tag(MarkdownDisplayMode.preview)
                        Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                            .tag(MarkdownDisplayMode.source)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .help("Switch Markdown display")
                    Spacer()
                    ReadingControlsView()
                }
                .padding(6)
                Divider()

                switch markdownDisplayMode {
                case .preview:
                    MarkdownPreviewView(content: tab.content, preferences: readingStore.preferences)
                case .source:
                    codeView(for: tab, scrollLine: scrollLine)
                }
            }
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    ReadingControlsView()
                }
                .padding(6)
                Divider()
                codeView(for: tab, scrollLine: scrollLine)
            }
        }
    }

    private func codeView(for tab: FileTab, scrollLine: Int?) -> some View {
        CodeTextView(
            content: tab.content,
            tokens: tab.tokens,
            preferences: readingStore.preferences,
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
        let fresh = added.filter { !existing.contains($0) }
        guard !fresh.isEmpty else { return }

        if state.workspaceId == nil {
            reopenWorkspace(paths: existing + fresh)
        } else {
            addRoots(paths: fresh)
        }
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
        refreshSidebarTreeNodes()
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
                result.roots.forEach { recentStore.record(path: $0.path) }
                state.entries = result.entries
                refreshSidebarTreeNodes()
                state.isLoading = false
            } catch {
                state.isLoading = false
                state.errorMessage = Self.describe(error)
            }
        }
    }

    private func addRoots(paths: [String]) {
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        state.isLoading = true
        state.errorMessage = nil
        Task {
            do {
                let result = try await Task.detached {
                    try endpoint.makeController().addRoots(workspaceId: workspaceId, paths: paths)
                }.value
                state.roots = result.roots
                result.roots.forEach { recentStore.record(path: $0.path) }
                state.entries = result.entries
                refreshSidebarTreeNodes()
                state.isLoading = false
            } catch {
                state.isLoading = false
                state.errorMessage = Self.describe(error)
            }
        }
    }

    func removeRoot(_ root: WorkspaceRoot) {
        // Drop the tabs/selection locally first so the UI updates immediately,
        // then tell the core to forget the root and refresh from the result.
        expandedPaths = expandedPaths.filter { path in
            path != root.path && !path.hasPrefix(root.path + "/")
        }
        collapsedRoots.remove(root.id)
        state.removeRoot(id: root.id)
        refreshSidebarTreeNodes()
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        Task {
            do {
                let result = try await Task.detached {
                    try endpoint.makeController().removeRoot(workspaceId: workspaceId, rootId: root.id)
                }.value
                state.roots = result.roots
                state.entries = result.entries
                refreshSidebarTreeNodes()
            } catch {
                state.errorMessage = Self.describe(error)
            }
        }
    }

    func closeWorkspace() {
        expandedPaths = []
        collapsedRoots = []
        state.closeWorkspace()
        refreshSidebarTreeNodes()
    }

    func collapseAll() {
        // Match VSCode "Collapse Folders in Explorer": collapse nested folders
        // and the root sections together.
        expandedPaths = []
        collapsedRoots = Set(state.roots.map(\.id))
    }

    func openEntry(_ entry: WorkspaceEntry) {
        sidebarSelection = entry.id
        loadFile(rootId: entry.rootId, path: entry.path, scrollLine: nil)
    }

    private func refreshSidebarTreeNodes() {
        sidebarTreeNodes = Dictionary(
            uniqueKeysWithValues: state.roots.map { root in
                (root.id, state.treeEntries(for: root))
            }
        )
        sidebarFileEntriesByID = Dictionary(
            uniqueKeysWithValues: state.fileEntries.map { entry in
                (entry.id, entry)
            }
        )
    }

    func openMatch(_ match: SearchMatch) {
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
                state.openFile(rootID: tab.rootID, path: tab.path, content: tab.content, tokens: tab.tokens)
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

    func runSearch() {
        activeSearchTask?.cancel()
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        let pattern = state.searchQuery
        guard !pattern.isEmpty else {
            state.searchResults = []
            return
        }
        activeSearchTask = Task {
            do {
                let matches = try await Task.detached {
                    try endpoint.makeController().search(workspaceId: workspaceId, pattern: pattern)
                }.value
                try Task.checkCancellation()
                state.searchResults = matches
                state.errorMessage = matches.isEmpty ? "No matches for \"\(pattern)\"." : nil
            } catch is CancellationError {
                // Task was cancelled, ignore updates
            } catch {
                state.searchResults = []
                state.errorMessage = Self.describe(error)
            }
        }
    }

    // MARK: - Keyboard navigation helpers

    func openSelectedSidebarEntry() {
        guard let id = sidebarSelection,
              let entry = sidebarFileEntriesByID[id]
        else {
            return
        }
        openEntry(entry)
    }

    func openSelectedSearchMatch() {
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

    private func selectTab(at oneBasedIndex: Int) {
        let index = oneBasedIndex - 1
        guard index >= 0, index < state.openTabs.count else { return }
        selectAndRecord { state.selectedTabID = state.openTabs[index].id }
    }

    private func closeTabOrWindow() {
        if state.selectedTabID != nil {
            closeSelectedTab()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
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

    // MARK: - Layout and Visual Helpers

    private func systemImage(for mode: TabLayoutMode) -> String {
        switch mode {
        case .verticalList: return "sidebar.left"
        case .horizontalTabs: return "rectangle.grid.1x2"
        case .both: return "rectangle.split.3x1"
        }
    }


}

private enum MarkdownDisplayMode {
    case preview
    case source
}
