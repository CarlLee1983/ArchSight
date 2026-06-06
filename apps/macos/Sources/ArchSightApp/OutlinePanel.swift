import ArchSightKit
import SwiftUI

/// Docked, VSCode-style Outline view for the active file. Renders the same
/// `documentSymbol` data as the ⇧⌘O overlay, but as a persistent sidebar panel
/// with hierarchy indentation. Read-only: selecting a symbol scrolls the editor.
/// Symbols are fetched lazily by `ContentView` only while this tab is active.
struct OutlinePanel: View {
    let symbols: [DocumentSymbol]
    let isLoading: Bool
    let hasOpenFile: Bool
    let onSelect: (DocumentSymbol) -> Void

    @State private var selection: DocumentSymbol.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OUTLINE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if !hasOpenFile {
            placeholder("Open a file to see its outline", systemImage: "list.bullet.indent")
        } else if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading symbols…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else if symbols.isEmpty {
            placeholder("No symbols in this file", systemImage: "questionmark.circle")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(symbols) { symbol in
                        row(symbol)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
    }

    private func row(_ symbol: DocumentSymbol) -> some View {
        let isSelected = selection == symbol.id
        return HStack(spacing: 6) {
            if symbol.depth > 0 {
                Spacer().frame(width: CGFloat(symbol.depth) * 12)
            }
            Image(systemName: SymbolKindLabel.systemImage(for: symbol.kind))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(symbol.name)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(symbol.line)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = symbol.id
            onSelect(symbol)
        }
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
