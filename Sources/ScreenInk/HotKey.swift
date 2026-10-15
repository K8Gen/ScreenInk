import Carbon.HIToolbox

/// A system-wide hotkey via Carbon `RegisterEventHotKey`. Needs no permission (PLAN.md §2).
@MainActor
final class HotKey {
    struct Combo: Equatable {
        var keyCode: UInt32
        /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
        var modifiers: UInt32

        static let defaultActivate = Combo(
            keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | optionKey | controlKey))

        var displayString: String {
            var result = ""
            if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
            return result + (Self.keyNames[keyCode] ?? "?")
        }

        private static let keyNames: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_S): "S",
        ]
    }

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var dispatcherInstalled = false
    private static let signature: OSType = 0x5349_4E4B  // 'SINK'

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// Returns nil when another app already owns the combination.
    init?(_ combo: Combo, handler: @escaping () -> Void) {
        Self.installDispatcherIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        self.ref = ref
        Self.handlers[id] = handler
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.handlers[id] = nil
    }

    private static func installDispatcherIfNeeded() {
        guard !dispatcherInstalled else { return }
        dispatcherInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr, hotKeyID.signature == HotKey.signature else { return status }
                let id = hotKeyID.id
                // Carbon delivers hotkey events on the main thread's event loop.
                MainActor.assumeIsolated { HotKey.handlers[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
    }
}
