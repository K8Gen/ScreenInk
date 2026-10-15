import AppKit
import ScreenInkCore

/// Copy Screen / Copy Region…: the capture, the flattening, the pasteboard write and the
/// alerts. ScreensController decides which screen and which rect.
///
/// The overlay sits above alert windows and takes the clicks, so callers hide it before
/// they call `askForPermission()` or `showFailure(_:)`.
@MainActor
enum ScreenExporter {
    enum Failure: LocalizedError {
        case noImage

        var errorDescription: String? { "ScreenInk couldn't make the image." }
    }

    private static let askedKey = "ScreenCaptureAsked"

    /// Captures `screen`, draws `annotations` over it, crops to `rect` (points, top-left;
    /// nil = whole screen) and puts the PNG on the general pasteboard.
    static func copy(screen: NSScreen, annotations: [Annotation], rect: CGRect?) async throws {
        guard let displayID = screen.displayID else { throw ScreenCapturer.Failure.displayNotFound }
        let pointSize = screen.frame.size
        let scale = screen.backingScaleFactor
        let background = try await ScreenCapturer.capture(
            displayID: displayID, pixelSize: CGSize(width: pointSize.width * scale, height: pointSize.height * scale))
        guard
            let image = ExportRenderer.render(
                background: background, annotations: annotations, pointSize: pointSize, rect: rect),
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw Failure.noImage }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    /// Explains why Screen Recording is needed and asks for it. The first time, macOS shows
    /// its own prompt after ours. After that, macOS doesn't prompt again, so we offer System Settings.
    static func askForPermission() {
        let defaults = UserDefaults.standard
        let alert = NSAlert()
        if !defaults.bool(forKey: askedKey) {
            defaults.set(true, forKey: askedKey)
            alert.messageText = "Allow Screen Recording"
            alert.informativeText =
                "To copy the screen with your drawings, ScreenInk needs the Screen Recording permission. macOS asks for it once."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            if run(alert) == .alertFirstButtonReturn { ScreenCapturer.requestPermission() }
            return
        }
        alert.messageText = "Screen Recording is off for ScreenInk"
        alert.informativeText =
            "Turn on ScreenInk in System Settings › Privacy & Security › Screen & System Audio Recording, then try again. macOS may ask you to reopen ScreenInk."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if run(alert) == .alertFirstButtonReturn,
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }

    static func showFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't copy the screen"
        alert.informativeText = error.localizedDescription
        run(alert)
    }

    /// An accessory app must activate itself for the alert to take keyboard focus.
    @discardableResult
    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
