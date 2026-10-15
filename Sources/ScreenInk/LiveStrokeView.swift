import AppKit
import os
import ScreenInkCore

/// Renders the stroke in progress from an offscreen bitmap cache (PLAN.md §2).
///
/// Each new segment is filled into the cache once, and only its bounding rect is
/// invalidated, so the per-sample cost doesn't grow with stroke length.
final class LiveStrokeView: NSView {
    private static let signposter = OSSignposter(subsystem: "ScreenInk", category: "LiveStroke")

    private var cache: CGContext?
    private var cacheScale: CGFloat = 0
    private var cacheSize: CGSize = .zero

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Input goes to the canvas underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func begin(style: Style) {
        clear()
        alphaValue = style.opacity
    }

    func append(_ path: CGPath, color: CGColor) {
        let state = Self.signposter.beginInterval("segment")
        defer { Self.signposter.endInterval("segment", state) }
        guard let context = cacheContext() else { return }
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath(using: .winding)
        setNeedsDisplay(path.boundingBoxOfPath.insetBy(dx: -2, dy: -2))
    }

    func clear() {
        if let cache {
            cache.clear(CGRect(origin: .zero, size: cacheSize))
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cache, let context = NSGraphicsContext.current?.cgContext else { return }
        // Creating the image is copy-on-write; it's released before the next segment is
        // drawn into the cache, so no copy actually happens.
        guard let image = cache.makeImage() else { return }
        context.saveGState()
        context.clip(to: dirtyRect)
        // The cache already holds upright, top-left content; undo this view's flip.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: bounds)
        context.restoreGState()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        cache = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cache = nil
    }

    private func cacheContext() -> CGContext? {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if let cache, cacheScale == scale, cacheSize == bounds.size { return cache }
        guard bounds.width > 0, bounds.height > 0,
            let context = CGContext(
                data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // Top-left origin in points, matching the canvas coordinate space.
        context.translateBy(x: 0, y: bounds.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.setShouldAntialias(true)
        cache = context
        cacheScale = scale
        cacheSize = bounds.size
        return context
    }
}
