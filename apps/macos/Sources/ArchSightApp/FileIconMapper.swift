import SwiftUI

enum FileIconMapper {
    static func iconName(for filename: String) -> String {
        let lower = filename.lowercased()
        if lower == "package.swift" || lower == "go.mod" || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
            return "doc.text.fill"
        }
        if lower.hasSuffix(".swift") {
            return "swift"
        } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
            return "doc.richtext"
        } else {
            return "doc.text"
        }
    }
    
    static func iconColor(for filename: String) -> Color {
        let lower = filename.lowercased()
        if lower == "package.swift" || lower == "go.mod" {
            return .purple
        }
        if lower.hasSuffix(".swift") {
            return .orange
        } else if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
            return .blue
        } else if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
            return .pink
        } else {
            return .secondary
        }
    }
}
