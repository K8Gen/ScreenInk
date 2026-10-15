import AppKit

/// A transparent, borderless panel covering one screen, above full-screen apps and on every Space.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        setFrame(screen.frame, display: false)
    }

    // Borderless panels refuse key status by default; the canvas needs keyboard shortcuts.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
