import AppKit
import XCTest
@testable import ArchSightKit

final class GutterLayoutTests: XCTestCase {
    func testNumberDrawYPlacesBaselineAtTextBaseline() {
        // The drawn number's baseline (drawY + ascender) must equal the text
        // baseline (relativeOrigin + fragmentMinY + inset + glyphBaselineY).
        let drawY = GutterLayout.numberDrawY(
            relativeOriginY: 10,
            fragmentMinY: 18,
            insetHeight: 8,
            glyphBaselineY: 15,
            gutterAscender: 9.86
        )
        let numberBaseline = drawY + 9.86
        XCTAssertEqual(numberBaseline, 10 + 18 + 8 + 15, accuracy: 0.0001)
    }

    /// Regression: with the default lineHeightMultiple (1.2) the line numbers
    /// must sit on the code baseline. The previous fragment-centering approach
    /// drifted them off by a constant amount — assert baseline alignment holds
    /// and that centering would NOT, using a real TextKit layout.
    func testBaselineAlignmentBeatsCenteringUnderLineHeightMultiple() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 1000, height: 1_000_000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.2
        storage.setAttributedString(NSAttributedString(
            string: "alpha\nbeta\ngamma\n",
            attributes: [.font: font, .paragraphStyle: para]
        ))
        layout.ensureLayout(for: container)

        let gutterFont = NSFont.monospacedSystemFont(ofSize: 12 * 0.85, weight: .regular)

        for (charStart, lineNo) in [(0, 1), (6, 2), (11, 3)] {
            let glyphIndex = layout.glyphIndexForCharacter(at: charStart)
            let frag = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let loc = layout.location(forGlyphAt: glyphIndex)
            let textBaseline = frag.minY + loc.y

            let drawY = GutterLayout.numberDrawY(
                relativeOriginY: 0,
                fragmentMinY: frag.minY,
                insetHeight: 0,
                glyphBaselineY: loc.y,
                gutterAscender: gutterFont.ascender
            )
            let numberBaseline = drawY + gutterFont.ascender
            XCTAssertEqual(numberBaseline, textBaseline, accuracy: 0.01, "line \(lineNo) baseline must match text")

            // The old centering formula misaligns under lineHeightMultiple.
            let numberSize = ("\(lineNo)" as NSString).size(withAttributes: [.font: gutterFont])
            let centeredTop = frag.minY + (frag.height - numberSize.height) / 2
            let centeredBaseline = centeredTop + gutterFont.ascender
            XCTAssertGreaterThan(abs(centeredBaseline - textBaseline), 1.0,
                                 "centering should be visibly off (it was the bug) on line \(lineNo)")
        }
    }
}
