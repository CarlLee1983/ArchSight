import ArchSightKit
import SwiftUI

/// VSCode-style "Go to Symbol in File" overlay (⇧⌘O). Self-contained: owns its
/// query/selection, fuzzy-filters the file's document symbols by name, and reports
/// the chosen symbol through `onGo`. Style mirrors `QuickOpenPanel`.
struct GoToSymbolPanel: View {
    let symbols: [DocumentSymbol]
    var isLoading: Bool = false
    let onGo: (DocumentSymbol) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var matches: [DocumentSymbol] {
        guard !query.isEmpty else { return symbols }
        return symbols
            .enumerated()
            .compactMap { index, symbol -> (index: Int, symbol: DocumentSymbol, score: Int)? in
                guard let score = FuzzyMatch.score(query, in: symbol.name) else { return nil }
                return (index, symbol, score)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.symbol)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Go to Symbol…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .focused($fieldFocused)
                .onChange(of: query) { _, _ in selection = 0 }

            Divider()

            if matches.isEmpty {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                        Text("Loading symbols…")
                    } else {
                        Text(symbols.isEmpty ? "No symbols in this file" : "No matching symbols")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, symbol in
                                row(symbol, isSelected: index == selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onGo(symbol) }
                            }
                        }
                    }
                    .onChange(of: selection) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 24)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func row(_ symbol: DocumentSymbol, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            // Indent nested symbols to convey the outline hierarchy.
            if symbol.depth > 0 {
                Spacer().frame(width: CGFloat(symbol.depth) * 14)
            }
            Image(systemName: SymbolKindLabel.systemImage(for: symbol.kind))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(symbol.name)
                .font(.system(size: 12, design: .monospaced))
            Text(SymbolKindLabel.name(for: symbol.kind))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(symbol.line)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
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
        onGo(list[selection])
    }
}
