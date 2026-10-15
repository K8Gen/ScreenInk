import CoreGraphics

/// One filled path of an annotation. Every annotation renders as filled paths only, so
/// on-screen layers, hit-testing and (later) PDF export share one geometry.
public struct RenderPart {
    public enum Fill: Equatable, Sendable {
        /// The annotation's style color.
        case style
        /// Black or white, whichever reads better on the style color (badge numbers).
        case contrast
    }

    public var path: CGPath
    public var fill: Fill
}

extension RGBA {
    /// White on dark colors, black on light ones.
    public var contrasting: RGBA {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? .black : .white
    }
}

extension Annotation {
    public var renderParts: [RenderPart] {
        let width = CGFloat(style.width)
        switch geometry {
        case let .stroke(points, widths):
            return [RenderPart(path: StrokeOutline.path(points: points, widths: widths), fill: .style)]

        case let .line(from, to):
            let centerline = CGMutablePath()
            centerline.move(to: from)
            centerline.addLine(to: to)
            return [RenderPart(path: stroked(centerline, width: width), fill: .style)]

        case let .arrow(from, to, control):
            let shape = ArrowShape(from: from, to: to, control: control, width: width)
            var parts = [RenderPart(path: shape.head, fill: .style)]
            if let shaft = shape.shaft {
                parts.insert(RenderPart(path: stroked(shaft, width: width), fill: .style), at: 0)
            }
            return parts

        case let .rectangle(rect, cornerRadius):
            let r = rect.standardized
            let radius = min(max(cornerRadius, 0), min(r.width, r.height) / 2)
            let outline = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return [RenderPart(path: stroked(outline, width: width), fill: .style)]

        case let .ellipse(rect):
            let outline = CGPath(ellipseIn: rect.standardized, transform: nil)
            return [RenderPart(path: stroked(outline, width: width), fill: .style)]

        case let .text(origin, string, fontSize):
            return [RenderPart(path: TextOutline.path(for: string, fontSize: fontSize, origin: origin), fill: .style)]

        case let .badge(center, number, format, radius):
            let circle = CGPath(
                ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
                transform: nil)
            let label = format.label(for: number)
            // Shrink long labels (e.g. roman numerals) to fit inside the circle.
            let fontSize = radius * (label.count <= 2 ? 1.1 : 2.2 / CGFloat(label.count))
            let glyphs = TextOutline.path(for: label, fontSize: fontSize, origin: .zero)
            let box = glyphs.boundingBoxOfPath
            var centering = CGAffineTransform(translationX: center.x - box.midX, y: center.y - box.midY)
            let centered = glyphs.copy(using: &centering) ?? glyphs
            return [RenderPart(path: circle, fill: .style), RenderPart(path: centered, fill: .contrast)]
        }
    }

    /// Union of all parts' bounds.
    public var bounds: CGRect {
        renderParts.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
    }

    /// True when `point` is on the annotation or within `tolerance` points of it.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat = 6) -> Bool {
        switch kind {
        case .text, .badge:
            // Glyph outlines have gaps; treat the whole box as the target.
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        default:
            return renderParts.contains { part in
                part.path.contains(point)
                    || part.path.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
                        .contains(point)
            }
        }
    }
}

private func stroked(_ path: CGPath, width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: max(width, 0.5), lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Shaft centerline plus a filled triangular head. The head size scales with the width.
struct ArrowShape {
    let shaft: CGPath?
    let head: CGPath

    init(from: CGPoint, to: CGPoint, control: CGPoint?, width: CGFloat) {
        let headLength = max(width * 4, 14)
        let headHalfWidth = headLength * 0.55
        // Direction the arrow arrives at its tip.
        let tail = control ?? from
        var direction = CGVector(dx: to.x - tail.x, dy: to.y - tail.y)
        let length = hypot(direction.dx, direction.dy)
        direction = length > 0 ? CGVector(dx: direction.dx / length, dy: direction.dy / length) : CGVector(dx: 1, dy: 0)
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)

        let base = CGPoint(x: to.x - direction.dx * headLength, y: to.y - direction.dy * headLength)
        let head = CGMutablePath()
        head.move(to: to)
        head.addLine(to: CGPoint(x: base.x + normal.dx * headHalfWidth, y: base.y + normal.dy * headHalfWidth))
        head.addLine(to: CGPoint(x: base.x - normal.dx * headHalfWidth, y: base.y - normal.dy * headHalfWidth))
        head.closeSubpath()
        self.head = head

        // End the shaft inside the head so the round cap doesn't poke out past its sides.
        let shaftEnd = CGPoint(x: to.x - direction.dx * headLength * 0.6, y: to.y - direction.dy * headLength * 0.6)
        let total = hypot(to.x - from.x, to.y - from.y)
        guard total > headLength else {
            shaft = nil
            return
        }
        let path = CGMutablePath()
        path.move(to: from)
        if let control {
            path.addQuadCurve(to: shaftEnd, control: control)
        } else {
            path.addLine(to: shaftEnd)
        }
        shaft = path
    }
}
