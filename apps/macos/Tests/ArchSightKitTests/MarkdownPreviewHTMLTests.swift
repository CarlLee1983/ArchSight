import XCTest
@testable import ArchSightKit

final class MarkdownPreviewHTMLTests: XCTestCase {
    func testRendersBasicMarkdownAsHTMLDocument() {
        let html = MarkdownPreviewHTML.render("""
        # Architecture

        This is **read-only**.
        """)

        XCTAssertTrue(html.contains("<h1>Architecture</h1>"))
        XCTAssertTrue(html.contains("<p>This is <strong>read-only</strong>.</p>"))
        XCTAssertTrue(html.contains("<!doctype html>"))
    }

    func testRendersMermaidFenceAsDiagramNode() {
        let html = MarkdownPreviewHTML.render("""
        ```mermaid
        graph TD
            A[Load] --> B[Preview]
        ```
        """)

        XCTAssertTrue(html.contains("<pre class=\"mermaid\">graph TD"))
        XCTAssertTrue(html.contains("A[Load] --&gt; B[Preview]"))
        XCTAssertTrue(html.contains("mermaid.initialize({ startOnLoad: false"))
        XCTAssertTrue(html.contains("await mermaid.run({ querySelector: '.mermaid'"))
    }

    func testEscapesRawHTMLAndNonMermaidCodeFences() {
        let html = MarkdownPreviewHTML.render("""
        <script>alert("x")</script>

        ```swift
        if a < b { print("safe") }
        ```
        """)

        XCTAssertTrue(html.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">if a &lt; b { print(&quot;safe&quot;) }"))
        XCTAssertFalse(html.contains("<script>alert(\"x\")</script>"))
    }

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
}
