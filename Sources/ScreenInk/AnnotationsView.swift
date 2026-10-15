import AppKit
import ScreenInkCore

/// Shows committed annotations, one layer tree each (PLAN.md §2).
///
/// This is a layer-hosting view: it owns its root layer outright, so the top-left
/// geometry set here isn't changed by AppKit.
final class AnnotationsView: NSView {
    private let root = CALayer()
    private var layersByID: [UUID: CALayer] = [:]
    private var rendered: [UUID: Annotation] = [:]
    private var renderedScale: CGFloat = 0

    /// Hidden while being erased or edited.
    var hiddenIDs: Set<UUID> = [] {
        didSet { applyPresentation() }
    }
    /// Temporary offset while the select tool drags annotations.
    var dragOffset: (ids: Set<UUID>, offset: CGVector)? {
        didSet { applyPresentation() }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Brings the layer tree in line with the document: adds, rebuilds changed, removes, reorders.
    func sync(with annotations: [Annotation], scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let rebuildAll = scale != renderedScale
        renderedScale = scale
        var nextLayers: [UUID: CALayer] = [:]
        var nextRendered: [UUID: Annotation] = [:]
        var ordered: [CALayer] = []
        for annotation in annotations {
            var layer = layersByID[annotation.id]
            if layer == nil || rebuildAll || rendered[annotation.id] != annotation {
                layer = AnnotationLayerFactory.makeLayer(for: annotation, bounds: bounds, scale: scale)
            }
            nextLayers[annotation.id] = layer
            nextRendered[annotation.id] = annotation
            ordered.append(layer!)
        }
        layersByID = nextLayers
        rendered = nextRendered
        root.sublayers = ordered
        applyPresentation()
    }

    /// Fades one annotation out, then calls `completion`.
    func fadeOut(id: UUID, duration: CFTimeInterval, completion: @escaping () -> Void) {
        guard let layer = layersByID[id] else {
            completion()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.opacity
        fade.toValue = 0
        fade.duration = duration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "fadeOut")
        CATransaction.commit()
    }

    /// Fades every annotation out together, then calls `completion`.
    func fadeOutAll(duration: CFTimeInterval, completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [root] in
            completion()
            root.removeAnimation(forKey: "fadeOut")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        root.add(fade, forKey: "fadeOut")
        CATransaction.commit()
    }

    private func applyPresentation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, layer) in layersByID {
            layer.isHidden = hiddenIDs.contains(id)
            if let dragOffset, dragOffset.ids.contains(id) {
                layer.setAffineTransform(CGAffineTransform(translationX: dragOffset.offset.dx, y: dragOffset.offset.dy))
            } else {
                layer.setAffineTransform(.identity)
            }
        }
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layersByID.values {
            layer.frame = bounds
            layer.sublayers?.forEach { $0.frame = bounds }
        }
        CATransaction.commit()
    }
}
