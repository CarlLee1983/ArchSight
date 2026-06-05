import SwiftUI
import ArchSightKit
import Foundation

struct HorizontalTabBar: View {
    let openTabs: [FileTab]
    @Binding var selectedTabID: FileTab.ID?
    let onCloseTab: (FileTab.ID) -> Void

    @State private var hoveredTabID: FileTab.ID?

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
                            ArchSightIcon.Close(color: isSelected ? .primary : .secondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Close Tab")
                        .opacity(isSelected ? 0.8 : (hoveredTabID == tab.id ? 0.6 : 0.4))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        isSelected 
                            ? Color(NSColor.textBackgroundColor) 
                            : (hoveredTabID == tab.id ? Color(NSColor.quaternaryLabelColor).opacity(0.3) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        if isHovering {
                            hoveredTabID = tab.id
                        } else if hoveredTabID == tab.id {
                            hoveredTabID = nil
                        }
                    }
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
