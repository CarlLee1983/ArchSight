import ArchSightKit
import SwiftUI

/// Empty-state shown in the editor pane when no workspace folder is open.
/// Offers an Open Folder action plus a clickable list of recently opened folders.
struct WelcomeView: View {
    let recents: [RecentFolder]
    let onOpenFolder: () -> Void
    let onOpenRecent: (String) -> Void
    let onRemoveRecent: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ArchSightIcon.FolderOpen(color: .accentColor)
                    .frame(width: 56, height: 56)
                Text("ArchSight")
                    .font(.title2.weight(.semibold))
                Button("Open Folder…", action: onOpenFolder)
                    .controlSize(.large)
            }

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    ForEach(recents) { folder in
                        RecentRow(
                            folder: folder,
                            onOpen: { onOpenRecent(folder.path) },
                            onRemove: { onRemoveRecent(folder.path) }
                        )
                    }
                }
                .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// One recent-folder row: name + abbreviated path, with a hover-revealed remove button.
private struct RecentRow: View {
    let folder: RecentFolder
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    private var abbreviatedPath: String {
        (folder.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 8) {
            ArchSightIcon.Folder(color: .accentColor)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                Text(abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from Recent")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.secondary.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
    }
}
