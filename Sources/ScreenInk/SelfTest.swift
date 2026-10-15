import AppKit
import ScreenInkCore

/// `ScreenInk --self-test <dir>`: exercises the real canvas, tools and rendering off-screen,
/// writes PNGs to `dir`, and checks pixels and document state. Used where the UI can't be
/// driven directly (CI, no Accessibility permission).
@MainActor
enum SelfTest {
    private static var failures: [String] = []

    private static func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    static func run(outputDirectory: URL) -> Bool {
        failures = []
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "ScreenInkSelfTest")!
        defaults.removePersistentDomain(forName: "ScreenInkSelfTest")
        let toolState = ToolState(defaults: defaults)
        let size = NSSize(width: 400, height: 300)
        let document = Document()
        let canvas = CanvasView(frame: NSRect(origin: .zero, size: size), document: document, toolState: toolState)
        func saveCanvas(_ name: String) { save(canvas.snapshot(), name, in: outputDirectory) }

        // 1. Pen stroke: live raster vs committed vector, orientation, undo/redo.
        let wave = (0...60).map { i -> CGPoint in
            let t = Double(i) / 60
            return CGPoint(x: 20 + t * 360, y: 20 + t * 260 + sin(t * 12) * 20)
        }
        canvas.currentTool.mouseDown(PointerInput(point: wave[0]), in: canvas)
        for point in wave.dropFirst().dropLast() { canvas.currentTool.mouseDragged(PointerInput(point: point), in: canvas) }
        let live = canvas.snapshot()
        canvas.currentTool.mouseUp(PointerInput(point: wave.last!), in: canvas)
        let committed = canvas.snapshot()
        save(live, "1-live.png", in: outputDirectory)
        save(committed, "2-committed.png", in: outputDirectory)
        check(isInk(committed, at: wave[0], viewSize: size), "no ink at stroke start (orientation?)")
        check(!isInk(committed, at: CGPoint(x: 20, y: 280), viewSize: size), "ink at bottom-left (flipped?)")
        let difference = differingFraction(live, committed)
        check(difference < 0.01, "live vs committed differ in \(difference * 100)% of pixels")
        document.undo()
        check(inkFraction(canvas.snapshot()) == 0, "undo left ink behind")
        document.redo()
        check(differingFraction(canvas.snapshot(), committed) < 0.001, "redo didn't restore the stroke")
        document.removeAll()

        // 2. Every tool, drawn through the same dispatch the mouse uses.
        toolState.colorIndex = 4  // blue
        toolState.tool = .rectangle
        canvas.simulateGesture([CGPoint(x: 30, y: 30), CGPoint(x: 90, y: 60), CGPoint(x: 150, y: 90)])
        toolState.tool = .ellipse
        canvas.simulateGesture([CGPoint(x: 200, y: 30), CGPoint(x: 290, y: 75)], shift: true)
        toolState.tool = .line
        canvas.simulateGesture([CGPoint(x: 30, y: 130), CGPoint(x: 150, y: 138)], shift: true)
        toolState.tool = .arrow
        canvas.simulateGesture([CGPoint(x: 200, y: 140), CGPoint(x: 360, y: 140)], option: true)
        toolState.colorIndex = 0
        toolState.tool = .badge
        canvas.simulateGesture([CGPoint(x: 330, y: 50)])
        canvas.simulateGesture([CGPoint(x: 370, y: 50)])
        toolState.tool = .highlighter
        canvas.simulateGesture((0...20).map { CGPoint(x: 30 + Double($0) * 6, y: 200) })
        toolState.tool = .text
        canvas.simulateGesture([CGPoint(x: 200, y: 200)])
        canvas.editingTextView?.insertText("Hello, ScreenInk", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.endTextEditing()
        saveCanvas("4-all-tools.png")

        let kinds = document.annotations.map(\.kind)
        check(
            kinds == [.rectangle, .ellipse, .line, .arrow, .badge, .badge, .stroke, .text],
            "unexpected annotations: \(kinds)")
        let badges = document.annotations.compactMap { annotation -> Int? in
            if case let .badge(_, number, _, _) = annotation.geometry { return number }
            return nil
        }
        check(badges == [1, 2], "badges numbered \(badges)")
        if case let .ellipse(rect) = document.annotations[safe: 1]?.geometry {
            check(rect.width == rect.height, "Shift didn't make a circle")
        }
        if case let .line(from, to) = document.annotations[safe: 2]?.geometry {
            check(from.y == to.y, "Shift didn't snap the line horizontal")
        }
        if case let .arrow(_, _, control) = document.annotations[safe: 3]?.geometry {
            check(control != nil, "⌥ didn't curve the arrow")
        }
        check(document.annotations[safe: 6]?.style.blend == .multiply, "highlighter isn't multiply-blended")
        if case let .text(_, string, _) = document.annotations.last?.geometry {
            check(string == "Hello, ScreenInk", "text was \(string)")
        }

        // 3. Select and move the rectangle by dragging its edge.
        let rectangleID = document.annotations[0].id
        let before = document.annotations[0].bounds
        toolState.tool = .select
        canvas.simulateGesture([CGPoint(x: 30, y: 60), CGPoint(x: 60, y: 70), CGPoint(x: 80, y: 80)])
        check(canvas.selection == [rectangleID], "click didn't select the rectangle")
        let after = document.annotations.first { $0.id == rectangleID }?.bounds ?? .null
        check(after.minX - before.minX == 50 && after.minY - before.minY == 20, "move went to \(after)")

        // 4. A color key recolors the selection.
        canvas.perform(.color(3))
        check(document.annotations.first { $0.id == rectangleID }?.style.color == RGBA.palette[3], "recolor failed")

        // 5. Erase the ellipse by crossing its outline; one undo brings it back.
        let ellipseID = document.annotations[1].id
        toolState.tool = .eraser
        canvas.simulateGesture([CGPoint(x: 245, y: 20), CGPoint(x: 245, y: 40)])
        check(!document.annotations.contains { $0.id == ellipseID }, "eraser missed the ellipse")
        check(document.annotations.count == 7, "eraser removed \(8 - document.annotations.count) annotations")
        document.undo()
        check(document.annotations.contains { $0.id == ellipseID }, "undo didn't restore the erased ellipse")
        saveCanvas("5-after-edits.png")

        // 6. A single pen click leaves a dot.
        toolState.tool = .pen
        canvas.simulateGesture([CGPoint(x: 200, y: 260)])
        check(isInk(canvas.snapshot(), at: CGPoint(x: 200, y: 260), viewSize: size), "click didn't leave a dot")

        // 7. Dimming darkens empty areas behind the ink, and turns off again.
        let empty = CGPoint(x: 4, y: 4)
        check(alpha(canvas.snapshot(), at: empty, viewSize: size) == 0, "corner isn't empty before dimming")
        toolState.dimLevel = 0.35
        let dimmed = canvas.snapshot()
        save(dimmed, "6-dimmed.png", in: outputDirectory)
        let dimAlpha = alpha(dimmed, at: empty, viewSize: size)
        check(abs(dimAlpha - 89) <= 10, "dim alpha \(dimAlpha), expected about 89")
        check(isInk(dimmed, at: CGPoint(x: 200, y: 260), viewSize: size), "dimming hid the ink")
        toolState.dimLevel = 0
        check(alpha(canvas.snapshot(), at: empty, viewSize: size) == 0, "dimming didn't turn off")

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

        print("self-test: live/committed pixel difference \(String(format: "%.4f%%", difference * 100))")
        for failure in failures { print("FAIL: \(failure)") }
        print(failures.isEmpty ? "self-test: PASS" : "self-test: FAIL")
        return failures.isEmpty
    }

    private static func save(_ image: CGImage, _ name: String, in directory: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
    }

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

    private static func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// `point` is in top-left view coordinates; rows in `pixels` run top to bottom.
    private static func isInk(_ image: CGImage, at point: CGPoint, viewSize: NSSize) -> Bool {
        alpha(image, at: point, viewSize: viewSize) > 128
    }

    private static func alpha(_ image: CGImage, at point: CGPoint, viewSize: NSSize) -> Int {
        let scale = CGFloat(image.width) / viewSize.width
        let x = Int(point.x * scale)
        let y = Int(point.y * scale)
        return Int(pixels(image)[(y * image.width + x) * 4 + 3])
    }

    private static func inkFraction(_ image: CGImage) -> Double {
        let data = pixels(image)
        let inked = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 0 }.count
        return Double(inked) / Double(image.width * image.height)
    }

    private static func differingFraction(_ a: CGImage, _ b: CGImage) -> Double {
        let (pa, pb) = (pixels(a), pixels(b))
        guard pa.count == pb.count else { return 1 }
        var differing = 0
        for i in stride(from: 3, to: pa.count, by: 4) where abs(Int(pa[i]) - Int(pb[i])) > 64 {
            differing += 1
        }
        return Double(differing) / Double(a.width * a.height)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension CanvasView {
    /// Composites the canvas layers the same way the screen does, on a white background.
    func snapshot() -> CGImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let context = CGContext(
            data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        for view in subviews where !view.isHidden {
            if view is DimView || view is AnnotationsView || view is OverlayLayerView, let layer = view.layer {
                // CALayer.render draws in the layer's own (flipped) space; flip to bitmap space.
                context.saveGState()
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)
                layer.render(in: context)
                context.restoreGState()
            } else if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let image = rep.cgImage {
                    context.setAlpha(view.alphaValue)
                    context.draw(image, in: view.frame)
                    context.setAlpha(1)
                }
            }
        }
        return context.makeImage()!
    }
}
