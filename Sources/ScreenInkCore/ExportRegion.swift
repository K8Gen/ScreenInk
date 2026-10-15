import CoreGraphics

/// Geometry for Copy Region…: the dragged rectangle in points and its crop in pixels.
/// Both use the screen-local top-left origin, like the canvas and `CGImage.cropping(to:)`.
public enum ExportRegion {
    /// A drag shorter than this on either side counts as a click, which cancels the pick.
    public static let minimumSide: CGFloat = 4

    /// The rectangle between the drag's start and end, clipped to the screen.
    /// Nil when the result is too small to be a deliberate drag.
    public static func rect(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect? {
        let dragged = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y))
        let clipped = dragged.intersection(bounds)
        guard !clipped.isNull, clipped.width >= minimumSide, clipped.height >= minimumSide else { return nil }
        return clipped
    }

    /// `rect` (points) in pixels of an image at `scale`, rounded outward to whole pixels
    /// and kept inside the image. Nil when nothing of it is inside.
    public static func pixelRect(for rect: CGRect, scale: CGFloat, imageSize: CGSize) -> CGRect? {
        let scaled = CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let clipped = scaled.integral.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped
    }
}
