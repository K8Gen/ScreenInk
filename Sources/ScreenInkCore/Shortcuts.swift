/// What a single-key shortcut does while drawing is active.
public enum ShortcutAction: Codable, Hashable, Sendable {
    case tool(ToolKind)
    /// Index into `RGBA.palette`.
    case color(Int)
    case thinner
    case thicker
    case clear
}

/// Single-key bindings, keyed by the lowercased character typed without modifiers.
/// Stored as data so a Settings pane can rebind them (PLAN.md §5).
public struct ShortcutMap: Codable, Hashable, Sendable {
    public var bindings: [String: ShortcutAction]

    public init(bindings: [String: ShortcutAction]) {
        self.bindings = bindings
    }

    public func action(for characters: String) -> ShortcutAction? {
        bindings[characters.lowercased()]
    }

    public func key(for action: ShortcutAction) -> String? {
        bindings.first { $0.value == action }?.key
    }

    public static let defaults = ShortcutMap(bindings: {
        var map: [String: ShortcutAction] = [
            "p": .tool(.pen), "h": .tool(.highlighter), "l": .tool(.line), "a": .tool(.arrow),
            "r": .tool(.rectangle), "o": .tool(.ellipse), "t": .tool(.text), "n": .tool(.badge),
            "e": .tool(.eraser), "v": .tool(.select),
            "[": .thinner, "]": .thicker, "c": .clear,
        ]
        for index in 0..<9 { map[String(index + 1)] = .color(index) }
        return map
    }())
}

/// Width presets that `[` and `]` step through.
public enum WidthSteps {
    public static let all: [Double] = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32]

    public static func next(after width: Double, thicker: Bool) -> Double {
        if thicker {
            return all.first { $0 > width } ?? all.last!
        }
        return all.last { $0 < width } ?? all.first!
    }
}
