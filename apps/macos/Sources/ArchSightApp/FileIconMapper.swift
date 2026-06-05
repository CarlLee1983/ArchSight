import SwiftUI
import ArchSightKit

public enum CustomIconType: Sendable {
    case folder
    case folderOpen
    case swift
    case markdown
    case config
    case defaultFile
    
    @ViewBuilder @MainActor
    public func view(color: Color? = nil) -> some View {
        switch self {
        case .folder:
            ArchSightIcon.Folder(color: color ?? .accentColor)
        case .folderOpen:
            ArchSightIcon.FolderOpen(color: color ?? .accentColor)
        case .swift:
            ArchSightIcon.File(color: color ?? .orange)
        case .markdown:
            ArchSightIcon.File(color: color ?? .blue)
        case .config:
            ArchSightIcon.File(color: color ?? .purple)
        case .defaultFile:
            ArchSightIcon.File(color: color ?? .secondary)
        }
    }
}

enum FileIconMapper {
    static func iconType(for filename: String) -> CustomIconType {
        let lower = filename.lowercased()
        if lower == "package.swift" || lower == "go.mod" || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
            return .config
        }
        if lower.hasSuffix(".swift") {
            return .swift
        } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
            return .markdown
        } else {
            return .defaultFile
        }
    }
}
