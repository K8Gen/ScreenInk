import CoreGraphics
import Foundation
import Testing
@testable import ScreenInkCore

@MainActor
@Suite struct DocumentTests {
    private func stroke(_ x: Double) -> Annotation {
        Annotation(
            geometry: .stroke(points: [CGPoint(x: x, y: 0), CGPoint(x: x + 10, y: 5)], widths: [2, 3]),
            style: .defaultPen)
    }

    @Test func insertUndoRedo() {
        let document = Document()
        let a = stroke(0)
        let b = stroke(20)
        document.insert(a)
        document.insert(b)
        #expect(document.annotations == [a, b])
        document.undo()
        #expect(document.annotations == [a])
        document.undo()
        #expect(document.annotations.isEmpty)
        document.redo()
        document.redo()
        #expect(document.annotations == [a, b])
    }

    @Test func clearIsUndoable() {
        let document = Document()
        let a = stroke(0)
        document.insert(a)
        document.removeAll()
        #expect(document.annotations.isEmpty)
        document.undo()
        #expect(document.annotations == [a])
    }

    @Test func removeKeepsOrderOfTheRest() {
        let document = Document()
        let items = (0..<4).map { stroke(Double($0) * 10) }
        items.forEach(document.insert)
        document.remove(ids: [items[1].id])
        #expect(document.annotations == [items[0], items[2], items[3]])
        document.undo()
        #expect(document.annotations == items)
    }

    @Test func notifiesOnEveryChange() {
        let document = Document()
        var changes = 0
        document.onChange = { changes += 1 }
        document.insert(stroke(0))
        document.undo()
        document.redo()
        #expect(changes == 3)
    }

    /// Property test from PLAN.md §8: apply N random operations, undo N, end at the start.
    @Test(arguments: 0..<20)
    func randomOperationsUndoToStart(seed: Int) {
        var rng = SeededGenerator(seed: UInt64(seed))
        let document = Document()
        var history: [[Annotation]] = [document.annotations]
        for step in 0..<25 {
            switch Int.random(in: 0..<5, using: &rng) {
            case 0 where !document.annotations.isEmpty:
                document.removeAll()
            case 1 where !document.annotations.isEmpty:
                document.remove(ids: [document.annotations.randomElement(using: &rng)!.id])
            default:
                document.insert(stroke(Double(step)))
            }
            history.append(document.annotations)
        }
        for expected in history.dropLast().reversed() {
            document.undo()
            #expect(document.annotations == expected)
        }
        #expect(!document.undoManager.canUndo)
    }

    @Test func annotationRoundTripsThroughJSON() throws {
        let original = stroke(3)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Annotation.self, from: data) == original)
    }
}

/// Deterministic SplitMix64 so property tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
