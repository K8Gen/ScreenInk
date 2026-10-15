import AppKit
import ScreenInkCore

/// Transient visuals above the annotations: shape previews, selection boxes, the marquee,
/// the eraser ring and the copy flash. Layer-hosting, top-left geometry.
final class OverlayLayerView: NSView {
    private let root = CALayer()
    private let previewContainer = CALayer()
    private let selectionLayer = CAShapeLayer()
    private let marqueeLayer = CAShapeLayer()
    private let eraserLayer = CAShapeLayer()
    private let flashLayer = CAShapeLayer()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
        for dashed in [selectionLayer, marqueeLayer] {
            dashed.fillColor = nil
            dashed.lineWidth = 1
            dashed.lineDashPattern = [5, 4]
            dashed.strokeColor = NSColor.controlAccentColor.cgColor
        }
        marqueeLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        eraserLayer.fillColor = NSColor.white.withAlphaComponent(0.25).cgColor
        eraserLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        eraserLayer.lineWidth = 1
        flashLayer.fillColor = NSColor.white.cgColor
        flashLayer.opacity = 0
        for sublayer in [previewContainer, selectionLayer, marqueeLayer, eraserLayer, flashLayer] {
            root.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        withoutAnimation {
            for sublayer in [previewContainer, selectionLayer, marqueeLayer, eraserLayer, flashLayer] {
                sublayer.frame = bounds
                sublayer.contentsScale = scale
            }
        }
    }

    func showPreview(_ annotation: Annotation?) {
        withoutAnimation {
            previewContainer.sublayers = annotation.map {
                [AnnotationLayerFactory.makeLayer(for: $0, bounds: bounds, scale: scale)]
            }
        }
    }

    /// Dashed boxes around the given rects (already offset for any drag in progress).
    func showSelection(_ rects: [CGRect]) {
        withoutAnimation {
            let path = CGMutablePath()
            for rect in rects { path.addRect(rect.insetBy(dx: -4, dy: -4)) }
            selectionLayer.path = rects.isEmpty ? nil : path
        }
    }

    func showMarquee(_ rect: CGRect?) {
        withoutAnimation { marqueeLayer.path = rect.map { CGPath(rect: $0, transform: nil) } }
    }

    func showEraser(at point: CGPoint?, radius: CGFloat) {
        withoutAnimation {
            eraserLayer.path = point.map {
                CGPath(
                    ellipseIn: CGRect(x: $0.x - radius, y: $0.y - radius, width: radius * 2, height: radius * 2),
                    transform: nil)
            }
        }
    }

    /// A short white flash over `rect`: the copy went to the clipboard.
    func flash(_ rect: CGRect) {
        withoutAnimation { flashLayer.path = CGPath(rect: rect, transform: nil) }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.6
        fade.toValue = 0
        fade.duration = Self.flashDuration
        flashLayer.add(fade, forKey: "flash")
    }

    static let flashDuration: CFTimeInterval = 0.25
}
