import Foundation
import ScreenInkCore

/// Current tool, color and width, shared by every screen and the palette. Persisted.
@MainActor
final class ToolState {
    var tool: ToolKind {
        didSet { changed() }
    }
    var colorIndex: Int {
        didSet { changed() }
    }
    var width: Double {
        didSet { changed() }
    }
    /// When set, each new annotation fades out and is removed after this many seconds.
    var autoFadeSeconds: Double? {
        didSet { changed() }
    }
    /// How much the screen behind the ink is darkened while drawing, as a fraction of black (0 = off).
    var dimLevel: Double {
        didSet { changed() }
    }
    var shortcuts = ShortcutMap.defaults

    private var observers: [() -> Void] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tool = defaults.string(forKey: Keys.tool).flatMap(ToolKind.init(rawValue:)) ?? .pen
        colorIndex = min(max(defaults.integer(forKey: Keys.color), 0), RGBA.palette.count - 1)
        let storedWidth = defaults.double(forKey: Keys.width)
        width = storedWidth > 0 ? storedWidth : 4
        let fade = defaults.double(forKey: Keys.autoFade)
        autoFadeSeconds = fade > 0 ? fade : nil
        dimLevel = min(max(defaults.double(forKey: Keys.dim), 0), 0.8)
    }

    var color: RGBA { RGBA.palette[colorIndex] }

    /// Text size follows the width so one control sizes everything.
    var fontSize: CGFloat { CGFloat(max(14, width * 5)) }

    var badgeRadius: CGFloat { CGFloat(max(13, width * 2.5 + 8)) }

    func style(for tool: ToolKind) -> Style {
        switch tool {
        case .highlighter:
            Style(color: color, width: width * 4, opacity: 0.4, blend: .multiply)
        default:
            Style(color: color, width: width)
        }
    }

    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    private func changed() {
        defaults.set(tool.rawValue, forKey: Keys.tool)
        defaults.set(colorIndex, forKey: Keys.color)
        defaults.set(width, forKey: Keys.width)
        defaults.set(autoFadeSeconds ?? 0, forKey: Keys.autoFade)
        defaults.set(dimLevel, forKey: Keys.dim)
        observers.forEach { $0() }
    }

    private enum Keys {
        static let tool = "Tool"
        static let color = "ColorIndex"
        static let width = "Width"
        static let autoFade = "AutoFadeSeconds"
        static let dim = "DimLevel"
    }
}
