import AppKit

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--self-test") {
    let directory = flag + 1 < arguments.count ? arguments[flag + 1] : NSTemporaryDirectory() + "ScreenInkSelfTest"
    _ = NSApplication.shared
    exit(SelfTest.run(outputDirectory: URL(fileURLWithPath: directory)) ? 0 : 1)
}

if let flag = arguments.firstIndex(of: "--screenshots"), flag + 1 < arguments.count {
    _ = NSApplication.shared
    exit(Screenshots.run(outputDirectory: URL(fileURLWithPath: arguments[flag + 1])) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, no main menu (LSUIElement in the bundle does the same).
app.setActivationPolicy(.accessory)
app.run()
