import AppKit
import ArchSightKit
import SwiftUI

// Sidebar + activity-bar view construction, split out of ContentView to keep
// each file focused. Same type (extension), so no behavior change.
extension ContentView {

    // MARK: - Sidebar & Activity Bar Views

    var activityBar: some View {
        VStack(spacing: 16) {
            // Explorer Tab
            Button { handleTabClick(.explorer) } label: {
                VStack {
                    ArchSightIcon.Explorer(color: activeSidebarTab == .explorer ? .accentColor : .secondary)
                }
                .frame(width: 36, height: 36)
                .background(activeSidebarTab == .explorer ? Color.secondary.opacity(0.15) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help(ShortcutCatalog.tooltip("File Explorer", "showExplorer"))
            .overlay(alignment: .leading) {
                if activeSidebarTab == .explorer {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 20)
                }
            }

            // Search Tab
            Button { handleTabClick(.search) } label: {
                VStack {
                    ArchSightIcon.Search(color: activeSidebarTab == .search ? .accentColor : .secondary)
                }
                .frame(width: 36, height: 36)
                .background(activeSidebarTab == .search ? Color.secondary.opacity(0.15) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help(ShortcutCatalog.tooltip("Search in Workspace", "showSearch"))
            .overlay(alignment: .leading) {
                if activeSidebarTab == .search {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 20)
                }
            }

            // Outline Tab
            Button { handleTabClick(.outline) } label: {
                VStack {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 16))
                        .foregroundStyle(activeSidebarTab == .outline ? Color.accentColor : .secondary)
                }
                .frame(width: 36, height: 36)
                .background(activeSidebarTab == .outline ? Color.secondary.opacity(0.15) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Outline")
            .overlay(alignment: .leading) {
                if activeSidebarTab == .outline {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 20)
                }
            }

            Spacer()
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .frame(width: 48)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    var sidebarPanel: some View {
        VStack(spacing: 0) {
            switch activeSidebarTab {
            case .explorer:
                if !state.openTabs.isEmpty {
                    openFilesPanel
                }

                if !state.roots.isEmpty {
                    foldersHeader
                }

                List(selection: $sidebarSelection) {
                    ForEach(state.roots) { root in
                        let rootExpanded = Binding<Bool>(
                            get: { !collapsedRoots.contains(root.id) },
                            set: { expanded in
                                if expanded {
                                    collapsedRoots.remove(root.id)
                                } else {
                                    collapsedRoots.insert(root.id)
                                }
                            }
                        )
                        Section(root.name, isExpanded: rootExpanded) {
                            let nodes = sidebarTreeNodes[root.id, default: []]
                            if nodes.isEmpty {
                                Text("No files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(nodes) { node in
                                    sidebarNode(node)
                                }
                            }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { FileSystemActions.revealInFinder(path: root.path) }
                            Button("Copy Path") { FileSystemActions.copyToPasteboard(root.path) }
                            Divider()
                            Button("Remove Folder from Workspace") { removeRoot(root) }
                            Divider()
                            Button("Close All Folders") { closeWorkspace() }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: sidebarSelection) { _, newSelection in
                    guard let id = newSelection,
                          let entry = sidebarFileEntriesByID[id]
                    else {
                        return
                    }
                    openEntry(entry)
                }
                .onKeyPress(.return) {
                    openSelectedSidebarEntry()
                    return .handled
                }
                .overlay {
                    if state.roots.isEmpty {
                        ContentUnavailableView("No Workspace", systemImage: "folder")
                    }
                }

            case .search:
                VStack(spacing: 8) {
                    HStack {
                        TextField("Search Pattern", text: $state.searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { runSearch() }
                        Button { runSearch() } label: {
                            Text("Go")
                        }
                    }
                    .padding(8)

                    searchResultsList
                }

            case .outline:
                OutlinePanel(
                    symbols: outlineSymbols,
                    isLoading: isLoadingOutline,
                    hasOpenFile: selectedTab != nil,
                    onSelect: { goToOutlineSymbol($0) }
                )
                .onAppear { loadOutlineIfNeeded() }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    var foldersHeader: some View {
        HStack(spacing: 6) {
            Text("FOLDERS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: collapseAll) {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(ShortcutCatalog.tooltip("Collapse Folders", "collapseFolders"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    var openFilesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OPEN FILES")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.openTabs) { tab in
                        openFileRow(tab)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 154)

            Divider().opacity(0.6)
        }
    }

    func openFileRow(_ tab: FileTab) -> some View {
        let fileName = (tab.path as NSString).lastPathComponent
        let isSelected = state.selectedTabID == tab.id
        let isHovered = hoveredOpenTabID == tab.id

        return HStack(spacing: 8) {
            FileIconMapper.iconType(for: fileName).view()
            Text(fileName)
                .font(.system(size: 11, design: .monospaced))
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                state.closeTab(id: tab.id)
                if hoveredOpenTabID == tab.id {
                    hoveredOpenTabID = nil
                }
            } label: {
                ArchSightIcon.Close(color: isSelected ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isHovered ? Color.secondary.opacity(0.16) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredOpenTabID = isHovering ? tab.id : nil
        }
        .onTapGesture {
            state.selectedTabID = tab.id
            history.visit(tab.id)
            pendingScrollLine = nil
        }
    }

    func sidebarNode(_ node: WorkspaceTreeNode) -> AnyView {
        if node.isDirectory {
            let isExpandedBinding = Binding<Bool>(
                get: { expandedPaths.contains(node.path) },
                set: { isExpanded in
                    if isExpanded {
                        expandedPaths.insert(node.path)
                    } else {
                        expandedPaths.remove(node.path)
                    }
                }
            )
            let isExpanded = expandedPaths.contains(node.path)
            return AnyView(DisclosureGroup(isExpanded: isExpandedBinding) {
                ForEach(node.children) { child in
                    sidebarNode(child)
                }
            } label: {
                HStack(spacing: 6) {
                    if isExpanded {
                        ArchSightIcon.FolderOpen()
                    } else {
                        ArchSightIcon.Folder()
                    }
                    Text(node.name)
                        .font(.system(.caption, design: .default))
                }
                .help(node.path)
                .contextMenu { entryContextMenu(path: node.path, rootPath: node.rootPath) }
            })
        } else {
            return AnyView(
                HStack(spacing: 6) {
                    FileIconMapper.iconType(for: node.name).view()
                    Text(node.name)
                        .font(.system(.caption, design: .monospaced))
                }
                .help(node.path)
                .tag(node.entry.id)
                .contentShape(Rectangle())
                .contextMenu { entryContextMenu(path: node.path, rootPath: node.rootPath) }
            )
        }
    }

    @ViewBuilder
    func entryContextMenu(path: String, rootPath: String) -> some View {
        Button("Reveal in Finder") { FileSystemActions.revealInFinder(path: path) }
        Divider()
        Button("Copy Path") { FileSystemActions.copyToPasteboard(path) }
        Button("Copy Relative Path") {
            FileSystemActions.copyToPasteboard(FileSystemPaths.relative(of: path, under: rootPath))
        }
    }

    var searchResultsList: some View {
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
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onKeyPress(.return) {
            openSelectedSearchMatch()
            return .handled
        }
    }

    func handleTabClick(_ tab: SidebarTab) {
        if activeSidebarTab == tab {
            withAnimation(.easeInOut(duration: 0.16)) {
                isSidebarVisible.toggle()
            }
        } else {
            activeSidebarTab = tab
            withAnimation(.easeInOut(duration: 0.16)) {
                isSidebarVisible = true
            }
        }
    }

}
