import AppKit
import ScreenInkCore

/// One pointer sample with the modifier state that tools care about.
struct PointerInput {
    var point: CGPoint
    /// 0…1; a mouse reports 1 while the button is down.
    var pressure: Double = 1
    var shift = false
    var option = false
    var clickCount = 1
}

/// A drawing tool. A fresh instance is made per canvas whenever the tool changes.
@MainActor
protocol CanvasTool: AnyObject {
    var cursor: NSCursor { get }
    func mouseDown(_ input: PointerInput, in canvas: CanvasView)
    func mouseDragged(_ input: PointerInput, in canvas: CanvasView)
    func mouseUp(_ input: PointerInput, in canvas: CanvasView)
    /// Abandons any gesture in progress (tool switch, deactivation).
    func cancel(in canvas: CanvasView)
}

/// Pen and highlighter: smoothed variable-width strokes via the live bitmap cache.
/// Holding ⌥ while starting a pen stroke draws a highlighter stroke instead.
@MainActor
final class FreehandTool: CanvasTool {
    private let kind: ToolKind
    private var builder: StrokeBuilder?
    private var style = Style.defaultPen
    private var pressureFilter = PressureFilter()
    private var lastWidth: CGFloat = 1
    private var usesPressure = true

    init(kind: ToolKind) {
        self.kind = kind
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: PointerInput, in canvas: CanvasView) {
        let effectiveKind: ToolKind = input.option && kind == .pen ? .highlighter : kind
        style = canvas.toolState.style(for: effectiveKind)
        usesPressure = effectiveKind == .pen
        builder = StrokeBuilder()
        pressureFilter.reset()
        canvas.liveView.begin(style: style)
        let width = width(for: input.pressure)
        _ = builder?.add(input.point, width: width)
        // Immediate feedback for a click; later segments draw over it.
        canvas.liveView.append(StrokeOutline.dot(at: input.point, width: width), color: style.color.cgColor)
    }

    func mouseDragged(_ input: PointerInput, in canvas: CanvasView) {
        guard builder != nil else { return }
        if let segment = builder?.add(input.point, width: width(for: input.pressure)) {
            canvas.liveView.append(StrokeOutline.outline(of: segment), color: style.color.cgColor)
        }
    }

    func mouseUp(_ input: PointerInput, in canvas: CanvasView) {
        guard var builder else { return }
        // Mouse-up reports zero pressure, so keep the last width for the final sample.
        _ = builder.add(input.point, width: lastWidth)
        self.builder = nil
        canvas.commit(Annotation(geometry: .stroke(points: builder.points, widths: builder.widths), style: style))
        canvas.liveView.clear()
    }

    func cancel(in canvas: CanvasView) {
        builder = nil
        canvas.liveView.clear()
    }

    private func width(for pressure: Double) -> CGFloat {
        guard usesPressure else {
            lastWidth = CGFloat(style.width)
            return lastWidth
        }
        lastWidth = pressureFilter.width(base: style.width, pressure: pressureFilter.filter(pressure))
        return lastWidth
    }
}

/// Line, arrow, rectangle and ellipse: drag out a preview, commit on release.
/// Shift constrains; ⌥ bends arrows.
@MainActor
final class ShapeTool: CanvasTool {
    private let kind: ToolKind
    private var start: CGPoint?

    init(kind: ToolKind) {
        self.kind = kind
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: PointerInput, in canvas: CanvasView) {
        start = input.point
    }

    func mouseDragged(_ input: PointerInput, in canvas: CanvasView) {
        canvas.overlayView.showPreview(annotation(to: input, in: canvas))
    }

    func mouseUp(_ input: PointerInput, in canvas: CanvasView) {
        if let annotation = annotation(to: input, in: canvas) { canvas.commit(annotation) }
        cancel(in: canvas)
    }

    func cancel(in canvas: CanvasView) {
        start = nil
        canvas.overlayView.showPreview(nil)
    }

    private func annotation(to input: PointerInput, in canvas: CanvasView) -> Annotation? {
        guard let start,
            let geometry = ShapeFactory.geometry(
                for: kind, from: start, to: input.point, constrain: input.shift, curved: input.option,
                cornerRadius: kind == .rectangle ? 6 : 0)
        else { return nil }
        return Annotation(geometry: geometry, style: canvas.toolState.style(for: kind))
    }
}

/// Click to drop the next numbered badge.
@MainActor
final class BadgeTool: CanvasTool {
    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: PointerInput, in canvas: CanvasView) {
        let state = canvas.toolState
        canvas.commit(
            Annotation(
                geometry: .badge(
                    center: input.point, number: canvas.document.nextBadgeNumber, format: .decimal,
                    radius: state.badgeRadius),
                style: Style(color: state.color, width: state.width)))
    }

    func mouseDragged(_ input: PointerInput, in canvas: CanvasView) {}
    func mouseUp(_ input: PointerInput, in canvas: CanvasView) {}
    func cancel(in canvas: CanvasView) {}
}

/// Drag over annotations to erase them whole; one undo step per drag.
@MainActor
final class EraserTool: CanvasTool {
    private var erasing: Set<UUID> = []

    var cursor: NSCursor { .crosshair }

    private func radius(in canvas: CanvasView) -> CGFloat {
        CGFloat(max(10, canvas.toolState.width * 2))
    }

    func mouseDown(_ input: PointerInput, in canvas: CanvasView) {
        erasing = []
        mouseDragged(input, in: canvas)
    }

    func mouseDragged(_ input: PointerInput, in canvas: CanvasView) {
        let radius = radius(in: canvas)
        canvas.overlayView.showEraser(at: input.point, radius: radius)
        for annotation in canvas.document.annotations where annotation.hitTest(input.point, tolerance: radius) {
            erasing.insert(annotation.id)
        }
        canvas.annotationsView.hiddenIDs = erasing
    }

    func mouseUp(_ input: PointerInput, in canvas: CanvasView) {
        let ids = erasing
        cancel(in: canvas)
        canvas.document.remove(ids: ids)
    }

    func cancel(in canvas: CanvasView) {
        erasing = []
        canvas.annotationsView.hiddenIDs = []
        canvas.overlayView.showEraser(at: nil, radius: 0)
    }
}

/// Click to select (Shift adds), drag to move, drag on empty space for a marquee.
/// Double-click a text annotation to edit it.
@MainActor
final class SelectTool: CanvasTool {
    private enum Gesture {
        case moving(start: CGPoint)
        case marquee(start: CGPoint, initial: Set<UUID>)
    }

    private var gesture: Gesture?

    var cursor: NSCursor { .arrow }

    func mouseDown(_ input: PointerInput, in canvas: CanvasView) {
        let hit = canvas.document.annotations.last { $0.hitTest(input.point) }
        guard let hit else {
            let initial = input.shift ? canvas.selection : []
            canvas.selection = initial
            gesture = .marquee(start: input.point, initial: initial)
            return
        }
        if input.clickCount == 2, hit.kind == .text {
            canvas.beginTextEditing(editing: hit)
            return
        }
        if input.shift {
            canvas.selection.formSymmetricDifference([hit.id])
        } else if !canvas.selection.contains(hit.id) {
            canvas.selection = [hit.id]
        }
        gesture = .moving(start: input.point)
    }

    func mouseDragged(_ input: PointerInput, in canvas: CanvasView) {
        switch gesture {
        case let .moving(start):
            canvas.setDragOffset(CGVector(dx: input.point.x - start.x, dy: input.point.y - start.y))
        case let .marquee(start, initial):
            let rect = CGRect(
                x: min(start.x, input.point.x), y: min(start.y, input.point.y),
                width: abs(input.point.x - start.x), height: abs(input.point.y - start.y))
            canvas.overlayView.showMarquee(rect)
            let inside = canvas.document.annotations.filter { $0.bounds.intersects(rect) }.map(\.id)
            canvas.selection = initial.union(inside)
        case nil:
            break
        }
    }

    func mouseUp(_ input: PointerInput, in canvas: CanvasView) {
        if case let .moving(start) = gesture {
            let offset = CGVector(dx: input.point.x - start.x, dy: input.point.y - start.y)
            canvas.setDragOffset(nil)
            if offset.dx != 0 || offset.dy != 0 {
                canvas.document.update(ids: canvas.selection, actionName: "Move") {
                    $0.geometry = $0.geometry.translated(by: offset)
                }
            }
        }
        cancel(in: canvas)
    }

    func cancel(in canvas: CanvasView) {
        gesture = nil
        canvas.setDragOffset(nil)
        canvas.overlayView.showMarquee(nil)
    }
}

/// Click to type; click an existing text annotation to edit it.
@MainActor
final class TextTool: CanvasTool {
    var cursor: NSCursor { .iBeam }

    func mouseDown(_ input: PointerInput, in canvas: CanvasView) {
        if canvas.isEditingText {
            canvas.endTextEditing()
            return
        }
        if let hit = canvas.document.annotations.last(where: { $0.kind == .text && $0.hitTest(input.point) }) {
            canvas.beginTextEditing(editing: hit)
        } else {
            // Put the click at the middle of the first line, where the caret appears.
            let fontSize = canvas.toolState.fontSize
            let origin = CGPoint(x: input.point.x, y: input.point.y - TextOutline.lineHeight(fontSize: fontSize) / 2)
            canvas.beginTextEditing(at: origin)
        }
    }

    func mouseDragged(_ input: PointerInput, in canvas: CanvasView) {}
    func mouseUp(_ input: PointerInput, in canvas: CanvasView) {}
    func cancel(in canvas: CanvasView) {}
}

@MainActor
func makeTool(_ kind: ToolKind) -> CanvasTool {
    switch kind {
    case .pen, .highlighter: FreehandTool(kind: kind)
    case .line, .arrow, .rectangle, .ellipse: ShapeTool(kind: kind)
    case .badge: BadgeTool()
    case .eraser: EraserTool()
    case .select: SelectTool()
    case .text: TextTool()
    }
}
