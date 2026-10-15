import AppKit
import ServiceManagement

/// The menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let screens: ScreensController
    private let toolState: ToolState
    private let hotKeyDescription: String?
    private static let fadeChoices: [Double?] = [nil, 3, 5, 10, 30]
    private static let dimChoices: [(title: String, level: Double)] = [
        ("Off", 0), ("Slightly", 0.2), ("Medium", 0.35), ("Strongly", 0.5),
    ]

    init(screens: ScreensController, toolState: ToolState, hotKeyDescription: String?) {
        self.screens = screens
        self.toolState = toolState
        self.hotKeyDescription = hotKeyDescription
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon(active: false)
    }

    func updateIcon(active: Bool) {
        let name = active ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "ScreenInk")
    }

    // Rebuilt on every open so titles and checkmarks are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var drawTitle = screens.isActive ? "Stop Drawing" : "Draw on Screen"
        if let hotKeyDescription { drawTitle += "  \(hotKeyDescription)" }
        menu.addItem(item(drawTitle, #selector(toggleDrawing)))
        let clear = item("Clear All", #selector(clearAll))
        clear.isEnabled = screens.hasAnnotations
        menu.addItem(clear)

        let fade = NSMenuItem(title: "Auto-Fade Drawings", action: nil, keyEquivalent: "")
        let fadeMenu = NSMenu()
        for (index, seconds) in Self.fadeChoices.enumerated() {
            let choice = item(seconds.map { "After \(Int($0)) Seconds" } ?? "Off", #selector(chooseFade(_:)))
            choice.tag = index
            choice.state = seconds == toolState.autoFadeSeconds ? .on : .off
            fadeMenu.addItem(choice)
        }
        fade.submenu = fadeMenu
        menu.addItem(fade)

        let dim = NSMenuItem(title: "Dim Screen While Drawing", action: nil, keyEquivalent: "")
        let dimMenu = NSMenu()
        for (index, choice) in Self.dimChoices.enumerated() {
            let item = item(choice.title, #selector(chooseDim(_:)))
            item.tag = index
            item.state = choice.level == toolState.dimLevel ? .on : .off
            dimMenu.addItem(item)
        }
        dim.submenu = dimMenu
        menu.addItem(dim)

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quit ScreenInk", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleDrawing() {
        screens.toggle()
    }

    @objc private func clearAll() {
        screens.clearAll()
    }

    @objc private func chooseFade(_ sender: NSMenuItem) {
        toolState.autoFadeSeconds = Self.fadeChoices[sender.tag]
    }

    @objc private func chooseDim(_ sender: NSMenuItem) {
        toolState.dimLevel = Self.dimChoices[sender.tag].level
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText =
                "\(error.localizedDescription)\n\nLaunch at Login needs the app to be signed and run from /Applications."
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
