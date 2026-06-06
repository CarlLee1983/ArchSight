import ArchSightKit
import SwiftUI

/// VSCode-style "Go to Line" overlay. Self-contained: owns its input, resolves it
/// against the open file's line count via `GoToLineQuery`, and reports the chosen
/// 1-based line through `onGo`. Style mirrors `QuickOpenPanel`.
struct GoToLinePanel: View {
    let totalLines: Int
    let onGo: (Int) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var resolved: Int? {
        GoToLineQuery.resolve(query, totalLines: totalLines)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Go to Line (1–\(totalLines))…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .focused($fieldFocused)
                .onSubmit { submit() }

            if !query.isEmpty {
                Divider()
                HStack {
                    if let line = resolved {
                        Text("Go to line \(line)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Enter a line number")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 24)
        .onAppear { fieldFocused = true }
        .onKeyPress(.return) { submit(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func submit() {
        guard let line = resolved else { return }
        onGo(line)
    }
}
