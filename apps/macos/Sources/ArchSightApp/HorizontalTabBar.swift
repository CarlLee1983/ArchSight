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
                    let filename = (tab.path as NSString).lastPathComponent
                    
                    HStack(spacing: 6) {
                        FileIconMapper.iconType(for: filename).view()
                        
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
}
