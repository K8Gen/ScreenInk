# Copy Screen / Copy Region… (PNG to clipboard) — Implementation Plan

> **For the executing agent:** Do the tasks in order. Do one step at a time. Commit after each task. Read [`design.md`](design.md) first for the behavior and the reasons. All code in this plan was compiled and tested on macOS 14+ (arm64) before this plan was written.

**Goal:** Add **Copy Screen** (⌘C) and **Copy Region…** (⇧⌘C). They put a PNG of the screen, with the annotations on top, on the clipboard.

**Architecture:** ScreenCaptureKit captures one display without ScreenInk's own windows. `ExportRenderer` draws the annotations from the `Document` model over the capture and crops the result. `ScreensController` chooses the screen and runs the region pick with a temporary `RegionTool` on every canvas.

**Tech stack:** Swift 6 (strict concurrency), SwiftPM only (no Xcode project), AppKit, Core Animation, ScreenCaptureKit (`SCScreenshotManager`, macOS 14), Swift Testing.

---

## Rules for this repository

- Read `AGENTS.md`. Pure logic goes in `ScreenInkCore` (no AppKit). AppKit code goes in `ScreenInk`.
- Coordinates are screen-local points with a top-left origin. All views are flipped.
- Match the style of the code around your change: comment density, naming, `// MARK:` sections.
- Work on the branch `feature/export-png`. Commit after each task.
- **Open the pull request only in `K8Gen/ScreenInk`.** Use `gh pr create --repo K8Gen/ScreenInk --base main`. Do not open issues or pull requests in any other repository. Do not mention issues or pull requests of other repositories.

## Verify commands

You need macOS 14 or later on Apple Silicon. CI (`.github/workflows/ci.yml`, `macos-15`) runs the same three checks on each push.

| Check | Command | Pass |
|---|---|---|
| Unit tests | `scripts/test.sh` (on a Mac with Xcode, `swift test` is also OK) | `Test run with N tests … passed` |
| App bundle | `scripts/build-app.sh` | `Built build/ScreenInk.app (arm64)` |
| Rendering self-test | `build/ScreenInk.app/Contents/MacOS/ScreenInk --self-test /tmp/screenink-selftest` | `self-test: PASS` |

If `scripts/test.sh` fails with `plugin for module 'TestingMacros' not found`, the build cache is stale. Run `rm -rf .build`, then run `scripts/test.sh` again.

At the start, run all three checks once. Before your change: 34 unit tests pass, and the self-test passes.

---

### Task 1: Region geometry in ScreenInkCore

**Files:**
- Create: `Sources/ScreenInkCore/ExportRegion.swift`
- Test: `Tests/ScreenInkCoreTests/ExportRegionTests.swift`

**Step 1: Write the failing test.** Create `Tests/ScreenInkCoreTests/ExportRegionTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ScreenInkCore

@Suite struct ExportRegionTests {
    let screen = CGRect(x: 0, y: 0, width: 300, height: 200)

    @Test func dragInAnyDirectionGivesTheSameRect() {
        let expected = CGRect(x: 40, y: 60, width: 60, height: 40)
        #expect(ExportRegion.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 100, y: 100), in: screen) == expected)
        #expect(ExportRegion.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 60), in: screen) == expected)
    }

    @Test func dragPastTheEdgeIsClippedToTheScreen() {
        let rect = ExportRegion.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: -50, y: 500), in: screen)
        #expect(rect == CGRect(x: 0, y: 10, width: 10, height: 190))
    }

    @Test func clickOrThinDragIsNil() {
        #expect(ExportRegion.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10), in: screen) == nil)
        #expect(ExportRegion.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 80), in: screen) == nil)
    }

    @Test func pixelRectScalesAndRoundsOutward() {
        let rect = CGRect(x: 10.25, y: 5.5, width: 20, height: 10)
        let pixels = ExportRegion.pixelRect(for: rect, scale: 2, imageSize: CGSize(width: 600, height: 400))
        #expect(pixels == CGRect(x: 20, y: 11, width: 41, height: 20))
    }

    @Test func pixelRectStaysInsideTheImage() {
        let rect = CGRect(x: 290, y: 190, width: 20, height: 20)
        let pixels = ExportRegion.pixelRect(for: rect, scale: 1, imageSize: CGSize(width: 300, height: 200))
        #expect(pixels == CGRect(x: 290, y: 190, width: 10, height: 10))
        #expect(ExportRegion.pixelRect(for: CGRect(x: 400, y: 0, width: 10, height: 10), scale: 1,
            imageSize: CGSize(width: 300, height: 200)) == nil)
    }
}
```

**Step 2: Run the test. Make sure that it fails.**
Run: `scripts/test.sh --filter ExportRegionTests`
Expected: the build fails with `cannot find 'ExportRegion' in scope`.

**Step 3: Write the implementation.** Create `Sources/ScreenInkCore/ExportRegion.swift`:

```swift
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
```

**Step 4: Run the tests. Make sure that they pass.**
Run: `scripts/test.sh`
Expected: `Test run with 39 tests in 10 suites passed`.

**Step 5: Commit.**
```bash
git add Sources/ScreenInkCore/ExportRegion.swift Tests/ScreenInkCoreTests/ExportRegionTests.swift
git commit -m "Add ExportRegion geometry for the copy region"
```

---

### Task 2: Screen capture with ScreenCaptureKit

**Files:**
- Modify: `Package.swift` (the `ScreenInk` target `linkerSettings`)
- Create: `Sources/ScreenInk/ScreenCapturer.swift`

**Step 1: Link the framework.** In `Package.swift`, replace:

```swift
            linkerSettings: [.linkedFramework("Carbon")]
```

with:

```swift
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ScreenCaptureKit")]
```

**Step 2: Write the capturer.** Create `Sources/ScreenInk/ScreenCapturer.swift`:

```swift
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
```

**Step 3: Build.**
Run: `swift build`
Expected: `Build complete!` with no compiler warnings.

**Step 4: Commit.**
```bash
git add Package.swift Sources/ScreenInk/ScreenCapturer.swift
git commit -m "Add ScreenCapturer: one ScreenCaptureKit image without our windows"
```

---

### Task 3: Flatten the capture and the annotations

**Files:**
- Create: `Sources/ScreenInk/ExportRenderer.swift`
- Modify: `Sources/ScreenInk/SelfTest.swift` (new check 8, three new helpers)

**Step 1: Write the failing self-test check.** In `Sources/ScreenInk/SelfTest.swift`, in `run(outputDirectory:)`, find this line:

```swift
        print("self-test: live/committed pixel difference \(String(format: "%.4f%%", difference * 100))")
```

Put this block immediately before it:

```swift
        // 8. Export: the capture under the annotations, no dimming, crops in top-left pixels.
        document.removeAll()
        toolState.colorIndex = 0  // red
        toolState.tool = .rectangle
        canvas.simulateGesture([CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150)])
        toolState.dimLevel = 0.5
        let blue: [UInt8] = [0, 0, 255, 255]
        let background = solidImage(width: Int(size.width) * 2, height: Int(size.height) * 2, rgba: blue)
        if let export = ExportRenderer.render(
            background: background, annotations: document.annotations, pointSize: size, rect: nil)
        {
            save(export, "8-export.png", in: outputDirectory)
            check(export.width == background.width && export.height == background.height, "export isn't screen-sized")
            check(rgba(export, at: CGPoint(x: 10, y: 10), viewSize: size) == blue, "export lost the background (or dimmed it)")
            check(isRed(rgba(export, at: CGPoint(x: 100, y: 100), viewSize: size)), "export lost the rectangle (flipped?)")
        } else {
            check(false, "export render failed")
        }
        let crop = CGRect(x: 90, y: 40, width: 40, height: 40)
        if let region = ExportRenderer.render(
            background: background, annotations: document.annotations, pointSize: size, rect: crop)
        {
            save(region, "9-export-region.png", in: outputDirectory)
            check(region.width == 80 && region.height == 80, "region is \(region.width)×\(region.height), expected 80×80")
            check(rgba(region, at: CGPoint(x: 5, y: 5), viewSize: crop.size) == blue, "region corner isn't background")
            check(isRed(rgba(region, at: CGPoint(x: 10, y: 30), viewSize: crop.size)), "region crop is off (flipped?)")
        } else {
            check(false, "region render failed")
        }
        toolState.dimLevel = 0

```

In the same file, find:

```swift
    private static func pixels(_ image: CGImage) -> [UInt8] {
```

Put these three helpers immediately before it:

```swift
    private static func solidImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(
            red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255, blue: CGFloat(rgba[2]) / 255,
            alpha: CGFloat(rgba[3]) / 255)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The pixel at `point` (top-left view coordinates) as [r, g, b, a], premultiplied.
    private static func rgba(_ image: CGImage, at point: CGPoint, viewSize: CGSize) -> [UInt8] {
        let scale = CGFloat(image.width) / viewSize.width
        let index = (Int(point.y * scale) * image.width + Int(point.x * scale)) * 4
        return Array(pixels(image)[index..<index + 4])
    }

    private static func isRed(_ pixel: [UInt8]) -> Bool {
        pixel[0] > 180 && pixel[1] < 120 && pixel[2] < 120
    }

```

**Step 2: Build. Make sure that it fails.**
Run: `swift build`
Expected: `cannot find 'ExportRenderer' in scope`.

**Step 3: Write the renderer.** Create `Sources/ScreenInk/ExportRenderer.swift`:

```swift
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
```

**Step 4: Run the self-test. Make sure that it passes.**
Run: `scripts/build-app.sh && build/ScreenInk.app/Contents/MacOS/ScreenInk --self-test /tmp/screenink-selftest`
Expected: `self-test: PASS`.
Open `/tmp/screenink-selftest/8-export.png`. You must see a red rounded rectangle on blue, in the upper-left part of the image. Open `9-export-region.png`. You must see the upper-left corner of that rectangle.

**Step 5: Commit.**
```bash
git add Sources/ScreenInk/ExportRenderer.swift Sources/ScreenInk/SelfTest.swift
git commit -m "Add ExportRenderer: capture plus annotations from the model, cropped"
```

---

### Task 4: Region tool and region pick on the canvas

**Files:**
- Modify: `Sources/ScreenInk/CanvasTools.swift` (append `RegionTool`)
- Modify: `Sources/ScreenInk/CanvasView.swift`
- Modify: `Sources/ScreenInk/SelfTest.swift` (new check 9)

**Step 1: Write the failing self-test check.** In `SelfTest.swift`, put this block immediately after the line `toolState.dimLevel = 0` that ends check 8 (and before the `print("self-test: live/committed …` line):

```swift
        // 9. Copy Region… swaps in the region tool: a drag gives the rect, a click cancels.
        var picked: CGRect?? = nil
        canvas.beginRegionPick { picked = .some($0) }
        check(canvas.currentTool is RegionTool, "region pick didn't swap in the region tool")
        canvas.simulateGesture([CGPoint(x: 300, y: 250), CGPoint(x: 250, y: 220), CGPoint(x: 220, y: 200)])
        check(picked == .some(CGRect(x: 220, y: 200, width: 80, height: 50)), "region pick gave \(String(describing: picked))")
        check(document.annotations.count == 1, "the region drag drew an annotation")
        canvas.endRegionPick()
        check(canvas.currentTool is ShapeTool, "the rectangle tool wasn't restored after the pick")
        picked = nil
        canvas.beginRegionPick { picked = .some($0) }
        canvas.simulateGesture([CGPoint(x: 50, y: 50)])
        check(picked == .some(nil), "a click didn't cancel the region pick")
        canvas.endRegionPick()
        document.removeAll()

```

**Step 2: Build. Make sure that it fails.**
Run: `swift build`
Expected: `value of type 'CanvasView' has no member 'beginRegionPick'`.

**Step 3: Add the region tool.** Append to the end of `Sources/ScreenInk/CanvasTools.swift`:

```swift

/// Copy Region…: drag a rectangle to copy that part of the screen. Swapped in by
/// `CanvasView.beginRegionPick(onFinish:)` instead of the current tool. `onFinish` gets the
/// rect, or nil when the pick was a click (or Esc, via `abort(in:)`).
@MainActor
final class RegionTool: CanvasTool {
    private let onFinish: (CGRect?) -> Void
    private var start: CGPoint?

    init(onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: PointerInput, in canvas: CanvasView) {
        start = input.point
    }

    func mouseDragged(_ input: PointerInput, in canvas: CanvasView) {
        guard let start else { return }
        canvas.overlayView.showMarquee(ExportRegion.rect(from: start, to: input.point, in: canvas.bounds))
    }

    func mouseUp(_ input: PointerInput, in canvas: CanvasView) {
        guard let start else { return }
        cancel(in: canvas)
        onFinish(ExportRegion.rect(from: start, to: input.point, in: canvas.bounds))
    }

    /// Esc: ends the pick without a rect.
    func abort(in canvas: CanvasView) {
        cancel(in: canvas)
        onFinish(nil)
    }

    func cancel(in canvas: CanvasView) {
        start = nil
        canvas.overlayView.showMarquee(nil)
    }
}
```

**Step 4: Change `CanvasView`.** Make these edits in `Sources/ScreenInk/CanvasView.swift`.

4a. After `var onDeactivateRequest: (() -> Void)?`, add:

```swift
    /// ⌘C (whole screen) or ⇧⌘C (pick a region).
    var onCopyRequest: ((_ region: Bool) -> Void)?
```

4b. After `private var dragOffset: CGVector?`, add:

```swift
    /// Set while Copy Region… waits for a drag; the region tool replaces the current tool.
    private(set) var isPickingRegion = false
```

4c. Replace the whole `toolStateDidChange()` function with:

```swift
    private func toolStateDidChange() {
        dimView.setLevel(toolState.dimLevel, animated: true)
        guard toolState.tool != toolKind, !isPickingRegion else { return }
        tool.cancel(in: self)
        endTextEditing()
        toolKind = toolState.tool
        tool = makeTool(toolKind)
        if toolKind != .select { selection = [] }
        updateCursorIfInside()
    }
```

4d. Immediately before the line `// MARK: Selection`, add:

```swift
    // MARK: Region pick

    /// Swaps in the region tool until `endRegionPick()`. `onFinish` gets the dragged rect,
    /// or nil for a click or Esc.
    func beginRegionPick(onFinish: @escaping (CGRect?) -> Void) {
        cancelInteraction()
        tool = RegionTool(onFinish: onFinish)
        isPickingRegion = true
        updateCursorIfInside()
    }

    /// Puts the current tool back. Safe to call when no pick is running.
    func endRegionPick() {
        guard isPickingRegion else { return }
        tool.cancel(in: self)
        isPickingRegion = false
        toolKind = toolState.tool
        tool = makeTool(toolKind)
        updateCursorIfInside()
    }

    private func updateCursorIfInside() {
        if window?.isVisible == true, let window,
            bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        {
            tool.cursor.set()
        }
    }

```

4e. In `keyDown(with:)`, make these lines the first lines of the function body:

```swift
        if let region = tool as? RegionTool {
            // While picking a region, Esc cancels and every other key is ignored.
            if Int(event.keyCode) == kVK_Escape { region.abort(in: self) }
            return
        }
```

4f. In `performKeyEquivalent(with:)`, after the `case (kVK_ANSI_RightBracket, [.command]):` case and its body, add:

```swift
        case (kVK_ANSI_C, [.command]):
            onCopyRequest?(false)
        case (kVK_ANSI_C, [.command, .shift]):
            onCopyRequest?(true)
```

**Step 5: Run the self-test. Make sure that it passes.**
Run: `scripts/build-app.sh && build/ScreenInk.app/Contents/MacOS/ScreenInk --self-test /tmp/screenink-selftest`
Expected: `self-test: PASS`.

**Step 6: Commit.**
```bash
git add Sources/ScreenInk/CanvasTools.swift Sources/ScreenInk/CanvasView.swift Sources/ScreenInk/SelfTest.swift
git commit -m "Add the region tool and region pick to the canvas, plus ⌘C/⇧⌘C requests"
```

---

### Task 5: Copy flash on the overlay

**Files:**
- Modify: `Sources/ScreenInk/OverlayLayerView.swift`

**Step 1: Make the edits.**

5a. Replace the type comment with:

```swift
/// Transient visuals above the annotations: shape previews, selection boxes, the marquee,
/// the eraser ring and the copy flash. Layer-hosting, top-left geometry.
```

5b. After `private let eraserLayer = CAShapeLayer()`, add:

```swift
    private let flashLayer = CAShapeLayer()
```

5c. In `init(frame:)`, after `eraserLayer.lineWidth = 1`, add:

```swift
        flashLayer.fillColor = NSColor.white.cgColor
        flashLayer.opacity = 0
```

5d. In `init(frame:)` and in `layout()`, the array `[previewContainer, selectionLayer, marqueeLayer, eraserLayer]` occurs two times. In both places, change it to `[previewContainer, selectionLayer, marqueeLayer, eraserLayer, flashLayer]`.

5e. Add these members at the end of the class, before its closing brace:

```swift

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
```

**Step 2: Build.**
Run: `swift build`
Expected: `Build complete!`.

**Step 3: Commit.**
```bash
git add Sources/ScreenInk/OverlayLayerView.swift
git commit -m "Add a copy flash to the overlay layer"
```

---

### Task 6: Exporter (pasteboard, permission, alerts)

**Files:**
- Create: `Sources/ScreenInk/ScreenExporter.swift`

**Step 1: Write the exporter.** Create `Sources/ScreenInk/ScreenExporter.swift`:

```swift
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
```

`screen.displayID` is the existing `NSScreen` extension at the end of `ScreensController.swift`.

**Step 2: Build.**
Run: `swift build`
Expected: `Build complete!` with no compiler warnings.

**Step 3: Commit.**
```bash
git add Sources/ScreenInk/ScreenExporter.swift
git commit -m "Add ScreenExporter: PNG to the pasteboard, permission and failure alerts"
```

---

### Task 7: Wire it up in ScreensController and the menu

**Files:**
- Modify: `Sources/ScreenInk/ScreensController.swift`
- Modify: `Sources/ScreenInk/StatusItemController.swift`

**Step 1: Change `ScreensController`.**

7a. After `private var screenObserver: NSObjectProtocol?`, add:

```swift
    /// Set while Copy Region… waits for a drag: whether drawing was on before the pick began.
    private var regionPickWasActive: Bool?
```

7b. Make these lines the first lines of `deactivate()`:

```swift
        if regionPickWasActive != nil {
            regionPickWasActive = nil
            for overlay in overlays.values { overlay.canvas.endRegionPick() }
        }
```

7c. Replace the `activeCanvas` property with this block. The block also adds the copy functions:

```swift
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
```

7d. In `rebuildOverlays()`, after `canvas.onDeactivateRequest = { [weak self] in self?.deactivate() }`, add:

```swift
            canvas.onCopyRequest = { [weak self] region in
                if region { self?.copyRegion() } else { self?.copyScreen() }
            }
            if regionPickWasActive != nil { beginRegionPick(on: canvas, displayID: id) }
```

The second line lets a monitor that is plugged in during a pick join the pick.

**Step 2: Change `StatusItemController`.**

2a. In `menuNeedsUpdate(_:)`, after `menu.addItem(clear)`, add:

```swift

        menu.addItem(.separator())
        menu.addItem(item("Copy Screen", #selector(copyScreen), key: "c"))
        let region = item("Copy Region…", #selector(copyRegion), key: "c")
        region.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(region)
        menu.addItem(.separator())
```

2b. After the `clearAll()` action method, add:

```swift

    @objc private func copyScreen() {
        screens.copyScreen()
    }

    @objc private func copyRegion() {
        screens.copyRegion()
    }
```

**Step 3: Run all three checks.**
Run: `scripts/test.sh && scripts/build-app.sh && build/ScreenInk.app/Contents/MacOS/ScreenInk --self-test /tmp/screenink-selftest`
Expected: 39 tests pass, `Built build/ScreenInk.app (arm64)`, `self-test: PASS`. No compiler warnings.

**Step 4: Commit.**
```bash
git add Sources/ScreenInk/ScreensController.swift Sources/ScreenInk/StatusItemController.swift
git commit -m "Add Copy Screen and Copy Region… to the menu and the overlay"
```

---

### Task 8: Documentation

**Files:**
- Modify: `README.md`
- Modify: `PLAN.md` (the **Status** block in section 7)

**Step 1: README.** In `## Features`, add this bullet after the "Menu-bar settings" bullet:

```markdown
- Copy the screen or a dragged region, with the drawings, to the clipboard as PNG (needs the Screen Recording permission)
```

In the table under `## Shortcuts while drawing`, add this row after the `⌘A · ⌘]` row:

```markdown
| ⌘C · ⇧⌘C | Copy screen · Copy region (PNG to the clipboard) |
```

**Step 2: PLAN.md.** In the **Status** block, add one more deviation bullet:

```markdown
- **Phase 5, early part:** Copy Screen (⌘C) and Copy Region… (⇧⌘C) put a PNG of the screen with the annotations on the clipboard (`ScreenCapturer`, `ExportRenderer`, `ScreenExporter`, `ExportRegion`). The capture excludes our own windows, and the annotations come from the model. Snapshots, the gallery, PDF and file export are still open. Design: `.kiro/specs/export-png/design.md`.
```

**Step 3: Commit.**
```bash
git add README.md PLAN.md
git commit -m "Document Copy Screen and Copy Region…"
```

---

### Task 9: Manual test, push and pull request

**Step 1: Manual test on a Mac.** The capture cannot run in CI. Run `make run` (or open `build/ScreenInk.app`). Then do these checks:

1. Menu-bar icon › **Copy Screen**. You see the "Allow Screen Recording" alert. Click **Continue**. macOS shows its prompt. Allow ScreenInk. If macOS asks, quit and reopen ScreenInk.
2. Draw something (⌃⌥⌘A, then the pen). Press ⌘C. The screen flashes white. Paste into Preview (File › New from Clipboard). You see the screen content with the drawing, without the palette and without the dimming.
3. Press ⇧⌘C. The palette hides and the cursor is a crosshair. Drag a rectangle. The rectangle flashes and the palette comes back. Paste: only that region is in the image, at Retina resolution.
4. Stop drawing (Esc). Menu › **Copy Region…**. Drag. The overlay hides again after the flash. The pasted image has the drawings.
5. Start Copy Region…, then press Esc. Nothing is copied, and the earlier state comes back. Do the same with a single click.
6. With two displays: Copy Region… on the second display. The image shows the second display only.
7. Turn off Screen Recording for ScreenInk in System Settings. Press ⌘C. The overlay hides, and the alert offers **Open System Settings**.

Note: the bundle is ad-hoc signed. After each rebuild, macOS can forget the permission. Then step 7 happens, and you must allow ScreenInk again.

**Step 2: Push the branch.**
```bash
git push origin feature/export-png
```
Here `origin` must be `K8Gen/ScreenInk`. Check with `git remote -v` before the push.

**Step 3: Open the pull request in `K8Gen/ScreenInk` only.**
```bash
gh pr create --repo K8Gen/ScreenInk --base main --head feature/export-png \
  --title "Copy Screen / Copy Region… (PNG to the clipboard)" \
  --body "Implements .kiro/specs/export-png/plan.md. Unit tests, app bundle and self-test pass. Manual checks: <list the results of Task 9 step 1>."
```

**Step 4:** Make sure that CI passes on the pull request.
