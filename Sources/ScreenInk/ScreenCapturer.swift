import AppKit
import ScreenCaptureKit

/// One still image of a display without ScreenInk's own windows (PLAN.md §3, "Screen capture").
/// Needs the Screen Recording permission.
enum ScreenCapturer {
    enum Failure: LocalizedError {
        case displayNotFound

        var errorDescription: String? { "The display is no longer connected." }
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time it is called. Later calls only return the current answer.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// The display's pixels at `pixelSize`, top-left first, without the cursor.
    static func capture(displayID: CGDirectDisplayID, pixelSize: CGSize) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Failure.displayNotFound
        }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
