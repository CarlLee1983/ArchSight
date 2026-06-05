import Foundation

public enum MarkdownPreviewHTML {
    public static func render(_ markdown: String) -> String {
        render(markdown, preferences: .default)
    }

    public static func render(_ markdown: String, preferences: ReadingPreferences) -> String {
        var renderer = Renderer(markdown: markdown)
        return renderer.render(preferences: preferences)
    }
}

private struct Renderer {
    private let lines: [String]
    private var body: [String] = []
    private var paragraph: [String] = []
    private var usesMermaid = false

    init(markdown: String) {
        lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    mutating func render(preferences: ReadingPreferences) -> String {
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                index += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushParagraph()
                index = renderCodeFence(startingAt: index)
                continue
            }
            if let heading = headingHTML(for: line) {
                flushParagraph()
                body.append(heading)
                index += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                flushParagraph()
                index = renderUnorderedList(startingAt: index)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                flushParagraph()
                body.append("<blockquote>\(inlineHTML(String(line.trimmingCharacters(in: .whitespaces).dropFirst(2))))</blockquote>")
                index += 1
                continue
            }
            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return document(
            body: body.joined(separator: "\n"),
            usesMermaid: usesMermaid,
            preferences: preferences
        )
    }

    private mutating func renderCodeFence(startingAt start: Int) -> Int {
        let opening = lines[start].trimmingCharacters(in: .whitespaces)
        let language = String(opening.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        var codeLines: [String] = []
        var index = start + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            codeLines.append(lines[index])
            index += 1
        }

        let escapedCode = escapeHTML(codeLines.joined(separator: "\n"))
        if language.lowercased() == "mermaid" {
            usesMermaid = true
            body.append("<pre class=\"mermaid\">\(escapedCode)</pre>")
        } else {
            let className = language.isEmpty ? "" : " class=\"language-\(escapeAttribute(language))\""
            body.append("<pre><code\(className)>\(escapedCode)</code></pre>")
        }
        return index
    }

    private mutating func renderUnorderedList(startingAt start: Int) -> Int {
        var items: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { break }
            items.append("<li>\(inlineHTML(String(trimmed.dropFirst(2))))</li>")
            index += 1
        }
        body.append("<ul>\n\(items.joined(separator: "\n"))\n</ul>")
        return index
    }

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        body.append("<p>\(inlineHTML(paragraph.joined(separator: " ")))</p>")
        paragraph = []
    }

    private func headingHTML(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first == " "
        else {
            return nil
        }
        let text = String(trimmed.dropFirst(level + 1))
        return "<h\(level)>\(inlineHTML(text))</h\(level)>"
    }

    private func inlineHTML(_ markdown: String) -> String {
        var html = escapeHTML(markdown)
        html = replacePairedDelimiter("**", in: html, open: "<strong>", close: "</strong>")
        html = replacePairedDelimiter("`", in: html, open: "<code>", close: "</code>")
        return html
    }

    private func replacePairedDelimiter(_ delimiter: String, in text: String, open: String, close: String) -> String {
        let parts = text.components(separatedBy: delimiter)
        guard parts.count > 1 else { return text }
        var result = parts[0]
        for index in 1..<parts.count {
            result += index.isMultiple(of: 2) ? close : open
            result += parts[index]
        }
        return result
    }
}

private func document(body: String, usesMermaid: Bool, preferences: ReadingPreferences) -> String {
    let theme = ReadingTheme.theme(for: preferences.theme)
    return """
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

private func mermaidScript(usesMermaid: Bool) -> String {
    guard usesMermaid else { return "" }
    return """
    <script type="module">
      import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11.15.0/dist/mermaid.esm.min.mjs';
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default' });
      try {
        await mermaid.run({ querySelector: '.mermaid', suppressErrors: true });
      } catch (error) {
        console.error(error);
      }
    </script>
    """
}

private func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private func escapeAttribute(_ text: String) -> String {
    escapeHTML(text).replacingOccurrences(of: " ", with: "-")
}
