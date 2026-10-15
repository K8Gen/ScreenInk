import CoreGraphics
import CoreText
import Foundation

/// Lays out plain text with the system font and returns the glyph outlines as a path
/// in top-left (y-down) coordinates.
public enum TextOutline {
    public static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    /// Distance between baselines, matching what a plain NSTextView uses for the same font.
    public static func lineHeight(fontSize: CGFloat) -> CGFloat {
        let font = font(size: fontSize)
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    public static func path(for string: String, fontSize: CGFloat, origin: CGPoint) -> CGPath {
        let font = font(size: fontSize)
        let ascent = CTFontGetAscent(font)
        let lineHeight = lineHeight(fontSize: fontSize)
        let result = CGMutablePath()

        for (index, line) in string.components(separatedBy: "\n").enumerated() where !line.isEmpty {
            let attributed = NSAttributedString(string: line, attributes: [.init(kCTFontAttributeName as String): font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let baseline = origin.y + ascent + CGFloat(index) * lineHeight
            let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                // Font fallback (e.g. for symbols) may switch fonts per run.
                let runFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for (glyph, position) in zip(glyphs, positions) {
                    // Glyph outlines are y-up; flip them onto the y-down baseline.
                    var transform = CGAffineTransform(translationX: origin.x + position.x, y: baseline)
                        .scaledBy(x: 1, y: -1)
                    if let outline = CTFontCreatePathForGlyph(runFont, glyph, &transform) {
                        result.addPath(outline)
                    }
                }
            }
        }
        return result
    }
}
