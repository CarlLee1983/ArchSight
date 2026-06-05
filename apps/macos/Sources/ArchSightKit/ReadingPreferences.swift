import Foundation

public enum ReadingThemeID: String, CaseIterable, Codable, Sendable {
    case system
    case github
    case solarized
    case highContrast
}

public enum LineSpacing: String, CaseIterable, Codable, Sendable {
    case compact
    case normal
    case relaxed

    /// CSS `line-height` for the Markdown preview.
    public var cssLineHeight: Double {
        switch self {
        case .compact: return 1.4
        case .normal: return 1.55
        case .relaxed: return 1.8
        }
    }

    /// `NSParagraphStyle.lineHeightMultiple` for the code view.
    public var lineHeightMultiple: Double {
        switch self {
        case .compact: return 1.0
        case .normal: return 1.2
        case .relaxed: return 1.45
        }
    }

    /// `textContainerInset` height/width for the code view.
    public var textInset: Double {
        switch self {
        case .compact: return 6
        case .normal: return 8
        case .relaxed: return 12
        }
    }
}
