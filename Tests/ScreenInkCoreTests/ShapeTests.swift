import CoreGraphics
import Foundation
import Testing
@testable import ScreenInkCore

@Suite struct ShapeFactoryTests {
    @Test func shiftSnapsLinesTo45Degrees() {
        let start = CGPoint(x: 0, y: 0)
        #expect(ShapeFactory.snapAngle(from: start, to: CGPoint(x: 100, y: 8)) == CGPoint(x: (100.0 * 100.0 + 8.0 * 8.0).squareRoot(), y: 0))
        let diagonal = ShapeFactory.snapAngle(from: start, to: CGPoint(x: 50, y: 60))
        #expect(abs(diagonal.x - diagonal.y) < 1e-6)
    }

    @Test func shiftMakesSquaresTowardTheDrag() {
        let geometry = ShapeFactory.geometry(
            for: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 130), constrain: true)
        #expect(geometry == .rectangle(CGRect(x: 40, y: 100, width: 60, height: 60), cornerRadius: 0))
    }

    @Test func tinyDragsMakeNothing() {
        #expect(ShapeFactory.geometry(for: .line, from: .zero, to: CGPoint(x: 1, y: 1), constrain: false) == nil)
        #expect(ShapeFactory.geometry(for: .ellipse, from: .zero, to: CGPoint(x: 2, y: 2), constrain: false) == nil)
        #expect(ShapeFactory.geometry(for: .pen, from: .zero, to: CGPoint(x: 50, y: 50), constrain: false) == nil)
    }

    @Test func curvedArrowHasAControlPoint() {
        let geometry = ShapeFactory.geometry(
            for: .arrow, from: .zero, to: CGPoint(x: 100, y: 0), constrain: false, curved: true)
        guard case let .arrow(_, _, control) = geometry else {
            Issue.record("expected an arrow")
            return
        }
        #expect(control == CGPoint(x: 50, y: -25))
    }
}

@Suite struct RenderingTests {
    private func annotation(_ geometry: Geometry, width: Double = 4) -> Annotation {
        Annotation(geometry: geometry, style: Style(color: .red, width: width))
    }

    @Test func rectangleOutlineIsHollow() {
        let a = annotation(.rectangle(CGRect(x: 0, y: 0, width: 100, height: 60), cornerRadius: 0))
        #expect(a.hitTest(CGPoint(x: 0, y: 30), tolerance: 0))
        #expect(!a.hitTest(CGPoint(x: 50, y: 30), tolerance: 4))
        #expect(a.bounds == CGRect(x: -2, y: -2, width: 104, height: 64))
    }

    @Test func arrowHeadPointsAtTheTip() {
        let a = annotation(.arrow(from: .zero, to: CGPoint(x: 200, y: 0), control: nil))
        #expect(a.renderParts.count == 2)
        #expect(a.hitTest(CGPoint(x: 199, y: 0), tolerance: 0))
        #expect(a.bounds.maxX <= 200.001)
    }

    @Test func shortArrowIsJustAHead() {
        let a = annotation(.arrow(from: .zero, to: CGPoint(x: 5, y: 0), control: nil))
        #expect(a.renderParts.count == 1)
    }

    @Test func textBoxStartsAtOrigin() {
        let a = annotation(.text(origin: CGPoint(x: 10, y: 20), string: "Hello\nWorld", fontSize: 20))
        let box = a.bounds
        #expect(box.minX >= 10 && box.minX < 14)
        #expect(box.minY >= 20 && box.minY < 30)
        // Two lines: taller than one line height.
        #expect(box.height > TextOutline.lineHeight(fontSize: 20))
        #expect(a.hitTest(CGPoint(x: box.midX, y: box.midY)))
    }

    @Test func badgeNumberIsCenteredInContrastColor() {
        let a = annotation(.badge(center: CGPoint(x: 50, y: 50), number: 7, format: .decimal, radius: 16))
        let parts = a.renderParts
        #expect(parts.map(\.fill) == [.style, .contrast])
        let glyphs = parts[1].path.boundingBoxOfPath
        #expect(abs(glyphs.midX - 50) < 0.01 && abs(glyphs.midY - 50) < 0.01)
        #expect(RGBA.yellow.contrasting == .black)
        #expect(RGBA.blue.contrasting == .white)
    }

    @Test func translationMovesEveryKind() {
        let geometries: [Geometry] = [
            .stroke(points: [.zero, CGPoint(x: 10, y: 10)], widths: [2, 2]),
            .line(from: .zero, to: CGPoint(x: 10, y: 0)),
            .arrow(from: .zero, to: CGPoint(x: 50, y: 0), control: CGPoint(x: 25, y: 10)),
            .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 2),
            .ellipse(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .text(origin: .zero, string: "Hi", fontSize: 14),
            .badge(center: .zero, number: 1, format: .decimal, radius: 10),
        ]
        for geometry in geometries {
            let before = annotation(geometry).bounds
            let after = annotation(geometry.translated(by: CGVector(dx: 30, dy: -5))).bounds
            #expect(abs(after.minX - before.minX - 30) < 0.01, "\(geometry.kind)")
            #expect(abs(after.minY - before.minY + 5) < 0.01, "\(geometry.kind)")
        }
    }
}

@Suite struct BadgeFormatTests {
    @Test(arguments: [(1, "A"), (26, "Z"), (27, "AA"), (52, "AZ"), (53, "BA")])
    func alphabet(number: Int, expected: String) {
        #expect(BadgeFormat.alphabet.label(for: number) == expected)
    }

    @Test(arguments: [(1, "I"), (4, "IV"), (9, "IX"), (14, "XIV"), (40, "XL"), (1994, "MCMXCIV")])
    func roman(number: Int, expected: String) {
        #expect(BadgeFormat.roman.label(for: number) == expected)
    }
}

@Suite struct ShortcutTests {
    @Test func defaultKeysAreUniqueAndCoverEveryTool() {
        let map = ShortcutMap.defaults
        for tool in ToolKind.allCases {
            #expect(map.key(for: .tool(tool)) != nil, "\(tool) has no key")
        }
        #expect(map.action(for: "P") == .tool(.pen))
        #expect(map.action(for: "9") == .color(8))
        #expect(Set(map.bindings.values).count == map.bindings.count)
    }

    @Test func widthStepsClampAtEnds() {
        #expect(WidthSteps.next(after: 4, thicker: true) == 6)
        #expect(WidthSteps.next(after: 5, thicker: false) == 4)
        #expect(WidthSteps.next(after: 32, thicker: true) == 32)
        #expect(WidthSteps.next(after: 1, thicker: false) == 1)
    }
}

@MainActor
@Suite struct DocumentOperationTests {
    private func badge(_ number: Int) -> Annotation {
        Annotation(geometry: .badge(center: .zero, number: number, format: .decimal, radius: 10), style: .defaultPen)
    }

    @Test func badgeNumbersFollowTheHighestAndUndoGivesThemBack() {
        let document = Document()
        #expect(document.nextBadgeNumber == 1)
        document.insert(badge(document.nextBadgeNumber))
        document.insert(badge(document.nextBadgeNumber))
        #expect(document.nextBadgeNumber == 3)
        document.undo()
        #expect(document.nextBadgeNumber == 2)
    }

    @Test func updateIsOneUndoStep() {
        let document = Document()
        let a = badge(1)
        let b = badge(2)
        document.insert(a)
        document.insert(b)
        document.update(ids: [a.id, b.id], actionName: "Move") {
            $0.geometry = $0.geometry.translated(by: CGVector(dx: 5, dy: 5))
        }
        #expect(document.annotations.allSatisfy { $0.bounds.midX == 5 })
        document.undo()
        #expect(document.annotations == [a, b])
    }

    @Test func bringToFrontKeepsRelativeOrder() {
        let document = Document()
        let items = (1...4).map(badge)
        items.forEach(document.insert)
        document.bringToFront(ids: [items[0].id, items[2].id])
        #expect(document.annotations.map(\.id) == [items[1], items[3], items[0], items[2]].map(\.id))
    }
}
