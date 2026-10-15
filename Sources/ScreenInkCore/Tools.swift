import CoreGraphics

public enum ToolKind: String, Codable, Hashable, Sendable, CaseIterable {
    case pen, highlighter, line, arrow, rectangle, ellipse, text, badge, eraser, select

    public var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .badge: "Numbered Badge"
        case .eraser: "Eraser"
        case .select: "Select"
        }
    }
}

/// Builds shape geometry from a drag (PLAN.md §5: Shift constrains lines and arrows
/// to 45° steps and rectangles/ellipses to squares/circles).
public enum ShapeFactory {
    /// Returns nil when the drag is too short to mean a shape.
    public static func geometry(
        for tool: ToolKind, from start: CGPoint, to rawEnd: CGPoint, constrain: Bool, curved: Bool = false,
        cornerRadius: CGFloat = 0
    ) -> Geometry? {
        switch tool {
        case .line, .arrow:
            let end = constrain ? snapAngle(from: start, to: rawEnd) : rawEnd
            guard hypot(end.x - start.x, end.y - start.y) >= 3 else { return nil }
            if tool == .line { return .line(from: start, to: end) }
            return .arrow(from: start, to: end, control: curved ? curveControl(from: start, to: end) : nil)
        case .rectangle, .ellipse:
            let rect = constrain ? squareRect(from: start, to: rawEnd) : rectFrom(start, rawEnd)
            guard rect.width >= 3 || rect.height >= 3 else { return nil }
            return tool == .rectangle ? .rectangle(rect, cornerRadius: cornerRadius) : .ellipse(rect)
        default:
            return nil
        }
    }

    /// Rotates `end` around `start` to the nearest multiple of 45°, keeping the length.
    public static func snapAngle(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let step = Double.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        var dxSnapped = length * cos(angle)
        var dySnapped = length * sin(angle)
        // cos/sin leave tiny residues at 90° multiples; make horizontal/vertical exact.
        if abs(dxSnapped) < 1e-9 { dxSnapped = 0 }
        if abs(dySnapped) < 1e-9 { dySnapped = 0 }
        return CGPoint(x: start.x + dxSnapped, y: start.y + dySnapped)
    }

    static func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Square anchored at `start`, growing toward the drag direction.
    static func squareRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let side = max(abs(end.x - start.x), abs(end.y - start.y))
        let corner = CGPoint(
            x: start.x + (end.x >= start.x ? side : -side), y: start.y + (end.y >= start.y ? side : -side))
        return rectFrom(start, corner)
    }

    /// A gentle bend: the control point sits off the midpoint by a quarter of the length.
    static func curveControl(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        return CGPoint(x: mid.x + (end.y - start.y) * 0.25, y: mid.y - (end.x - start.x) * 0.25)
    }
}
