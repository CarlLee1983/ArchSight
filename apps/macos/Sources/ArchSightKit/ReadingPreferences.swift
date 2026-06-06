import Foundation

public enum ReadingThemeID: String, CaseIterable, Codable, Sendable {
    case system
    case github
    case solarized
    case highContrast

    /// Human-readable label for pickers and settings.
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .github: return "GitHub"
        case .solarized: return "Solarized"
        case .highContrast: return "High Contrast"
        }
    }
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
public enum TabLayoutMode: String, CaseIterable, Codable, Sendable {
    case verticalList
    case horizontalTabs
    case both

    public var displayName: String {
        switch self {
        case .verticalList: return "Vertical Cards"
        case .horizontalTabs: return "Horizontal Tabs"
        case .both: return "Both Layouts"
        }
    }
}

public struct ReadingPreferences: Equatable, Sendable, Codable {
    public var theme: ReadingThemeID
    public var fontScale: Double
    public var lineSpacing: LineSpacing
    public var tabLayoutMode: TabLayoutMode
    /// Soft-wrap long lines in the code view (VSCode ⌥Z). Default OFF, matching VSCode.
    public var wordWrap: Bool

    public init(theme: ReadingThemeID, fontScale: Double, lineSpacing: LineSpacing, tabLayoutMode: TabLayoutMode = .verticalList, wordWrap: Bool = false) {
        self.theme = theme
        self.fontScale = fontScale
        self.lineSpacing = lineSpacing
        self.tabLayoutMode = tabLayoutMode
        self.wordWrap = wordWrap
    }

    public static let `default` = ReadingPreferences(theme: .system, fontScale: 1.0, lineSpacing: .normal, tabLayoutMode: .verticalList, wordWrap: false)

    private enum CodingKeys: String, CodingKey {
        case theme
        case fontScale
        case lineSpacing
        case tabLayoutMode
        case wordWrap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decode(ReadingThemeID.self, forKey: .theme)
        self.fontScale = try container.decode(Double.self, forKey: .fontScale)
        self.lineSpacing = try container.decode(LineSpacing.self, forKey: .lineSpacing)
        self.tabLayoutMode = try container.decodeIfPresent(TabLayoutMode.self, forKey: .tabLayoutMode) ?? .verticalList
        self.wordWrap = try container.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(tabLayoutMode, forKey: .tabLayoutMode)
        try container.encode(wordWrap, forKey: .wordWrap)
    }

    /// Discrete font scale steps used by the A- / A+ controls.
    public static let fontScaleSteps: [Double] = [0.85, 1.0, 1.15, 1.3, 1.5]

    /// Smallest / largest available font scale, derived from `fontScaleSteps`.
    public static let minFontScale: Double = fontScaleSteps.first ?? 1.0
    public static let maxFontScale: Double = fontScaleSteps.last ?? 1.0

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
