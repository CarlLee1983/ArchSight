import ArchSightKit
import SwiftUI

/// VSCode-style Quick Open overlay. Self-contained: owns its query/selection,
/// ranks the workspace's file entries via `FuzzyMatch`, and reports the chosen
/// entry back through `onOpen`.
struct QuickOpenPanel: View {
    let entries: [WorkspaceEntry]
    let onOpen: (WorkspaceEntry) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var matches: [WorkspaceEntry] {
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return Array(
            FuzzyMatch.rank(query, candidates: entries.map(\.path))
                .compactMap { byPath[$0] }
                .prefix(50)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Go to File…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .focused($fieldFocused)
                .onChange(of: query) { _, _ in selection = 0 }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                            row(entry, isSelected: index == selection)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { onOpen(entry) }
                        }
                    }
                }
                .onChange(of: selection) { _, newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 24)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func row(_ entry: WorkspaceEntry, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            FileIconMapper.iconType(for: entry.name).view()
            Text(entry.name)
                .font(.system(size: 12, design: .monospaced))
            Text(entry.path)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
    }

    private func move(_ delta: Int) {
        let count = matches.count
        guard count > 0 else { return }
        selection = max(0, min(count - 1, selection + delta))
    }

    private func openSelected() {
        let list = matches
        guard selection < list.count else { return }
        onOpen(list[selection])
    }
}
