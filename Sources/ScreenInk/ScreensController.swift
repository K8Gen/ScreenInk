import AppKit
import ScreenInkCore

/// Owns one overlay panel per display, the document for each display, and the palette.
///
/// Documents are keyed by display ID and outlive their panels, so unplugging and
/// replugging a monitor (or any screen reconfiguration) keeps its drawing.
@MainActor
final class ScreensController {
    private struct Overlay {
        let panel: OverlayPanel
        let canvas: CanvasView
    }

    let toolState: ToolState
    private(set) var isActive = false {
        didSet { onActiveChange?(isActive) }
    }
    var onActiveChange: ((Bool) -> Void)?

    private var overlays: [CGDirectDisplayID: Overlay] = [:]
    private var documents: [CGDirectDisplayID: Document] = [:]
    private let palette: ToolPalette
    private var screenObserver: NSObjectProtocol?
    /// Set while Copy Region… waits for a drag: whether drawing was on before the pick began.
    private var regionPickWasActive: Bool?

    init(toolState: ToolState) {
        self.toolState = toolState
        palette = ToolPalette(toolState: toolState)
        palette.onUndo = { [weak self] in self?.activeCanvas?.document.undo() }
        palette.onRedo = { [weak self] in self?.activeCanvas?.document.redo() }
        palette.onClear = { [weak self] in self?.clearAll() }
        palette.onClose = { [weak self] in self?.deactivate() }
        rebuildOverlays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        }
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    /// Shows the overlays and makes the one under the pointer key, without activating the
    /// app, so the presenter's app keeps its menu bar and focus state.
    func activate() {
        for overlay in overlays.values {
            overlay.panel.ignoresMouseEvents = false
            overlay.panel.orderFrontRegardless()
        }
        if let overlay = overlayUnderPointer() {
            overlay.panel.makeKey()
            overlay.panel.makeFirstResponder(overlay.canvas)
            if let screen = overlay.panel.screen { palette.show(on: screen) }
        }
        isActive = true
    }

    func deactivate() {
        if regionPickWasActive != nil {
            regionPickWasActive = nil
            for overlay in overlays.values { overlay.canvas.endRegionPick() }
        }
        for overlay in overlays.values {
            overlay.canvas.cancelInteraction()
            overlay.panel.ignoresMouseEvents = true
            overlay.panel.orderOut(nil)
        }
        palette.hide()
        isActive = false
    }

    func clearAll() {
        for overlay in overlays.values {
            if isActive {
                overlay.canvas.clearWithFade()
            } else {
                overlay.canvas.document.removeAll()
            }
        }
    }

    var hasAnnotations: Bool {
        documents.values.contains { !$0.annotations.isEmpty }
    }

    /// The canvas receiving keyboard input, or the one under the pointer.
    private var activeCanvas: CanvasView? {
        activeDisplayID.flatMap { overlays[$0]?.canvas }
    }

    /// The display receiving keyboard input, or the one under the pointer (same rule as undo).
    private var activeDisplayID: CGDirectDisplayID? {
        let pointer = NSEvent.mouseLocation
        return overlays.first { $0.value.panel.isKeyWindow }?.key
            ?? overlays.first { $0.value.panel.frame.contains(pointer) }?.key
            ?? overlays.keys.first
    }

    // MARK: Copy to the clipboard

    /// Copy Screen: the active screen with its drawings, as PNG.
    func copyScreen() {
        guard regionPickWasActive == nil, let displayID = activeDisplayID else { return }
        guard ScreenCapturer.hasPermission else { return askForCapturePermission() }
        copy(displayID: displayID, rect: nil) { [weak self] copied in
            guard let self, copied, self.isActive, let canvas = self.overlays[displayID]?.canvas else { return }
            canvas.overlayView.flash(canvas.bounds)
        }
    }

    /// Copy Region…: shows the overlays (if hidden) and waits for a drag on any screen.
    func copyRegion() {
        guard regionPickWasActive == nil else { return }
        guard ScreenCapturer.hasPermission else { return askForCapturePermission() }
        regionPickWasActive = isActive
        if !isActive { activate() }
        palette.hide()
        for (displayID, overlay) in overlays { beginRegionPick(on: overlay.canvas, displayID: displayID) }
    }

    private func beginRegionPick(on canvas: CanvasView, displayID: CGDirectDisplayID) {
        canvas.beginRegionPick { [weak self] rect in self?.finishRegionPick(rect, on: displayID) }
    }

    private func finishRegionPick(_ rect: CGRect?, on displayID: CGDirectDisplayID) {
        guard let wasActive = regionPickWasActive else { return }
        regionPickWasActive = nil
        for overlay in overlays.values { overlay.canvas.endRegionPick() }
        guard let rect else { return restoreAfterRegionPick(wasActive: wasActive) }
        copy(displayID: displayID, rect: rect) { [weak self] copied in
            guard let self else { return }
            guard copied, let canvas = self.overlays[displayID]?.canvas else {
                return self.restoreAfterRegionPick(wasActive: wasActive)
            }
            canvas.overlayView.flash(rect)
            // Let the flash finish before the overlay hides again.
            DispatchQueue.main.asyncAfter(deadline: .now() + OverlayLayerView.flashDuration) { [weak self] in
                self?.restoreAfterRegionPick(wasActive: wasActive)
            }
        }
    }

    private func restoreAfterRegionPick(wasActive: Bool) {
        if !wasActive {
            deactivate()
        } else if isActive, let screen = overlayUnderPointer()?.panel.screen {
            palette.show(on: screen)
        }
    }

    /// Captures the display, draws its document on top, crops, and writes the PNG.
    /// `done` gets false when the copy failed (the overlay is then hidden and an alert shown).
    private func copy(displayID: CGDirectDisplayID, rect: CGRect?, done: @escaping (_ copied: Bool) -> Void) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return done(false) }
        let annotations = documents[displayID]?.annotations ?? []
        Task {
            do {
                try await ScreenExporter.copy(screen: screen, annotations: annotations, rect: rect)
                done(true)
            } catch {
                deactivate()
                ScreenExporter.showFailure(error)
                done(false)
            }
        }
    }

    /// Alerts sit below the overlay, so hide it first.
    private func askForCapturePermission() {
        deactivate()
        ScreenExporter.askForPermission()
    }

    private func overlayUnderPointer() -> Overlay? {
        let pointer = NSEvent.mouseLocation
        return overlays.values.first { $0.panel.frame.contains(pointer) } ?? overlays.values.first
    }

    private func rebuildOverlays() {
        var current: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID { current[id] = screen }
        }

        for (id, overlay) in overlays where current[id] == nil {
            overlay.canvas.cancelInteraction()
            overlay.panel.orderOut(nil)
            overlay.panel.close()
            overlays[id] = nil
        }

        for (id, screen) in current {
            if let overlay = overlays[id] {
                overlay.panel.setFrame(screen.frame, display: true)
                continue
            }
            let document = documents[id] ?? Document()
            documents[id] = document
            let panel = OverlayPanel(screen: screen)
            let canvas = CanvasView(
                frame: NSRect(origin: .zero, size: screen.frame.size), document: document, toolState: toolState)
            canvas.autoresizingMask = [.width, .height]
            canvas.onDeactivateRequest = { [weak self] in self?.deactivate() }
            canvas.onCopyRequest = { [weak self] region in
                if region { self?.copyRegion() } else { self?.copyScreen() }
            }
            if regionPickWasActive != nil { beginRegionPick(on: canvas, displayID: id) }
            panel.contentView = canvas
            overlays[id] = Overlay(panel: panel, canvas: canvas)
            if isActive {
                panel.ignoresMouseEvents = false
                panel.orderFrontRegardless()
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
