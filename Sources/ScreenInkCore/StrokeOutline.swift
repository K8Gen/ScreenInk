import CoreGraphics

/// Converts stroke segments into filled outlines.
///
/// Each segment is stroked with its own width and round caps, and the outlines are
/// appended into one path. All stroked outlines share the same winding direction, so a
/// non-zero fill renders the overlaps solid. This gives variable-width strokes without
/// a boolean union (PLAN.md §10 fallback).
public enum StrokeOutline {
    public static func outline(of segment: BezierSegment) -> CGPath {
        let centerline = CGMutablePath()
        centerline.move(to: segment.start)
        centerline.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        return centerline.copy(
            strokingWithWidth: max(segment.width, 0.5), lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    public static func dot(at point: CGPoint, width: CGFloat) -> CGPath {
        let radius = max(width, 0.5) / 2
        return CGPath(
            ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2),
            transform: nil)
    }

    public static func path(points: [CGPoint], widths: [CGFloat]) -> CGPath {
        guard points.count > 1 else {
            guard let point = points.first else { return CGMutablePath() }
            return dot(at: point, width: widths.first ?? 1)
        }
        let path = CGMutablePath()
        for segment in StrokeBuilder.segments(points: points, widths: widths) {
            path.addPath(outline(of: segment))
        }
        return path
    }
}
