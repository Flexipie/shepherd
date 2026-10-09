import Carbon
import Observation
import ShepherdCore

/// The global "next" hotkey, through Carbon's `RegisterEventHotKey`: an Apple API that needs no
/// Accessibility or Input Monitoring permission. Re-registers when the config changes and reports
/// problems into the config's problem list. macOS accepts a combination a system shortcut already
/// owns without saying so, so only clashes within this app can be reported.
@MainActor
final class HotKeyCenter {
    private let config: ConfigStore
    private let onPress: () -> Void
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var registered: String??

    init(config: ConfigStore, onPress: @escaping () -> Void) {
        self.config = config
        self.onPress = onPress
        installHandler()
        update()
    }

    private func update() {
        let wanted = withObservationTracking {
            config.config.nextHotkey
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        guard registered != .some(wanted) else { return }
        registered = .some(wanted)
        unregister()
        config.report(register(wanted), for: "hotkey")
    }

    /// Registers `text`, or returns the problem.
    private func register(_ text: String?) -> String? {
        guard let text else { return nil }
        let key: HotKey
        do {
            key = try HotKey(parsing: text)
        } catch {
            return "config: hotkeys.next: \(error.message)"
        }
        var modifiers: UInt32 = 0
        if key.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if key.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if key.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if key.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(key.keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        switch status {
        case noErr: return nil
        case OSStatus(eventHotKeyExistsErr): return "config: hotkeys.next: \"\(text)\" is already in use"
        default: return "config: hotkeys.next: cannot register \"\(text)\" (error \(status))"
        }
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().onPress()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// "shep".
    private static let signature: OSType = 0x7368_6570
}
