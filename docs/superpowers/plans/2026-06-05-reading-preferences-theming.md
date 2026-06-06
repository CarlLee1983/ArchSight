# 閱讀偏好與主題化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 Markdown 預覽與程式碼檢視共用一套可切換主題、可調字級與行距、並持久化的閱讀偏好，透過內容區工具列與 Settings 視窗操作。

**Architecture:** 在 `ArchSightKit` 以純值型別定義偏好與主題（單一事實來源），同時餵給 Markdown 的 CSS 變數與程式碼檢視的 `NSColor`。`.system` 主題沿用動態系統色維持自動淺/深。持久化用 `@Observable` store（Kit，注入 `UserDefaults` 可測），UI 用 SwiftUI 工具列 + `Settings` scene 綁同一 store。

**Tech Stack:** Swift 6 / SwiftPM、SwiftUI、AppKit（`NSTextView`/`NSColor`）、WebKit（`WKWebView`）、Observation、XCTest。

工作目錄：`apps/macos`。所有 `swift` 指令在該目錄執行。

---

## 檔案結構

**新增（Kit）**
- `Sources/ArchSightKit/ReadingPreferences.swift` — `ReadingThemeID`、`LineSpacing`、`ReadingPreferences`、字級步進。
- `Sources/ArchSightKit/ReadingTheme.swift` — `ReadingPalette`、`ReadingTheme`、catalog、`RGBA` hex 解析。
- `Sources/ArchSightKit/ReadingPreferencesStore.swift` — `@Observable` 持久化 store。

**新增（App）**
- `Sources/ArchSightApp/ReadingThemeAppKit.swift` — `ReadingTheme` → `NSFont`/`NSColor`/`NSParagraphStyle`。
- `Sources/ArchSightApp/ReadingControlsView.swift` — 共用工具列控制（主題、A-/A+、行距）。
- `Sources/ArchSightApp/ReadingSettingsView.swift` — Settings 視窗內容。

**修改**
- `Sources/ArchSightKit/MarkdownPreviewHTML.swift` — `render(_:preferences:)` + CSS 變數。
- `Sources/ArchSightApp/CodeTextView.swift` — 吃 preferences（font/lineSpacing/colors）。
- `Sources/ArchSightApp/MarkdownPreviewView.swift` — 吃 preferences、背景切換。
- `Sources/ArchSightApp/ContentView.swift` — 注入 store、放工具列、傳 preferences。
- `Sources/ArchSightApp/ArchSightApp.swift` — 建 store、`.environment`、`Settings` scene。

**測試（Kit）**
- `Tests/ArchSightKitTests/ReadingPreferencesTests.swift`
- `Tests/ArchSightKitTests/ReadingThemeTests.swift`
- `Tests/ArchSightKitTests/ReadingPreferencesStoreTests.swift`
- `Tests/ArchSightKitTests/MarkdownPreviewHTMLTests.swift`（既有，新增案例）

---

# Phase 1 — 核心模型（純 Kit，TDD）

## Task 1: ReadingThemeID 與 LineSpacing

**Files:**
- Create: `Sources/ArchSightKit/ReadingPreferences.swift`
- Test: `Tests/ArchSightKitTests/ReadingPreferencesTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ArchSightKitTests/ReadingPreferencesTests.swift`:
```swift
import XCTest
@testable import ArchSightKit

final class ReadingPreferencesTests: XCTestCase {
    func testThemeIDsAreStableAndComplete() {
        XCTAssertEqual(
            ReadingThemeID.allCases,
            [.system, .github, .solarized, .highContrast]
        )
        XCTAssertEqual(ReadingThemeID.github.rawValue, "github")
    }

    func testLineSpacingMapsToCSSAndMultiple() {
        XCTAssertEqual(LineSpacing.compact.cssLineHeight, 1.4, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.normal.cssLineHeight, 1.55, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.relaxed.cssLineHeight, 1.8, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.compact.lineHeightMultiple, 1.0, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.relaxed.lineHeightMultiple, 1.45, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.compact.textInset, 6, accuracy: 0.001)
        XCTAssertEqual(LineSpacing.relaxed.textInset, 12, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReadingPreferencesTests`
Expected: FAIL（`cannot find 'ReadingThemeID' in scope`）。

- [ ] **Step 3: Write minimal implementation**

`Sources/ArchSightKit/ReadingPreferences.swift`:
```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ReadingPreferencesTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightKit/ReadingPreferences.swift Tests/ArchSightKitTests/ReadingPreferencesTests.swift
git commit -m "feat: [macos] add ReadingThemeID and LineSpacing reading-pref enums"
```

---

## Task 2: ReadingPreferences 與字級步進

**Files:**
- Modify: `Sources/ArchSightKit/ReadingPreferences.swift`
- Test: `Tests/ArchSightKitTests/ReadingPreferencesTests.swift`

- [ ] **Step 1: Write the failing test**

在 `ReadingPreferencesTests` 內新增：
```swift
    func testDefaultPreferences() {
        let prefs = ReadingPreferences.default
        XCTAssertEqual(prefs.theme, .system)
        XCTAssertEqual(prefs.fontScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(prefs.lineSpacing, .normal)
    }

    func testFontSteppingClampsAtBounds() {
        var prefs = ReadingPreferences.default
        prefs = prefs.increasedFont()
        XCTAssertEqual(prefs.fontScale, 1.15, accuracy: 0.001)
        prefs = prefs.increasedFont().increasedFont().increasedFont().increasedFont()
        XCTAssertEqual(prefs.fontScale, 1.5, accuracy: 0.001) // clamps at top
        prefs = ReadingPreferences.default
        prefs = prefs.decreasedFont().decreasedFont()
        XCTAssertEqual(prefs.fontScale, 0.85, accuracy: 0.001) // clamps at bottom
    }

    func testNormalizedSnapsArbitraryScaleToNearestStep() {
        let messy = ReadingPreferences(theme: .github, fontScale: 1.22, lineSpacing: .compact)
        XCTAssertEqual(messy.normalized().fontScale, 1.15, accuracy: 0.001)
        XCTAssertEqual(ReadingPreferences(theme: .system, fontScale: 9.0, lineSpacing: .normal)
            .normalized().fontScale, 1.5, accuracy: 0.001)
    }

    func testCodableRoundTrip() throws {
        let prefs = ReadingPreferences(theme: .solarized, fontScale: 1.3, lineSpacing: .relaxed)
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ReadingPreferences.self, from: data)
        XCTAssertEqual(decoded, prefs)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReadingPreferencesTests`
Expected: FAIL（`ReadingPreferences` 未定義）。

- [ ] **Step 3: Write minimal implementation**

在 `Sources/ArchSightKit/ReadingPreferences.swift` 末端新增：
```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ReadingPreferencesTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightKit/ReadingPreferences.swift Tests/ArchSightKitTests/ReadingPreferencesTests.swift
git commit -m "feat: [macos] add ReadingPreferences with font stepping and normalization"
```

---

## Task 3: ReadingPalette、ReadingTheme、catalog

**Files:**
- Create: `Sources/ArchSightKit/ReadingTheme.swift`
- Test: `Tests/ArchSightKitTests/ReadingThemeTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ArchSightKitTests/ReadingThemeTests.swift`:
```swift
import XCTest
@testable import ArchSightKit

final class ReadingThemeTests: XCTestCase {
    func testCatalogCoversEveryThemeID() {
        let ids = ReadingTheme.catalog.map(\.id)
        XCTAssertEqual(ids, ReadingThemeID.allCases)
    }

    func testThemeLookupReturnsMatchingID() {
        XCTAssertEqual(ReadingTheme.theme(for: .solarized).id, .solarized)
    }

    func testSystemThemeIsDynamicAndOthersAreNot() {
        XCTAssertTrue(ReadingTheme.theme(for: .system).isDynamic)
        XCTAssertFalse(ReadingTheme.theme(for: .github).isDynamic)
        XCTAssertEqual(ReadingTheme.theme(for: .github).appearance, .light)
        XCTAssertEqual(ReadingTheme.theme(for: .solarized).appearance, .dark)
    }

    func testNamedThemePaletteUsesHexColors() {
        let github = ReadingTheme.theme(for: .github)
        XCTAssertEqual(github.palette.background, "#ffffff")
        XCTAssertEqual(github.palette.foreground, "#1f2328")
        XCTAssertEqual(github.cssColorScheme, "light")
    }

    func testSyntaxColorLookupCoversCanonicalTypes() {
        let p = ReadingTheme.theme(for: .github).palette
        XCTAssertEqual(p.syntaxColor(for: "keyword"), p.keyword)
        XCTAssertEqual(p.syntaxColor(for: "string"), p.string)
        XCTAssertEqual(p.syntaxColor(for: "unknown"), p.foreground) // fallback
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReadingThemeTests`
Expected: FAIL（`ReadingTheme` 未定義）。

- [ ] **Step 3: Write minimal implementation**

`Sources/ArchSightKit/ReadingTheme.swift`:
```swift
import Foundation

public enum ThemeAppearance: String, Sendable {
    case light
    case dark
    case system
}

public struct ReadingPalette: Equatable, Sendable {
    public let background: String
    public let foreground: String
    public let secondaryText: String
    public let border: String
    public let blockquote: String
    public let codeBackground: String
    public let keyword: String
    public let string: String
    public let comment: String
    public let number: String
    public let function: String
    public let type: String
    public let op: String

    /// Maps a canonical syntax token type to its hex color, mirroring
    /// `CodeTextView.color(for:)`. Falls back to `foreground`.
    public func syntaxColor(for type: String) -> String {
        switch type {
        case "keyword": return keyword
        case "string": return string
        case "comment": return comment
        case "number", "constant": return number
        case "function": return function
        case "type": return self.type
        case "operator": return op
        default: return foreground
        }
    }
}

public struct ReadingTheme: Sendable {
    public let id: ReadingThemeID
    public let appearance: ThemeAppearance
    public let palette: ReadingPalette

    /// `.system` follows the OS appearance via dynamic colors; adapters emit
    /// system color tokens instead of the placeholder hex palette.
    public var isDynamic: Bool { id == .system }

    /// CSS `color-scheme` value so form controls / scrollbars match the theme.
    public var cssColorScheme: String {
        switch appearance {
        case .light: return "light"
        case .dark: return "dark"
        case .system: return "light dark"
        }
    }

    public static func theme(for id: ReadingThemeID) -> ReadingTheme {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    public static let catalog: [ReadingTheme] = [
        ReadingTheme(
            id: .system,
            appearance: .system,
            palette: ReadingPalette(
                background: "#ffffff", foreground: "#000000", secondaryText: "#3c3c43",
                border: "#d0d0d0", blockquote: "#3c3c43", codeBackground: "#f5f5f5",
                keyword: "#cf222e", string: "#0a3069", comment: "#6e7781",
                number: "#0550ae", function: "#8250df", type: "#953800", op: "#1f2328"
            )
        ),
        ReadingTheme(
            id: .github,
            appearance: .light,
            palette: ReadingPalette(
                background: "#ffffff", foreground: "#1f2328", secondaryText: "#59636e",
                border: "#d1d9e0", blockquote: "#59636e", codeBackground: "#f6f8fa",
                keyword: "#cf222e", string: "#0a3069", comment: "#59636e",
                number: "#0550ae", function: "#8250df", type: "#953800", op: "#1f2328"
            )
        ),
        ReadingTheme(
            id: .solarized,
            appearance: .dark,
            palette: ReadingPalette(
                background: "#002b36", foreground: "#93a1a1", secondaryText: "#657b83",
                border: "#073642", blockquote: "#839496", codeBackground: "#073642",
                keyword: "#859900", string: "#2aa198", comment: "#586e75",
                number: "#d33682", function: "#268bd2", type: "#b58900", op: "#93a1a1"
            )
        ),
        ReadingTheme(
            id: .highContrast,
            appearance: .dark,
            palette: ReadingPalette(
                background: "#000000", foreground: "#ffffff", secondaryText: "#c0c0c0",
                border: "#ffffff", blockquote: "#e0e0e0", codeBackground: "#1a1a1a",
                keyword: "#ff8cc6", string: "#ff6b6b", comment: "#b0b0b0",
                number: "#ffb86c", function: "#6bc7ff", type: "#d39bff", op: "#ffffff"
            )
        ),
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ReadingThemeTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightKit/ReadingTheme.swift Tests/ArchSightKitTests/ReadingThemeTests.swift
git commit -m "feat: [macos] add ReadingTheme palette catalog"
```

---

## Task 4: RGBA hex 解析（供 AppKit adapter 使用）

**Files:**
- Modify: `Sources/ArchSightKit/ReadingTheme.swift`
- Test: `Tests/ArchSightKitTests/ReadingThemeTests.swift`

- [ ] **Step 1: Write the failing test**

在 `ReadingThemeTests` 內新增：
```swift
    func testRGBAParsesSixDigitHex() {
        let color = RGBA(hex: "#268bd2")
        XCTAssertNotNil(color)
        XCTAssertEqual(color!.red, 0x26 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color!.green, 0x8b / 255.0, accuracy: 0.001)
        XCTAssertEqual(color!.blue, 0xd2 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color!.alpha, 1.0, accuracy: 0.001)
    }

    func testRGBAAcceptsHexWithoutHashAndIsCaseInsensitive() {
        XCTAssertEqual(RGBA(hex: "FFFFFF"), RGBA(hex: "#ffffff"))
    }

    func testRGBARejectsMalformedHex() {
        XCTAssertNil(RGBA(hex: "#12"))
        XCTAssertNil(RGBA(hex: "#gggggg"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReadingThemeTests`
Expected: FAIL（`RGBA` 未定義）。

- [ ] **Step 3: Write minimal implementation**

在 `Sources/ArchSightKit/ReadingTheme.swift` 末端新增：
```swift
public struct RGBA: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// Parses `#rrggbb` (with or without leading `#`, case-insensitive).
    /// Returns nil for any other format.
    public init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6,
              let int = UInt32(value, radix: 16)
        else { return nil }
        red = Double((int >> 16) & 0xff) / 255.0
        green = Double((int >> 8) & 0xff) / 255.0
        blue = Double(int & 0xff) / 255.0
        alpha = 1.0
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ReadingThemeTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightKit/ReadingTheme.swift Tests/ArchSightKitTests/ReadingThemeTests.swift
git commit -m "feat: [macos] add RGBA hex parser for theme colors"
```

---

## Task 5: MarkdownPreviewHTML 吃 preferences 輸出 CSS 變數

**Files:**
- Modify: `Sources/ArchSightKit/MarkdownPreviewHTML.swift`
- Test: `Tests/ArchSightKitTests/MarkdownPreviewHTMLTests.swift`

- [ ] **Step 1: Write the failing test**

在 `MarkdownPreviewHTMLTests` 內新增：
```swift
    func testLegacyRenderUsesSystemDefaults() {
        let html = MarkdownPreviewHTML.render("# Hi")
        XCTAssertTrue(html.contains("--font-scale: 1.0"))
        XCTAssertTrue(html.contains("--bg: Canvas"))
        XCTAssertTrue(html.contains("--fg: CanvasText"))
    }

    func testPreferencesInjectScaleSpacingAndThemeColors() {
        let prefs = ReadingPreferences(theme: .github, fontScale: 1.3, lineSpacing: .relaxed)
        let html = MarkdownPreviewHTML.render("# Hi", preferences: prefs)
        XCTAssertTrue(html.contains("--font-scale: 1.3"))
        XCTAssertTrue(html.contains("--line-height: 1.8"))
        XCTAssertTrue(html.contains("--bg: #ffffff"))
        XCTAssertTrue(html.contains("--fg: #1f2328"))
        XCTAssertTrue(html.contains("color-scheme: light;"))
    }

    func testSystemThemeKeepsDynamicColorScheme() {
        let html = MarkdownPreviewHTML.render("# Hi", preferences: .default)
        XCTAssertTrue(html.contains("color-scheme: light dark;"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownPreviewHTMLTests`
Expected: FAIL（`render(_:preferences:)` 不存在）。

- [ ] **Step 3: Write minimal implementation**

在 `Sources/ArchSightKit/MarkdownPreviewHTML.swift`：

(a) 擴充 `MarkdownPreviewHTML` enum：
```swift
public enum MarkdownPreviewHTML {
    public static func render(_ markdown: String) -> String {
        render(markdown, preferences: .default)
    }

    public static func render(_ markdown: String, preferences: ReadingPreferences) -> String {
        var renderer = Renderer(markdown: markdown)
        return renderer.render(preferences: preferences)
    }
}
```

(b) `Renderer.render()` 改名帶參數並把 preferences 傳給 `document`：
```swift
    mutating func render(preferences: ReadingPreferences) -> String {
        var index = 0
        while index < lines.count {
            // …（迴圈內容不變）…
        }
        flushParagraph()
        return document(
            body: body.joined(separator: "\n"),
            usesMermaid: usesMermaid,
            preferences: preferences
        )
    }
```

(c) 改寫 `document(...)`：
```swift
private func document(body: String, usesMermaid: Bool, preferences: ReadingPreferences) -> String {
    let theme = ReadingTheme.theme(for: preferences.theme)
    """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root {
          color-scheme: \(theme.cssColorScheme);
    \(cssVariables(theme: theme, preferences: preferences))
        }
        body {
          margin: 0;
          padding: 16px 20px 32px;
          font-family: -apple-system, system-ui, sans-serif;
          font-size: calc(16px * var(--font-scale));
          color: var(--fg);
          background: var(--bg);
          line-height: var(--line-height);
        }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.1em 0 0.45em; }
        h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
        p, ul, blockquote, pre { margin: 0.8em 0; }
        code, pre {
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          font-size: calc(12px * var(--font-scale));
        }
        pre {
          overflow: auto;
          padding: 10px 12px;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--code-bg);
        }
        blockquote {
          border-left: 3px solid var(--quote-bar);
          padding-left: 12px;
          color: var(--blockquote);
        }
        .mermaid { text-align: center; background: var(--bg); }
      </style>
    </head>
    <body>
    \(body)
    \(mermaidScript(usesMermaid: usesMermaid))
    </body>
    </html>
    """
}

private func cssVariables(theme: ReadingTheme, preferences: ReadingPreferences) -> String {
    let p = theme.palette
    func value(_ hex: String, dynamic: String) -> String {
        theme.isDynamic ? dynamic : hex
    }
    let lines = [
        "--bg: \(value(p.background, dynamic: "Canvas"));",
        "--fg: \(value(p.foreground, dynamic: "CanvasText"));",
        "--code-bg: \(value(p.codeBackground, dynamic: "color-mix(in srgb, CanvasText 6%, Canvas)"));",
        "--border: \(value(p.border, dynamic: "color-mix(in srgb, CanvasText 18%, transparent)"));",
        "--quote-bar: \(value(p.border, dynamic: "color-mix(in srgb, CanvasText 25%, transparent)"));",
        "--blockquote: \(value(p.blockquote, dynamic: "color-mix(in srgb, CanvasText 72%, transparent)"));",
        "--font-scale: \(preferences.fontScale);",
        "--line-height: \(preferences.lineSpacing.cssLineHeight);",
    ]
    return lines.map { "      " + $0 }.joined(separator: "\n")
}
```
> 注意：`document(...)` 是多行字串 expression body，務必保留開頭的 `"""` 即為回傳值（與既有寫法一致，無 `return`）。

- [ ] **Step 4: Run full Kit tests to verify pass + no regression**

Run: `swift test`
Expected: PASS（含既有 `testRendersBasicMarkdownAsHTMLDocument` 等三案維持綠燈）。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightKit/MarkdownPreviewHTML.swift Tests/ArchSightKitTests/MarkdownPreviewHTMLTests.swift
git commit -m "feat: [macos] render Markdown preview with themed CSS variables"
```

---

# Phase 2 — 持久化 + Code view adapter

## Task 6: ReadingPreferencesStore（@Observable，注入 UserDefaults）

**Files:**
- Create: `Sources/ArchSightKit/ReadingPreferencesStore.swift`
- Test: `Tests/ArchSightKitTests/ReadingPreferencesStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ArchSightKitTests/ReadingPreferencesStoreTests.swift`:
```swift
import XCTest
@testable import ArchSightKit

final class ReadingPreferencesStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.reading.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshStoreStartsAtDefaults() {
        let store = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences, .default)
    }

    func testMutationsPersistAcrossStores() {
        let store = ReadingPreferencesStore(defaults: defaults)
        store.setTheme(.github)
        store.increaseFont()
        store.setLineSpacing(.relaxed)

        let reloaded = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.theme, .github)
        XCTAssertEqual(reloaded.preferences.fontScale, 1.15, accuracy: 0.001)
        XCTAssertEqual(reloaded.preferences.lineSpacing, .relaxed)
    }

    func testCorruptStorageFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "reading.preferences")
        let store = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences, .default)
    }

    func testLoadedScaleIsNormalized() throws {
        let messy = ReadingPreferences(theme: .system, fontScale: 1.22, lineSpacing: .normal)
        defaults.set(try JSONEncoder().encode(messy), forKey: "reading.preferences")
        let store = ReadingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences.fontScale, 1.15, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReadingPreferencesStoreTests`
Expected: FAIL（`ReadingPreferencesStore` 未定義）。

- [ ] **Step 3: Write minimal implementation**

`Sources/ArchSightKit/ReadingPreferencesStore.swift`:
```swift
import Foundation
import Observation

/// Observable, persistent holder for `ReadingPreferences`. Mutations route
/// through the explicit setters so persistence stays in one place (no reliance
/// on `didSet` semantics under the `@Observable` macro).
@Observable
public final class ReadingPreferencesStore {
    public private(set) var preferences: ReadingPreferences

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "reading.preferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Self.loadPreferences(from: defaults)
    }

    public func setTheme(_ id: ReadingThemeID) {
        update { $0.theme = id }
    }

    public func setLineSpacing(_ spacing: LineSpacing) {
        update { $0.lineSpacing = spacing }
    }

    public func increaseFont() {
        preferences = preferences.increasedFont()
        persist()
    }

    public func decreaseFont() {
        preferences = preferences.decreasedFont()
        persist()
    }

    private func update(_ mutate: (inout ReadingPreferences) -> Void) {
        var copy = preferences
        mutate(&copy)
        preferences = copy
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func loadPreferences(from defaults: UserDefaults) -> ReadingPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ReadingPreferences.self, from: data)
        else {
            return .default
        }
        return decoded.normalized()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ReadingPreferencesStoreTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightKit/ReadingPreferencesStore.swift Tests/ArchSightKitTests/ReadingPreferencesStoreTests.swift
git commit -m "feat: [macos] add observable persistent ReadingPreferencesStore"
```

---

## Task 7: ReadingThemeAppKit adapter + 套用到 CodeTextView

**Files:**
- Create: `Sources/ArchSightApp/ReadingThemeAppKit.swift`
- Modify: `Sources/ArchSightApp/CodeTextView.swift`

> App target 無單元測試；`RGBA` 解析已在 Task 4 測過。本任務以 `swift build` 與後續手動驗證把關。

- [ ] **Step 1: 建立 AppKit adapter**

`Sources/ArchSightApp/ReadingThemeAppKit.swift`:
```swift
import AppKit
import ArchSightKit

/// Bridges a value-type `ReadingTheme` to AppKit drawing primitives for the
/// code view. Dynamic (`.system`) themes return the existing dynamic system
/// colors so light/dark continues to follow the OS automatically.
enum ReadingThemeAppKit {
    static func font(scale: Double) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 12 * scale, weight: .regular)
    }

    static func backgroundColor(for theme: ReadingTheme) -> NSColor {
        theme.isDynamic ? .textBackgroundColor : color(hex: theme.palette.background)
    }

    static func foregroundColor(for theme: ReadingTheme) -> NSColor {
        theme.isDynamic ? .labelColor : color(hex: theme.palette.foreground)
    }

    static func syntaxColor(for type: String, theme: ReadingTheme) -> NSColor {
        if theme.isDynamic {
            return dynamicSyntaxColor(for: type)
        }
        return color(hex: theme.palette.syntaxColor(for: type))
    }

    static func paragraphStyle(for lineSpacing: LineSpacing) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineSpacing.lineHeightMultiple
        return style
    }

    /// Mirrors the original `CodeTextView.color(for:)` mapping.
    private static func dynamicSyntaxColor(for type: String) -> NSColor {
        switch type {
        case "keyword": return .systemPink
        case "string": return .systemRed
        case "comment": return .secondaryLabelColor
        case "number", "constant": return .systemOrange
        case "function": return .systemBlue
        case "type": return .systemPurple
        case "operator": return .secondaryLabelColor
        default: return .labelColor
        }
    }

    static func color(hex: String) -> NSColor {
        guard let rgba = RGBA(hex: hex) else { return .labelColor }
        return NSColor(
            srgbRed: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            alpha: rgba.alpha
        )
    }
}
```

- [ ] **Step 2: 讓 CodeTextView 吃 preferences**

在 `Sources/ArchSightApp/CodeTextView.swift`：

(a) 新增屬性、移除 `static let codeFont`、刪除舊 `static func color(for:)`：
```swift
struct CodeTextView: NSViewRepresentable {
    let content: String
    var tokens: [SyntaxToken] = []
    var preferences: ReadingPreferences = .default
    var scrollToLine: Int?
    var onDefinition: (Int, Int) -> Void
    var onReferences: (Int, Int) -> Void

    private var theme: ReadingTheme { ReadingTheme.theme(for: preferences.theme) }
    private var codeFont: NSFont { ReadingThemeAppKit.font(scale: preferences.fontScale) }
```

(b) `makeNSView` 內套用字體/內距/背景：
```swift
        textView.font = codeFont
        textView.backgroundColor = ReadingThemeAppKit.backgroundColor(for: theme)
        let inset = preferences.lineSpacing.textInset
        textView.textContainerInset = NSSize(width: inset, height: inset)
```

(c) `updateNSView` 內：強制隨 preferences 重套樣式（不能只靠 `string != content`，否則改字級不重繪）。把建立 attributed string 抽成隨 preferences 與內容都會更新的流程：
```swift
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeNSTextView else {
            return
        }
        context.coordinator.onDefinition = onDefinition
        context.coordinator.onReferences = onReferences

        let signature = "\(preferences.theme.rawValue)|\(preferences.fontScale)|\(preferences.lineSpacing.rawValue)"
        if textView.string != content || context.coordinator.lastStyleSignature != signature {
            let paragraph = ReadingThemeAppKit.paragraphStyle(for: preferences.lineSpacing)
            let attributed = NSMutableAttributedString(
                string: content,
                attributes: [
                    .font: codeFont,
                    .foregroundColor: ReadingThemeAppKit.foregroundColor(for: theme),
                    .paragraphStyle: paragraph,
                ]
            )
            for span in SyntaxHighlighting.spans(for: tokens, in: content) where NSMaxRange(span.range) <= attributed.length {
                attributed.addAttribute(
                    .foregroundColor,
                    value: ReadingThemeAppKit.syntaxColor(for: span.type, theme: theme),
                    range: span.range
                )
            }
            textView.textStorage?.setAttributedString(attributed)
            textView.backgroundColor = ReadingThemeAppKit.backgroundColor(for: theme)
            textView.font = codeFont
            let inset = preferences.lineSpacing.textInset
            textView.textContainerInset = NSSize(width: inset, height: inset)
            textView.lastScrolledLine = nil
            context.coordinator.lastStyleSignature = signature
        }
        if let line = scrollToLine, line != textView.lastScrolledLine {
            textView.scrollToLine(line)
            textView.lastScrolledLine = line
        }
    }
```

(d) `Coordinator` 加欄位：
```swift
    final class Coordinator {
        var onDefinition: (Int, Int) -> Void = { _, _ in }
        var onReferences: (Int, Int) -> Void = { _, _ in }
        var lastStyleSignature: String?
    }
```

> 注意：`SyntaxHighlightingTests` 等若引用了 `CodeTextView.color(for:)` 會編譯失敗。它是 App target 的型別、Kit 測試不會引用；若 grep 到引用處，改用 `ReadingThemeAppKit.syntaxColor(for:theme:)`（`.system` 主題行為等價）。

- [ ] **Step 3: Build 驗證**

Run: `swift build`
Expected: 編譯成功，無對 `Self.codeFont` / `Self.color(for:)` 的殘留引用。
若失敗：依錯誤逐一修正殘留引用，再重跑。

- [ ] **Step 4: 全測試確認無回歸**

Run: `swift test`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightApp/ReadingThemeAppKit.swift Sources/ArchSightApp/CodeTextView.swift
git commit -m "feat: [macos] theme the code view via ReadingThemeAppKit adapter"
```

---

# Phase 3 — UI 接線

## Task 8: 建立 store、注入 environment、加 Settings scene

**Files:**
- Modify: `Sources/ArchSightApp/ArchSightApp.swift`
- Create: `Sources/ArchSightApp/ReadingSettingsView.swift`（先放佔位本任務僅注入，內容在 Task 11 完成）

- [ ] **Step 1: 在 App 建立並注入 store**

`Sources/ArchSightApp/ArchSightApp.swift`:
```swift
import ArchSightKit
import SwiftUI

@main
struct ArchSightApp: App {
    @State private var readingPreferences = ReadingPreferencesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(readingPreferences)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            ReadingSettingsView()
                .environment(readingPreferences)
        }
    }
}
```

- [ ] **Step 2: 暫時的 ReadingSettingsView 佔位（讓專案可編譯）**

`Sources/ArchSightApp/ReadingSettingsView.swift`:
```swift
import ArchSightKit
import SwiftUI

struct ReadingSettingsView: View {
    @Environment(ReadingPreferencesStore.self) private var store

    var body: some View {
        Text("Reading settings")
            .padding()
            .frame(width: 360, height: 200)
    }
}
```

- [ ] **Step 3: Build 驗證**

Run: `swift build`
Expected: 編譯成功。

- [ ] **Step 4: Commit**

```bash
git add Sources/ArchSightApp/ArchSightApp.swift Sources/ArchSightApp/ReadingSettingsView.swift
git commit -m "feat: [macos] inject ReadingPreferencesStore and add Settings scene"
```

---

## Task 9: MarkdownPreviewView 吃 preferences + 背景切換

**Files:**
- Modify: `Sources/ArchSightApp/MarkdownPreviewView.swift`

- [ ] **Step 1: 讓 preview 吃 preferences 並依主題切背景**

`Sources/ArchSightApp/MarkdownPreviewView.swift`:
```swift
import ArchSightKit
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let content: String
    var preferences: ReadingPreferences = .default

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Named themes paint their own background via CSS; the system theme stays
        // transparent so it sits flush on the SwiftUI background.
        let theme = ReadingTheme.theme(for: preferences.theme)
        webView.setValue(!theme.isDynamic, forKey: "drawsBackground")

        let html = MarkdownPreviewHTML.render(content, preferences: preferences)
        guard context.coordinator.lastHTML != html else {
            return
        }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: URL(string: "https://archsight.local/"))
    }

    final class Coordinator {
        var lastHTML: String?
    }
}
```

- [ ] **Step 2: Build 驗證**

Run: `swift build`
Expected: 編譯成功（`ContentView` 仍以舊呼叫 `MarkdownPreviewView(content:)`，因 `preferences` 有預設值故不報錯）。

- [ ] **Step 3: Commit**

```bash
git add Sources/ArchSightApp/MarkdownPreviewView.swift
git commit -m "feat: [macos] feed reading preferences into Markdown preview"
```

---

## Task 10: 共用工具列控制 + 接到 ContentView

**Files:**
- Create: `Sources/ArchSightApp/ReadingControlsView.swift`
- Modify: `Sources/ArchSightApp/ContentView.swift`

- [ ] **Step 1: 建立工具列控制**

`Sources/ArchSightApp/ReadingControlsView.swift`:
```swift
import ArchSightKit
import SwiftUI

/// Compact reading controls (theme, font size, line spacing) shared by the
/// Markdown preview and the code view. Binds the shared store so every surface
/// and the Settings window stay in sync.
struct ReadingControlsView: View {
    @Environment(ReadingPreferencesStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Picker("Theme", selection: themeBinding) {
                ForEach(ReadingThemeID.allCases, id: \.self) { id in
                    Text(label(for: id)).tag(id)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .help("Reading theme")

            HStack(spacing: 2) {
                Button { store.decreaseFont() } label: { Image(systemName: "textformat.size.smaller") }
                    .disabled(store.preferences.fontScale <= ReadingPreferences.fontScaleSteps.first!)
                    .help("Decrease text size")
                Button { store.increaseFont() } label: { Image(systemName: "textformat.size.larger") }
                    .disabled(store.preferences.fontScale >= ReadingPreferences.fontScaleSteps.last!)
                    .help("Increase text size")
            }

            Picker("Line spacing", selection: lineSpacingBinding) {
                Image(systemName: "text.justify").tag(LineSpacing.compact)
                Image(systemName: "text.justifyleft").tag(LineSpacing.normal)
                Image(systemName: "list.bullet").tag(LineSpacing.relaxed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            .help("Line spacing")
        }
    }

    private var themeBinding: Binding<ReadingThemeID> {
        Binding(get: { store.preferences.theme }, set: { store.setTheme($0) })
    }

    private var lineSpacingBinding: Binding<LineSpacing> {
        Binding(get: { store.preferences.lineSpacing }, set: { store.setLineSpacing($0) })
    }

    private func label(for id: ReadingThemeID) -> String {
        switch id {
        case .system: return "System"
        case .github: return "GitHub"
        case .solarized: return "Solarized"
        case .highContrast: return "High Contrast"
        }
    }
}
```

- [ ] **Step 2: 在 ContentView 讀 store 並把 preferences 傳給兩個檢視**

在 `Sources/ArchSightApp/ContentView.swift`：

(a) 在 `ContentView`（含 `@State private var markdownDisplayMode` 的同一型別）內新增環境讀取：
```swift
    @Environment(ReadingPreferencesStore.self) private var readingStore
```

(b) `filePane(for:scrollLine:)` 的 Markdown 分支，在既有 `HStack` 工具列右側加入控制，並把 preferences 傳給 preview：
```swift
        if tab.canPreviewMarkdown {
            VStack(spacing: 0) {
                HStack {
                    Picker("Markdown display", selection: $markdownDisplayMode) {
                        Label("Preview", systemImage: "doc.richtext")
                            .tag(MarkdownDisplayMode.preview)
                        Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                            .tag(MarkdownDisplayMode.source)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .help("Switch Markdown display")
                    Spacer()
                    ReadingControlsView()
                }
                .padding(6)
                Divider()

                switch markdownDisplayMode {
                case .preview:
                    MarkdownPreviewView(content: tab.content, preferences: readingStore.preferences)
                case .source:
                    codeView(for: tab, scrollLine: scrollLine)
                }
            }
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    ReadingControlsView()
                }
                .padding(6)
                Divider()
                codeView(for: tab, scrollLine: scrollLine)
            }
        }
```

(c) `codeView(for:scrollLine:)` 傳入 preferences：
```swift
    private func codeView(for tab: FileTab, scrollLine: Int?) -> some View {
        CodeTextView(
            content: tab.content,
            tokens: tab.tokens,
            preferences: readingStore.preferences,
            scrollToLine: scrollLine,
            onDefinition: { line, column in requestDefinition(on: tab, line: line, column: column) },
            onReferences: { line, column in requestReferences(on: tab, line: line, column: column) }
        )
    }
```

- [ ] **Step 3: Build 驗證**

Run: `swift build`
Expected: 編譯成功。
> 若 `ContentView` 本體是 `ContentView` 以外的子型別（例如分割成多個 struct），把 `@Environment` 加在實際持有 `filePane`/`codeView` 的型別上。

- [ ] **Step 4: 全測試確認無回歸**

Run: `swift test`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/ArchSightApp/ReadingControlsView.swift Sources/ArchSightApp/ContentView.swift
git commit -m "feat: [macos] add shared reading controls toolbar to file panes"
```

---

## Task 11: Settings 視窗完整內容

**Files:**
- Modify: `Sources/ArchSightApp/ReadingSettingsView.swift`

- [ ] **Step 1: 實作 Settings Form 與即時預覽**

`Sources/ArchSightApp/ReadingSettingsView.swift`:
```swift
import ArchSightKit
import SwiftUI

struct ReadingSettingsView: View {
    @Environment(ReadingPreferencesStore.self) private var store

    private static let sampleMarkdown = """
    # Sample heading

    Body text with **bold** and `inline code`.

    > A short blockquote.
    """

    var body: some View {
        Form {
            Picker("Theme", selection: themeBinding) {
                ForEach(ReadingThemeID.allCases, id: \.self) { id in
                    Text(label(for: id)).tag(id)
                }
            }

            Stepper(
                value: fontIndexBinding,
                in: 0...(ReadingPreferences.fontScaleSteps.count - 1)
            ) {
                Text(String(format: "Text size: %.0f%%", store.preferences.fontScale * 100))
            }

            Picker("Line spacing", selection: lineSpacingBinding) {
                Text("Compact").tag(LineSpacing.compact)
                Text("Normal").tag(LineSpacing.normal)
                Text("Relaxed").tag(LineSpacing.relaxed)
            }

            Section("Preview") {
                MarkdownPreviewView(
                    content: Self.sampleMarkdown,
                    preferences: store.preferences
                )
                .frame(height: 160)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
    }

    private var themeBinding: Binding<ReadingThemeID> {
        Binding(get: { store.preferences.theme }, set: { store.setTheme($0) })
    }

    private var lineSpacingBinding: Binding<LineSpacing> {
        Binding(get: { store.preferences.lineSpacing }, set: { store.setLineSpacing($0) })
    }

    /// Maps the discrete scale steps onto a Stepper index so each tick lands on
    /// a valid step and persists through the store.
    private var fontIndexBinding: Binding<Int> {
        Binding(
            get: {
                ReadingPreferences.fontScaleSteps.firstIndex(of: store.preferences.fontScale) ?? 1
            },
            set: { newIndex in
                let current = ReadingPreferences.fontScaleSteps.firstIndex(of: store.preferences.fontScale) ?? 1
                if newIndex > current { store.increaseFont() }
                else if newIndex < current { store.decreaseFont() }
            }
        )
    }

    private func label(for id: ReadingThemeID) -> String {
        switch id {
        case .system: return "System"
        case .github: return "GitHub"
        case .solarized: return "Solarized"
        case .highContrast: return "High Contrast"
        }
    }
}
```

- [ ] **Step 2: Build 驗證**

Run: `swift build`
Expected: 編譯成功。

- [ ] **Step 3: 手動驗證（一次到位）**

Run: `swift run ArchSight`
逐項確認：
1. 開一個 `.md` 檔 → 工具列出現主題/字級/行距控制。
2. 切 GitHub / Solarized / High Contrast → 預覽底色與文字色隨之改變；切回 System 恢復透明跟隨外觀。
3. 按 A+ / A- → 預覽與程式碼檢視字級同步變化，邊界時按鈕 disable。
4. 開一個非 `.md` 程式碼檔 → 同一列控制存在，主題/字級/行距即時套用到程式碼檢視。
5. `Cmd+,` 開 Settings → 改任一項，內容視窗同步更新（綁同一 store）。
6. 結束再 `swift run ArchSight` → 設定保留（持久化生效）。

- [ ] **Step 4: Commit**

```bash
git add Sources/ArchSightApp/ReadingSettingsView.swift
git commit -m "feat: [macos] complete reading preferences Settings window"
```

---

## 完成後

- 跑一次完整 `swift test` 與 `swift build` 確認綠燈。
- 視需要更新 `docs/` 內相關說明（若有檔案內容檢視的使用文件）。
