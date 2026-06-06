import AppKit
import ArchSightKit

/// A VSCode-style line-number gutter for the read-only code view. It draws only
/// the line numbers in the visible rect (NSRulerView redraws on scroll), and maps
/// character offsets to lines via a cached `LineStarts` so scrolling a large file
/// never rescans the buffer. Theme/font are pushed in by `CodeTextView`.
final class LineNumberRulerView: NSRulerView {
    private weak var codeTextView: NSTextView?
    private var lineStarts = LineStarts("")

    var gutterFont: NSFont = .monospacedSystemFont(ofSize: 10, weight: .regular) {
        didSet { needsDisplay = true }
    }
    var numberColor: NSColor = .secondaryLabelColor {
        didSet { needsDisplay = true }
    }
    var gutterBackgroundColor: NSColor = .textBackgroundColor {
        didSet { needsDisplay = true }
    }
    /// Full-opacity color for the caret's line number (VSCode highlights the active
    /// line number brighter than the dimmed rest). Set alongside `numberColor`.
    var currentNumberColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }
    /// 1-based line of the caret, or nil when unknown. Drives the active-line emphasis.
    var currentLine: Int? {
        didSet { if oldValue != currentLine { needsDisplay = true } }
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.codeTextView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuilds the cached line map and widens the gutter to fit the largest line
    /// number. Call whenever the open file's content changes.
    func refresh(for content: String) {
        lineStarts = LineStarts(content)
        let digits = max(2, String(lineStarts.lineCount).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: gutterFont]).width
        ruleThickness = ceil(width) + 12
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = codeTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        gutterBackgroundColor.setFill()
        bounds.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: numberColor,
        ]
        let currentAttributes: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: currentNumberColor,
        ]
        let inset = textView.textContainerInset
        let relativePoint = convert(NSPoint.zero, from: textView)
        let textLength = (textView.string as NSString).length

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        let maxChar = NSMaxRange(visibleCharRange)

        var lineIndex = lineStarts.lineIndex(forUTF16Offset: visibleCharRange.location)
        while lineIndex < lineStarts.offsets.count {
            let charStart = lineStarts.offsets[lineIndex]
            if charStart > maxChar { break }

            let fragmentRect: NSRect
            if charStart < textLength {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: charStart)
                fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            } else if layoutManager.extraLineFragmentTextContainer != nil {
                // Trailing empty line (final newline) or an empty document.
                fragmentRect = layoutManager.extraLineFragmentRect
            } else {
                break
            }

            let label = "\(lineIndex + 1)" as NSString
            let isCurrent = (lineIndex + 1) == currentLine
            let lineAttributes = isCurrent ? currentAttributes : attributes
            let size = label.size(withAttributes: lineAttributes)
            let drawX = ruleThickness - size.width - 6
            let drawY = relativePoint.y + fragmentRect.minY + inset.height + (fragmentRect.height - size.height) / 2
            label.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: lineAttributes)

            lineIndex += 1
        }
    }
}
