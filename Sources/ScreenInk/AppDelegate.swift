import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screens: ScreensController?
    private var statusItem: StatusItemController?
    private var activateHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let toolState = ToolState()
        let screens = ScreensController(toolState: toolState)
        self.screens = screens

        let combo = HotKey.Combo.defaultActivate
        activateHotKey = HotKey(combo) { [weak screens] in screens?.toggle() }

        let statusItem = StatusItemController(
            screens: screens, toolState: toolState, hotKeyDescription: activateHotKey == nil ? nil : combo.displayString)
        self.statusItem = statusItem
        screens.onActiveChange = { [weak statusItem] active in statusItem?.updateIcon(active: active) }

        if activateHotKey == nil {
            let alert = NSAlert()
            alert.messageText = "Shortcut \(combo.displayString) is already in use"
            alert.informativeText = "Another app has claimed it. Use the menu-bar icon to start drawing."
            alert.runModal()
        }
    }
}
