import AppKit

/// A black veil under the annotations that darkens the screen while drawing. Layer-hosting,
/// never takes clicks.
final class DimView: NSView {
    private let root = CALayer()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        root.backgroundColor = NSColor.black.cgColor
        root.opacity = 0
        layer = root
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `level` is the fraction of black, 0 to hide.
    func setLevel(_ level: Double, animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setDisableActions(!animated)
        root.opacity = Float(level)
        CATransaction.commit()
    }
}
