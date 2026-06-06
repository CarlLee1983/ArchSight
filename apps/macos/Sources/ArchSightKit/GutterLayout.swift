import CoreGraphics

/// Pure geometry for the line-number gutter.
///
/// The gutter must place each number so its text baseline sits on the *same*
/// baseline as the code glyph on that line. Vertically centering the number
/// within the line-fragment rect looks right only when the line height equals
/// the natural font height; with `lineHeightMultiple > 1` the glyph baseline is
/// no longer at the fragment's center, so centering drifts the numbers off the
/// code by a constant few points. Baseline alignment is correct for any line
/// height and matches VSCode.
public enum GutterLayout {
    /// Flipped-coordinate Y (top-left) at which to draw a line-number string so
    /// its baseline aligns with the code glyph baseline on the same line.
    ///
    /// - Parameters:
    ///   - relativeOriginY: the text view origin converted into ruler coordinates.
    ///   - fragmentMinY: the line fragment's `minY` in text-container coordinates.
    ///   - insetHeight: the text view's `textContainerInset.height`.
    ///   - glyphBaselineY: the glyph baseline relative to the line fragment
    ///     origin — i.e. `NSLayoutManager.location(forGlyphAt:).y`.
    ///   - gutterAscender: the line-number font's ascender (distance from the
    ///     drawn top of the string down to its baseline).
    public static func numberDrawY(
        relativeOriginY: CGFloat,
        fragmentMinY: CGFloat,
        insetHeight: CGFloat,
        glyphBaselineY: CGFloat,
        gutterAscender: CGFloat
    ) -> CGFloat {
        relativeOriginY + fragmentMinY + insetHeight + glyphBaselineY - gutterAscender
    }
}
