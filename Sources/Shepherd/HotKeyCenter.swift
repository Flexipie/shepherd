import Carbon
import Observation
import ShepherdCore

/// The global hotkeys ("next" and "palette"), through Carbon's `RegisterEventHotKey`: an Apple
/// API that needs no Accessibility or Input Monitoring permission. Re-registers when the config
/// changes and reports problems into the config's problem list as `hotkeys.<name>`. macOS accepts
/// a combination a system shortcut already owns without saying so, so only clashes within this
/// app can be reported.
@MainActor
final class HotKeyCenter {
    /// A hotkey's name in config, its value there, and what pressing it does.
    struct Binding {
        let name: String
        let combo: KeyPath<ShepherdConfig, String?>
        let onPress: () -> Void
    }

    private let config: ConfigStore
    private let bindings: [Binding]
    private var handler: EventHandlerRef?
    private var hotKeys: [String: EventHotKeyRef] = [:]
    private var registered: [String?]?

    init(config: ConfigStore, bindings: [Binding]) {
        self.config = config
        self.bindings = bindings
        installHandler()
        update()
    }

    private func update() {
        let wanted = withObservationTracking {
            bindings.map { config.config[keyPath: $0.combo] }
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        guard registered != wanted else { return }
        registered = wanted
        unregisterAll()
        var taken: [String: String] = [:]
        for (index, binding) in bindings.enumerated() {
            config.report(register(binding.name, wanted[index], id: UInt32(index + 1), taken: &taken), for: "hotkeys.\(binding.name)")
        }
    }

    /// Registers `text` for `name`, or returns the problem.
    private func register(_ name: String, _ text: String?, id: UInt32, taken: inout [String: String]) -> String? {
        guard let text else { return nil }
        let key: HotKey
        do {
            key = try HotKey(parsing: text)
        } catch {
            return "config: hotkeys.\(name): \(error.message)"
        }
        // The same key and modifiers, however they were written.
        let combo = "\(key.keyCode)/\(key.modifiers.rawValue)"
        if let other = taken[combo] { return "config: hotkeys.\(name): \"\(text)\" is already hotkeys.\(other)" }
        var modifiers: UInt32 = 0
        if key.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if key.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if key.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if key.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(key.keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr:
            hotKeys[name] = ref
            taken[combo] = name
            return nil
        case OSStatus(eventHotKeyExistsErr): return "config: hotkeys.\(name): \"\(text)\" is already in use"
        default: return "config: hotkeys.\(name): cannot register \"\(text)\" (error \(status))"
        }
    }

    /// Lets go of every hotkey, so another Shepherd can take them.
    func suspend() {
        unregisterAll()
        registered = nil
    }

    /// Takes the hotkeys again after `suspend()`.
    func resume() {
        update()
    }

    private func unregisterAll() {
        for ref in hotKeys.values { UnregisterEventHotKey(ref) }
        hotKeys.removeAll()
    }

    private func pressed(_ id: UInt32) {
        let index = Int(id) - 1
        guard bindings.indices.contains(index) else { return }
        bindings[index].onPress()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else { return noErr }
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().pressed(hotKeyID.id)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// "shep".
    nonisolated private static let signature: OSType = 0x7368_6570
}
