import CoreGraphics

/// One cubic Bézier piece of a stroke, drawn with a single width.
public struct BezierSegment: Equatable, Sendable {
    public var start: CGPoint
    public var control1: CGPoint
    public var control2: CGPoint
    public var end: CGPoint
    public var width: CGFloat

    public init(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, width: CGFloat) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
        self.width = width
    }
}

/// Turns raw pointer samples into smooth cubic segments using the 5-point midpoint scheme
/// (PLAN.md §2): once five points are buffered, the fourth is moved to the midpoint of the
/// third and fifth, the curve p0→p3 (controls p1, p2) is emitted, and the buffer restarts
/// from [p3, p4]. Consecutive segments therefore share a tangent at their joint, so the
/// stroke has no corners.
public struct StrokeBuilder: Sendable {
    /// Every accepted input sample, kept so the stroke can be stored and replayed.
    public private(set) var points: [CGPoint] = []
    public private(set) var widths: [CGFloat] = []

    private var buffer: [CGPoint] = []

    public init() {}

    /// Adds a sample. Returns a segment when one is complete.
    public mutating func add(_ point: CGPoint, width: CGFloat) -> BezierSegment? {
        if point == points.last { return nil }
        points.append(point)
        widths.append(width)
        buffer.append(point)
        guard buffer.count == 5 else { return nil }

        buffer[3] = midpoint(buffer[2], buffer[4])
        let segment = BezierSegment(
            start: buffer[0], control1: buffer[1], control2: buffer[2], end: buffer[3], width: width)
        buffer = [buffer[3], buffer[4]]
        return segment
    }

    /// Flushes the 1–3 points still buffered after the last full segment.
    public mutating func finish() -> BezierSegment? {
        defer { buffer = [] }
        let width = widths.last ?? 1
        switch buffer.count {
        case 2:
            let (a, b) = (buffer[0], buffer[1])
            return BezierSegment(
                start: a, control1: lerp(a, b, 1.0 / 3), control2: lerp(a, b, 2.0 / 3), end: b, width: width)
        case 3:
            // Quadratic p0-p1-p2 raised to a cubic.
            let (a, q, b) = (buffer[0], buffer[1], buffer[2])
            return BezierSegment(
                start: a, control1: lerp(a, q, 2.0 / 3), control2: lerp(b, q, 2.0 / 3), end: b, width: width)
        case 4:
            return BezierSegment(
                start: buffer[0], control1: buffer[1], control2: buffer[2], end: buffer[3], width: width)
        default:
            return nil
        }
    }

    /// Replays stored samples into the exact segments produced while drawing.
    public static func segments(points: [CGPoint], widths: [CGFloat]) -> [BezierSegment] {
        var builder = StrokeBuilder()
        var result: [BezierSegment] = []
        for (index, point) in points.enumerated() {
            let width = index < widths.count ? widths[index] : (widths.last ?? 1)
            if let segment = builder.add(point, width: width) { result.append(segment) }
        }
        if let tail = builder.finish() { result.append(tail) }
        return result
    }
}

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
