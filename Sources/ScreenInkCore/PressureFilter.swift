import CoreGraphics

/// Exponential moving average over pen pressure, mapped to a line width.
/// Pressure is smoothed separately from position (PLAN.md §2).
public struct PressureFilter: Sendable {
    public var alpha: Double
    /// Width multiplier at zero pressure, so light strokes never vanish.
    public var minimumScale: Double
    public private(set) var value: Double?

    public init(alpha: Double = 0.3, minimumScale: Double = 0.3) {
        self.alpha = alpha
        self.minimumScale = minimumScale
    }

    public mutating func reset() {
        value = nil
    }

    /// Feeds a raw 0…1 pressure sample and returns the smoothed value.
    public mutating func filter(_ pressure: Double) -> Double {
        let clamped = min(max(pressure, 0), 1)
        let next = value.map { $0 + alpha * (clamped - $0) } ?? clamped
        value = next
        return next
    }

    public func width(base: Double, pressure: Double) -> CGFloat {
        CGFloat(base * (minimumScale + (1 - minimumScale) * pressure))
    }
}
