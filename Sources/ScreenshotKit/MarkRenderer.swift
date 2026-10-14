import AppKit

/// Draws a `Mark` into a `CGContext`.
///
/// The overlay and `composeFinalImage` both draw with this code, so the saved image is the same
/// as the overlay. The context must have the top-left of the box at 0, 0, with y going down and
/// one unit for one point.
public enum MarkRenderer {
    /// Highlight covers what is below it with this part of its colour.
    public static let highlightAlpha: CGFloat = 0.4

    public static func color(_ color: MarkColor, alpha: CGFloat = 1) -> CGColor {
        let parts = color.components
        return CGColor(srgbRed: parts.red, green: parts.green, blue: parts.blue, alpha: alpha)
    }

    public static func draw(_ marks: [Mark], in context: CGContext) {
        for mark in marks {
            draw(mark, in: context)
        }
    }

    public static func draw(_ mark: Mark, in context: CGContext) {
        guard let first = mark.points.first else { return }
        let color = MarkRenderer.color(mark.style.color)

        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(mark.lineWidth)

        switch mark.tool {
        case .rectangle:
            context.setLineJoin(.miter)
            context.stroke(mark.frame)
        case .ellipse:
            context.strokeEllipse(in: mark.frame)
        case .arrow:
            drawArrow(mark, from: first, in: context)
        case .pen:
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(smoothPath(through: mark.points))
            context.strokePath()
        case .highlight:
            // Multiply, as a real highlighter: a dark pixel below stays dark, so text stays readable.
            context.setBlendMode(.multiply)
            context.setAlpha(highlightAlpha)
            context.setLineCap(.butt)
            context.setLineJoin(.round)
            context.addPath(smoothPath(through: mark.points))
            context.strokePath()
        case .text:
            drawText(mark, at: first, in: context)
        case .number:
            drawNumber(mark, at: first, in: context)
        }
    }

    // MARK: Shapes

    /// A line with a filled head at the end of the drag. The model gives the corners of the head
    /// (`Mark.arrowHead`), so the hit test of the mark uses the same numbers.
    private static func drawArrow(_ mark: Mark, from start: CGPoint, in context: CGContext) {
        guard let head = mark.arrowHead else { return }
        if let shaftEnd = head.shaftEnd {
            // The line stops at the base of the head, so the tip stays sharp.
            context.setLineCap(.round)
            context.move(to: start)
            context.addLine(to: shaftEnd)
            context.strokePath()
        }
        context.move(to: head.tip)
        context.addLine(to: head.left)
        context.addLine(to: head.right)
        context.closePath()
        context.fillPath()
    }

    /// A smooth line through the points of the pointer: each point is the control point of a
    /// curve between the middles of its two segments.
    private static func smoothPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        if points.count > 2 {
            for index in 1..<(points.count - 1) {
                let next = points[index + 1]
                let middle = CGPoint(x: (points[index].x + next.x) / 2, y: (points[index].y + next.y) / 2)
                path.addQuadCurve(to: middle, control: points[index])
            }
        }
        path.addLine(to: last)
        return path
    }

    // MARK: Number

    /// The colour of the digits of a Number mark: white on a dark circle, black on a light
    /// circle, so the number is easy to read on each of the six colours.
    static func digitColor(on color: MarkColor) -> CGColor {
        switch color {
        case .red, .blue, .black: return CGColor(gray: 1, alpha: 1)
        case .amber, .green, .white: return CGColor(gray: 0, alpha: 1)
        }
    }

    /// A filled circle with the number in its middle. The digits are their outlines, as a path
    /// that the context fills. Thus they are sharp at each pixel scale. This is the code of the
    /// Stamp of Screendraw (`makeNumberLayer`), for a context and not a layer.
    private static func drawNumber(_ mark: Mark, at middle: CGPoint, in context: CGContext) {
        let diameter = mark.style.numberDiameter
        // The fill colour is the colour of the mark.
        context.fillEllipse(in: CGRect(
            x: middle.x - diameter / 2, y: middle.y - diameter / 2, width: diameter, height: diameter
        ))

        let font = NSFont.systemFont(ofSize: diameter * 0.6, weight: .bold) as CTFont
        let text = NSAttributedString(string: String(mark.number), attributes: [.font: font])
        let digits = CGMutablePath()
        for run in CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var places = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &places)
            for (glyph, place) in zip(glyphs, places) {
                guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                digits.addPath(outline, transform: CGAffineTransform(translationX: place.x, y: place.y))
            }
        }
        // A number with many digits gets smaller, so it stays in 70% of the circle.
        let box = digits.boundingBoxOfPath
        guard !box.isEmpty else { return }
        let scale = min(1, diameter * 0.7 / box.width)
        // The digits have y going up, and the context of the marks has y going down.
        var toMiddle = CGAffineTransform(translationX: middle.x, y: middle.y)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        context.setFillColor(digitColor(on: mark.style.color))
        guard let placed = digits.copy(using: &toMiddle) else { return }
        context.addPath(placed)
        context.fillPath()
    }

    // MARK: Text

    static func textAttributes(_ style: MarkStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .medium),
            .foregroundColor: NSColor(cgColor: color(style.color)) ?? .red,
        ]
    }

    private static func drawText(_ mark: Mark, at origin: CGPoint, in context: CGContext) {
        let layout = TextLayout(text: mark.text, style: mark.style, wrapWidth: mark.wrapWidth)
        let previous = NSGraphicsContext.current
        // The context has y going down. AppKit must know that, or the letters are upside down.
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        layout.manager.drawGlyphs(forGlyphRange: layout.manager.glyphRange(for: layout.container), at: origin)
        NSGraphicsContext.current = previous
    }
}

/// The text system of one Text mark: the text, and the width where a line breaks.
///
/// The text field of the overlay and `MarkRenderer` both use this layout. Thus the lines of the
/// saved image break at the same places as the lines that the user typed.
struct TextLayout {
    // The storage owns the manager, and the manager owns the container.
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container: NSTextContainer

    init(text: String, style: MarkStyle, wrapWidth: CGFloat) {
        storage = NSTextStorage(string: text, attributes: MarkRenderer.textAttributes(style))
        container = NSTextContainer(size: CGSize(width: max(wrapWidth, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
    }

    /// The area that the lines of the text use, from the top-left of the text.
    var usedRect: CGRect {
        _ = manager.glyphRange(for: container)
        return manager.usedRect(for: container)
    }
}
