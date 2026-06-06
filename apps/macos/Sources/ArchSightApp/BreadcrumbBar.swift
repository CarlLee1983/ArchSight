import ArchSightKit
import SwiftUI

/// VSCode-style breadcrumb bar shown at the top of the editor pane. Renders the
/// open file's path as chevron-separated segments, the last carrying the file
/// icon and primary emphasis. Read-only (display only), matching ArchSight's
/// observation-cockpit stance. Hidden entirely when the path has no segments.
struct BreadcrumbBar: View {
    let path: String

    var body: some View {
        let segments = PathBreadcrumbs.segments(for: path)
        if segments.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        let isLast = index == segments.count - 1
                        if isLast {
                            FileIconMapper.iconType(for: segment).view()
                        }
                        Text(segment)
                            .font(.system(size: 11))
                            .foregroundStyle(isLast ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Color(NSColor.textBackgroundColor))

                Divider()
            }
        }
    }
}
