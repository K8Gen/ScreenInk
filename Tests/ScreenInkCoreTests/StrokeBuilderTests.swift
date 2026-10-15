import CoreGraphics
import Testing
@testable import ScreenInkCore

@Suite struct StrokeBuilderTests {
    @Test func emitsFirstSegmentOnFifthPoint() {
        var builder = StrokeBuilder()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 10)]
        for point in points {
            #expect(builder.add(point, width: 2) == nil)
        }
        let segment = builder.add(CGPoint(x: 40, y: 20), width: 3)
        // p3 becomes the midpoint of p2 and p4.
        #expect(segment == BezierSegment(
            start: CGPoint(x: 0, y: 0), control1: CGPoint(x: 10, y: 0), control2: CGPoint(x: 20, y: 10),
            end: CGPoint(x: 30, y: 15), width: 3))
    }

    @Test func consecutiveSegmentsShareJointAndTangent() {
        let points = (0..<20).map { i in CGPoint(x: Double(i) * 7, y: sin(Double(i) / 2) * 30) }
        let segments = StrokeBuilder.segments(points: points, widths: Array(repeating: 2, count: points.count))
        #expect(segments.count >= 3)
        for (a, b) in zip(segments, segments.dropFirst()) {
            #expect(a.end == b.start)
            // C1 continuity: incoming and outgoing control points are collinear with the joint.
            let incoming = CGVector(dx: a.end.x - a.control2.x, dy: a.end.y - a.control2.y)
            let outgoing = CGVector(dx: b.control1.x - b.start.x, dy: b.control1.y - b.start.y)
            let cross = incoming.dx * outgoing.dy - incoming.dy * outgoing.dx
            #expect(abs(cross) < 1e-9)
        }
    }

    @Test func coversWholeStrokeFromFirstToLastPoint() {
        for count in 2...12 {
            let points = (0..<count).map { CGPoint(x: Double($0) * 5, y: Double($0 % 3) * 4) }
            let segments = StrokeBuilder.segments(points: points, widths: [1])
            #expect(segments.first?.start == points.first, "count \(count)")
            #expect(segments.last?.end == points.last, "count \(count)")
            for (a, b) in zip(segments, segments.dropFirst()) {
                #expect(a.end == b.start, "count \(count)")
            }
        }
    }

    @Test func ignoresRepeatedSamples() {
        var builder = StrokeBuilder()
        _ = builder.add(CGPoint(x: 1, y: 1), width: 1)
        _ = builder.add(CGPoint(x: 1, y: 1), width: 1)
        #expect(builder.points.count == 1)
    }

    @Test func replayMatchesLiveSegments() {
        let points = (0..<17).map { CGPoint(x: Double($0) * 3, y: Double($0 * $0) / 10) }
        let widths = points.indices.map { CGFloat(1 + $0 % 4) }
        var builder = StrokeBuilder()
        var live: [BezierSegment] = []
        for (point, width) in zip(points, widths) {
            if let segment = builder.add(point, width: width) { live.append(segment) }
        }
        if let tail = builder.finish() { live.append(tail) }
        #expect(live == StrokeBuilder.segments(points: builder.points, widths: builder.widths))
    }
}

@Suite struct StrokeOutlineTests {
    @Test func singlePointIsADot() {
        let path = StrokeOutline.path(points: [CGPoint(x: 50, y: 50)], widths: [10])
        #expect(path.boundingBox == CGRect(x: 45, y: 45, width: 10, height: 10))
        #expect(path.contains(CGPoint(x: 50, y: 50)))
    }

    @Test func outlineCoversCenterlineWithoutHolesAtOverlaps() {
        // A tight zig-zag forces overlapping segment outlines.
        let points: [CGPoint] = (0..<30).map { (i: Int) -> CGPoint in
            let x = Double(i % 2) * 6 + Double(i)
            let y = Double(i % 3) * 5
            return CGPoint(x: x, y: y)
        }
        let widths = [CGFloat](repeating: 8, count: points.count)
        let path = StrokeOutline.path(points: points, widths: widths)
        for segment in StrokeBuilder.segments(points: points, widths: widths) {
            let startInside = path.contains(segment.start, using: CGPathFillRule.winding)
            let endInside = path.contains(segment.end, using: CGPathFillRule.winding)
            #expect(startInside)
            #expect(endInside)
        }
    }

    @Test func widthControlsThickness() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let thin = StrokeOutline.path(points: points, widths: [2, 2]).boundingBox
        let thick = StrokeOutline.path(points: points, widths: [20, 20]).boundingBox
        #expect(abs(thin.height - 2) < 0.01)
        #expect(abs(thick.height - 20) < 0.01)
    }
}

@Suite struct PressureFilterTests {
    @Test func firstSampleIsTakenAsIs() {
        var filter = PressureFilter()
        #expect(filter.filter(0.8) == 0.8)
    }

    @Test func smoothsTowardNewValues() {
        var filter = PressureFilter(alpha: 0.5)
        _ = filter.filter(0)
        #expect(filter.filter(1) == 0.5)
        #expect(filter.filter(1) == 0.75)
    }

    @Test func clampsAndMapsToWidth() {
        var filter = PressureFilter(minimumScale: 0.25)
        #expect(filter.filter(3) == 1)
        #expect(filter.width(base: 8, pressure: 0) == 2)
        #expect(filter.width(base: 8, pressure: 1) == 8)
    }
}
