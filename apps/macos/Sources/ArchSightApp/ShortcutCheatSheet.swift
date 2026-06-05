import ArchSightKit
import SwiftUI

/// Overlay listing all keyboard shortcuts grouped by category. Style mirrors
/// `QuickOpenPanel` (material, rounded, shadow). Reads `ShortcutCatalog` so the
/// hints never drift from the tooltips.
struct ShortcutCheatSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("esc")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ShortcutCatalog.grouped(), id: \.0) { category, hints in
                        if !hints.isEmpty {
                            section(category, hints)
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 24)
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func section(_ category: ShortcutCategory, _ hints: [ShortcutHint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            ForEach(hints) { hint in
                HStack {
                    Text(hint.label)
                        .font(.system(size: 12))
                    Spacer(minLength: 16)
                    Text(hint.chord.display)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
