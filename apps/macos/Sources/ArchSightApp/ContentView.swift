import ArchSightKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var state = WorkspaceViewState()
    @State private var coreStatus: CoreSessionStatus = .disconnected
    @State private var coreSession = CoreSessionFactory.fromEnvironment()
    @State private var coreEndpoint: CoreServiceEndpoint?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            middleColumn
        } detail: {
            editorPane
        }
        .toolbar {
            Button {
                openFolderPicker()
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
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

    // MARK: - Columns

    private var sidebar: some View {
        List {
            ForEach(state.roots) { root in
                Section(root.name) {
                    let files = state.fileEntries.filter { $0.rootId == root.id }
                    if files.isEmpty {
                        Text("No files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(files) { entry in
                            Button {
                                openEntry(entry)
                            } label: {
                                Text(entry.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help(entry.path)
                        }
                    }
                }
            }
        }
        .navigationTitle("Workspace")
        .overlay {
            if state.roots.isEmpty {
                ContentUnavailableView("No Workspace", systemImage: "folder")
            }
        }
    }

    @ViewBuilder
    private var middleColumn: some View {
        if state.searchResults.isEmpty {
            fileList
        } else {
            searchResults
        }
    }

    private var fileList: some View {
        List(state.openTabs, selection: $state.selectedTabID) { tab in
            Text(tab.path)
                .font(.system(.body, design: .monospaced))
                .tag(tab.id)
        }
        .navigationTitle("Open Files")
        .overlay {
            if state.openTabs.isEmpty {
                ContentUnavailableView("No File", systemImage: "doc.text")
            }
        }
    }

    private var searchResults: some View {
        List {
            Section("Search Results (\(state.searchResults.count))") {
                ForEach(state.searchResults) { match in
                    Button {
                        openMatch(match)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(match.path):\(match.line)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(match.preview)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Search")
    }

    private var editorPane: some View {
        Group {
            if let tab = selectedTab {
                ScrollView([.vertical, .horizontal]) {
                    Text(tab.content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .navigationTitle(tab.path)
            } else {
                ContentUnavailableView("Read Only", systemImage: "eye")
            }
        }
    }

    private var selectedTab: FileTab? {
        state.openTabs.first { $0.id == state.selectedTabID }
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

    private var canSearch: Bool {
        coreEndpoint != nil && state.workspaceId != nil
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

    /// Fallback used when no core service is configured: show the chosen folders
    /// as roots without a flattened tree, so the app still reflects the selection.
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
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        Task {
            do {
                let tab = try await Task.detached {
                    try endpoint.makeController().loadFile(
                        workspaceId: workspaceId,
                        rootId: entry.rootId,
                        path: entry.path
                    )
                }.value
                state.openFile(rootID: tab.rootID, path: tab.path, content: tab.content)
            } catch {
                state.errorMessage = Self.describe(error)
            }
        }
    }

    private func openMatch(_ match: SearchMatch) {
        guard let endpoint = coreEndpoint, let workspaceId = state.workspaceId else { return }
        Task {
            do {
                let tab = try await Task.detached {
                    try endpoint.makeController().loadFile(
                        workspaceId: workspaceId,
                        rootId: match.rootId,
                        path: match.path
                    )
                }.value
                state.openFile(rootID: tab.rootID, path: tab.path, content: tab.content)
            } catch {
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

    private static func describe(_ error: Error) -> String {
        if let ipcError = error as? CoreClientError {
            return "\(ipcError.code): \(ipcError.message)"
        }
        return String(describing: error)
    }
}
