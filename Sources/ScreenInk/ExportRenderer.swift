import AppKit
import ScreenInkCore

/// Flattens a screen capture and the screen's annotations into one image for Copy Screen
/// and Copy Region…. The annotations are rebuilt from the model, so the dimming veil,
/// the selection boxes and the palette never appear in an export.
@MainActor
enum ExportRenderer {
    /// `background` covers the whole screen of `pointSize`; its width sets the scale.
    /// `rect` (points, top-left origin) crops the result; nil keeps the whole screen.
    static func render(background: CGImage, annotations: [Annotation], pointSize: CGSize, rect: CGRect?) -> CGImage? {
        let width = background.width
        let height = background.height
        let scale = CGFloat(width) / pointSize.width
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))

        let bounds = CGRect(origin: .zero, size: pointSize)
        let root = CALayer()
        root.isGeometryFlipped = true
        root.frame = bounds
        root.sublayers = annotations.map { AnnotationLayerFactory.makeLayer(for: $0, bounds: bounds, scale: scale) }
        // Same transform as CanvasView.snapshot(): CALayer.render draws flipped, so flip to bitmap space.
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: pointSize.height)
        context.scaleBy(x: 1, y: -1)
        root.render(in: context)
        context.restoreGState()

        guard let image = context.makeImage() else { return nil }
        guard let rect else { return image }
        guard let crop = ExportRegion.pixelRect(for: rect, scale: scale, imageSize: CGSize(width: width, height: height))
        else { return nil }
        return image.cropping(to: crop)
    }
}
