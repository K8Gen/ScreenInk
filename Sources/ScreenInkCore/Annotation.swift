import CoreGraphics
import Foundation

public enum BadgeFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case decimal
    case alphabet
    case roman

    public func label(for number: Int) -> String {
        let n = max(number, 1)
        switch self {
        case .decimal:
            return String(n)
        case .alphabet:
            // 1 → A, 26 → Z, 27 → AA (bijective base 26).
            var value = n
            var result = ""
            while value > 0 {
                value -= 1
                result = String(UnicodeScalar(UInt8(65 + value % 26))) + result
                value /= 26
            }
            return result
        case .roman:
            let table: [(Int, String)] = [
                (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
            ]
            var value = min(n, 3999)
            var result = ""
            for (amount, symbol) in table {
                while value >= amount {
                    result += symbol
                    value -= amount
                }
            }
            return result
        }
    }
}

public enum AnnotationKind: String, Codable, Hashable, Sendable {
    case stroke, line, arrow, rectangle, ellipse, text, badge
}

/// Vector geometry of one annotation, in the owning screen's top-left point space.
public enum Geometry: Codable, Hashable, Sendable {
    /// Freehand pen or highlighter stroke: raw input points and the width at each.
    case stroke(points: [CGPoint], widths: [CGFloat])
    case line(from: CGPoint, to: CGPoint)
    /// `control` makes a curved arrow (quadratic Bézier through it).
    case arrow(from: CGPoint, to: CGPoint, control: CGPoint?)
    case rectangle(CGRect, cornerRadius: CGFloat)
    case ellipse(CGRect)
    /// `origin` is the top-left corner of the first line's box.
    case text(origin: CGPoint, string: String, fontSize: CGFloat)
    case badge(center: CGPoint, number: Int, format: BadgeFormat, radius: CGFloat)

    public var kind: AnnotationKind {
        switch self {
        case .stroke: .stroke
        case .line: .line
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .badge: .badge
        }
    }

    public func translated(by d: CGVector) -> Geometry {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.dx, y: p.y + d.dy) }
        switch self {
        case let .stroke(points, widths):
            return .stroke(points: points.map(move), widths: widths)
        case let .line(from, to):
            return .line(from: move(from), to: move(to))
        case let .arrow(from, to, control):
            return .arrow(from: move(from), to: move(to), control: control.map(move))
        case let .rectangle(rect, cornerRadius):
            return .rectangle(rect.offsetBy(dx: d.dx, dy: d.dy), cornerRadius: cornerRadius)
        case let .ellipse(rect):
            return .ellipse(rect.offsetBy(dx: d.dx, dy: d.dy))
        case let .text(origin, string, fontSize):
            return .text(origin: move(origin), string: string, fontSize: fontSize)
        case let .badge(center, number, format, radius):
            return .badge(center: move(center), number: number, format: format, radius: radius)
        }
    }
}

public struct Annotation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var geometry: Geometry
    public var style: Style
    public var createdAt: Date

    public init(id: UUID = UUID(), geometry: Geometry, style: Style, createdAt: Date = Date()) {
        self.id = id
        self.geometry = geometry
        self.style = style
        self.createdAt = createdAt
    }

    public var kind: AnnotationKind { geometry.kind }
}
