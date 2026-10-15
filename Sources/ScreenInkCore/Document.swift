import Foundation

/// The annotations on one screen. Array order is z-order (last is on top).
///
/// Every mutation records the previous array with the undo manager, so undo/redo always
/// restores an exact earlier state. Arrays of value types make this cheap (copy-on-write).
@MainActor
public final class Document {
    public private(set) var annotations: [Annotation] = []
    public let undoManager: UndoManager
    /// Called after every change, including undo and redo.
    public var onChange: (() -> Void)?

    public init(undoManager: UndoManager = UndoManager()) {
        self.undoManager = undoManager
        undoManager.groupsByEvent = false
    }

    public func insert(_ annotation: Annotation) {
        replace(with: annotations + [annotation], actionName: "Draw")
    }

    public func remove(ids: Set<UUID>) {
        let remaining = annotations.filter { !ids.contains($0.id) }
        guard remaining.count != annotations.count else { return }
        replace(with: remaining, actionName: "Delete")
    }

    /// Applies `change` to each annotation in `ids` as one undoable step.
    public func update(ids: Set<UUID>, actionName: String, _ change: (inout Annotation) -> Void) {
        guard !ids.isEmpty else { return }
        var updated = annotations
        for index in updated.indices where ids.contains(updated[index].id) {
            change(&updated[index])
        }
        guard updated != annotations else { return }
        replace(with: updated, actionName: actionName)
    }

    /// Moves `ids` to the top of the z-order, keeping their relative order.
    public func bringToFront(ids: Set<UUID>) {
        let front = annotations.filter { ids.contains($0.id) }
        let rest = annotations.filter { !ids.contains($0.id) }
        guard rest + front != annotations else { return }
        replace(with: rest + front, actionName: "Bring to Front")
    }

    /// One more than the highest badge number on this screen, so undo naturally "gives back" a number.
    public var nextBadgeNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case let .badge(_, number, _, _) = annotation.geometry { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    public func removeAll() {
        guard !annotations.isEmpty else { return }
        replace(with: [], actionName: "Clear")
    }

    public func undo() {
        if undoManager.canUndo { undoManager.undo() }
    }

    public func redo() {
        if undoManager.canRedo { undoManager.redo() }
    }

    private func replace(with newAnnotations: [Annotation], actionName: String) {
        let previous = annotations
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.replace(with: previous, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        annotations = newAnnotations
        onChange?()
    }
}
