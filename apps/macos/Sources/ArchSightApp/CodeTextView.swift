import AppKit
import ArchSightKit
import SwiftUI

/// A read-only, AppKit-backed code viewer. It renders monospaced text without any
/// editing affordances and turns Cmd+Click and a context menu into explicit
/// definition/references navigation requests, reporting 1-based line/column via
/// the tested `TextPosition` helper.
struct CodeTextView: NSViewRepresentable {
    let content: String
    var tokens: [SyntaxToken] = []
    var scrollToLine: Int?
    var onDefinition: (Int, Int) -> Void
    var onReferences: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// Maps a canonical token type to a dynamic system color so highlighting
    /// follows light/dark appearance automatically.
    static func color(for type: String) -> NSColor {
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

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CodeNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false  // disables RTF paste/string= attribute stripping; programmatic textStorage attributes still apply
        textView.drawsBackground = true
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = Self.codeFont
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.coordinator = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeNSTextView else {
            return
        }
        context.coordinator.onDefinition = onDefinition
        context.coordinator.onReferences = onReferences

        if textView.string != content {
            let attributed = NSMutableAttributedString(
                string: content,
                attributes: [
                    .font: Self.codeFont,
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            for span in SyntaxHighlighting.spans(for: tokens, in: content) where NSMaxRange(span.range) <= attributed.length {
                attributed.addAttribute(.foregroundColor, value: Self.color(for: span.type), range: span.range)
            }
            textView.textStorage?.setAttributedString(attributed)
            textView.lastScrolledLine = nil
        }
        if let line = scrollToLine, line != textView.lastScrolledLine {
            textView.scrollToLine(line)
            textView.lastScrolledLine = line
        }
    }

    final class Coordinator {
        var onDefinition: (Int, Int) -> Void = { _, _ in }
        var onReferences: (Int, Int) -> Void = { _, _ in }
    }
}

final class CodeNSTextView: NSTextView {
    weak var coordinator: CodeTextView.Coordinator?
    var lastScrolledLine: Int?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let position = position(for: event) {
            coordinator?.onDefinition(position.line, position.column)
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let definition = NSMenuItem(title: "Go to Definition", action: #selector(goToDefinition(_:)), keyEquivalent: "")
        let references = NSMenuItem(title: "Find References", action: #selector(findReferences(_:)), keyEquivalent: "")
        for item in [definition, references] {
            item.target = self
            if let position = position(for: event) {
                item.representedObject = [position.line, position.column]
            } else {
                item.isEnabled = false
            }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func goToDefinition(_ sender: NSMenuItem) {
        guard let position = sender.representedObject as? [Int], position.count == 2 else {
            return
        }
        coordinator?.onDefinition(position[0], position[1])
    }

    @objc private func findReferences(_ sender: NSMenuItem) {
        guard let position = sender.representedObject as? [Int], position.count == 2 else {
            return
        }
        coordinator?.onReferences(position[0], position[1])
    }

    private func position(for event: NSEvent) -> (line: Int, column: Int)? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard index >= 0 else {
            return nil
        }
        return TextPosition.lineColumn(forUTF16Offset: index, in: string)
    }

    func scrollToLine(_ line: Int) {
        let text = string as NSString
        var currentLine = 1
        var lineStart = 0
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, stop in
            if currentLine == line {
                lineStart = range.location
                stop.pointee = true
            }
            currentLine += 1
        }
        let target = NSRange(location: min(lineStart, text.length), length: 0)
        scrollRangeToVisible(target)
        setSelectedRange(target)
    }
}
