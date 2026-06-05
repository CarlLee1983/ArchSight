import SwiftUI
import ArchSightKit
import Foundation

struct HorizontalTabBar: View {
    let openTabs: [FileTab]
    @Binding var selectedTabID: FileTab.ID?
    let onCloseTab: (FileTab.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(openTabs) { tab in
                    let isSelected = selectedTabID == tab.id
                    let filename = URL(fileURLWithPath: tab.path).lastPathComponent
                    
                    HStack(spacing: 6) {
                        Image(systemName: fileIconName(for: filename))
                            .foregroundColor(fileIconColor(for: filename))
                            .font(.system(size: 11))
                        
                        Text(filename)
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                        
                        Button(action: {
                            onCloseTab(tab.id)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Close Tab")
                        .opacity(isSelected ? 0.8 : 0.4)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(isSelected ? Color(NSColor.textBackgroundColor) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTabID = tab.id
                    }
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                    
                    if tab.id != openTabs.last?.id {
                        Divider()
                            .frame(height: 20)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(height: 32)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            VStack {
                Spacer()
                Divider()
            }
        )
    }

    private func fileIconName(for filename: String) -> String {
        let lowercased = filename.lowercased()
        if lowercased == "package.swift" || lowercased == "go.mod" || lowercased.hasSuffix(".json") || lowercased.hasSuffix(".yaml") || lowercased.hasSuffix(".yml") {
            return "doc.text.fill"
        }
        if lowercased.hasSuffix(".swift") {
            return "swift"
        } else if lowercased.hasSuffix(".md") || lowercased.hasSuffix(".markdown") {
            return "doc.richtext"
        } else {
            return "doc.text"
        }
    }

    private func fileIconColor(for filename: String) -> Color {
        let lowercased = filename.lowercased()
        if lowercased == "package.swift" || lowercased == "go.mod" {
            return .purple
        }
        if lowercased.hasSuffix(".swift") {
            return .orange
        } else if lowercased.hasSuffix(".md") || lowercased.hasSuffix(".markdown") {
            return .blue
        } else if lowercased.hasSuffix(".json") || lowercased.hasSuffix(".yaml") || lowercased.hasSuffix(".yml") {
            return .pink
        } else {
            return .secondary
        }
    }
}
