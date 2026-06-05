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

public struct ReadingPreferences: Equatable, Sendable, Codable {
    public var theme: ReadingThemeID
    public var fontScale: Double
    public var lineSpacing: LineSpacing

    public init(theme: ReadingThemeID, fontScale: Double, lineSpacing: LineSpacing) {
        self.theme = theme
        self.fontScale = fontScale
        self.lineSpacing = lineSpacing
    }

    public static let `default` = ReadingPreferences(theme: .system, fontScale: 1.0, lineSpacing: .normal)

    /// Discrete font scale steps used by the A- / A+ controls.
    public static let fontScaleSteps: [Double] = [0.85, 1.0, 1.15, 1.3, 1.5]

    public func increasedFont() -> ReadingPreferences {
        steppedFont(by: 1)
    }

    public func decreasedFont() -> ReadingPreferences {
        steppedFont(by: -1)
    }

    /// Snaps `fontScale` to the nearest valid step (used after decoding untrusted storage).
    public func normalized() -> ReadingPreferences {
        var copy = self
        copy.fontScale = Self.nearestStep(to: fontScale)
        return copy
    }

    private func steppedFont(by delta: Int) -> ReadingPreferences {
        let steps = Self.fontScaleSteps
        let current = Self.nearestStepIndex(to: fontScale)
        let next = min(max(current + delta, 0), steps.count - 1)
        var copy = self
        copy.fontScale = steps[next]
        return copy
    }

    private static func nearestStepIndex(to value: Double) -> Int {
        fontScaleSteps.enumerated().min { lhs, rhs in
            abs(lhs.element - value) < abs(rhs.element - value)
        }?.offset ?? 1
    }

    private static func nearestStep(to value: Double) -> Double {
        fontScaleSteps[nearestStepIndex(to: value)]
    }
}
