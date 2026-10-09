/// A global key combination written like `ctrl+option+cmd+n`: modifiers (ctrl, option or opt or
/// alt, cmd or command, shift) and one key (a-z, 0-9, space, return, tab, f1-f12). Key codes are
/// the Mac's virtual key codes, so the app can register them without translating.
public struct HotKey: Sendable, Equatable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let command = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers
    public let description: String

    public init(parsing text: String) throws(ConfigProblem) {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var modifiers: Modifiers = []
        var key: (name: String, code: UInt32)?
        for part in parts {
            if let modifier = Self.modifierNames[part] {
                modifiers.insert(modifier)
            } else if let code = Self.keyCodes[part] {
                guard key == nil else { throw ConfigProblem("cannot parse \"\(text)\": more than one key") }
                key = (part, code)
            } else {
                throw ConfigProblem("cannot parse \"\(text)\": unknown key \"\(part)\"")
            }
        }
        guard let key else { throw ConfigProblem("cannot parse \"\(text)\": no key") }
        // Shift alone would take a capital letter from every app; F keys are fine bare.
        guard !modifiers.subtracting(.shift).isEmpty || key.name.hasPrefix("f") && key.name.count > 1 else {
            throw ConfigProblem("\"\(text)\" needs ctrl, option or cmd")
        }
        keyCode = key.code
        self.modifiers = modifiers
        description = text
    }

    static let modifierNames: [String: Modifiers] = [
        "ctrl": .control, "control": .control, "option": .option, "opt": .option, "alt": .option,
        "cmd": .command, "command": .command, "shift": .shift,
    ]

    static let keyCodes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08,
        "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F,
        "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D,
        "return": 0x24, "tab": 0x30, "space": 0x31,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    ]
}
