import Carbon
import Foundation

/// A way to type a character on a keyboard layout: one key, with Shift, Option or both, or a dead key and then a key,
/// as é is typed on a U.S. keyboard (⌥E, then E).
public struct Keystroke: Hashable, Sendable, CustomStringConvertible {
    public struct Key: Hashable, Sendable, CustomStringConvertible {
        public var code: UInt16
        public var shift: Bool
        public var option: Bool
        /// What's printed on the key: what it types without a modifier, in capitals when Shift types those ("E", "Ü"),
        /// else as it is ("´", "é" on a French keyboard, whose Shift types 2), or its name ("Space").
        public var cap: String

        /// "⌥⇧E", as menus write shortcuts: Option before Shift.
        public var description: String { (option ? "⌥" : "") + (shift ? "⇧" : "") + cap }
    }

    public var keys: [Key]

    /// "⌥⇧K", or "⌥E, then E" when a dead key comes first.
    public var description: String { keys.map(\.description).joined(separator: ", then ") }
}

/// The characters a keyboard layout types, each with the easiest keystroke for it: one key before a dead key and the
/// key after it, and fewer modifiers before more. Worked out with UCKeyTranslate from the layout's data, once per layout.
public struct KeyboardLayout: Sendable {
    /// The input source's ID, "com.apple.keylayout.US".
    public let id: String
    /// Its name, "U.S." or "German".
    public let name: String
    private let keyboardType: UInt32
    private let keystrokes: [String: Keystroke]

    /// The keystroke that types a character, if the layout has one.
    public func keystroke(for scalar: UInt32) -> Keystroke? {
        Unicode.Scalar(scalar).flatMap { keystrokes[String(Character($0))] }
    }

    @MainActor private static var cache: KeyboardLayout?

    /// The keyboard layout in use (with an input method, like Japanese, the one it types Latin letters with), worked
    /// out again when the user switches to another. Text Input Sources wants the main thread.
    @MainActor public static func current() -> KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        let type = UInt32(LMGetKbdType())
        if let cache, cache.id == string(source, kTISPropertyInputSourceID), cache.keyboardType == type { return cache }
        cache = KeyboardLayout(source: source, keyboardType: type)
        return cache
    }

    /// An installed layout by its ID, whether in use or not: "com.apple.keylayout.German".
    @MainActor public static func installed(_ id: String) -> KeyboardLayout? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first
        else { return nil }
        return KeyboardLayout(source: source, keyboardType: UInt32(LMGetKbdType()))
    }

    @MainActor private init?(source: TISInputSource, keyboardType: UInt32) {
        guard let id = Self.string(source, kTISPropertyInputSourceID),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        self.id = id
        name = Self.string(source, kTISPropertyLocalizedName) ?? id
        self.keyboardType = keyboardType
        keystrokes = Self.keystrokes(layout: data, keyboardType: keyboardType)
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// The keys characters are looked for on, in the order they're tried. The keypad's keys come to nothing, as the
    /// keys above the letters type their digits too; ISO's key beside the left Shift and the JIS keys, which not every
    /// keyboard has, come last.
    private static let keyCodes: [[UInt16]] = {
        let keypad: Set<UInt16> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
        let extra: [UInt16] = [10, 93, 94, 95]
        return [(0..<128).filter { !keypad.contains($0) && !extra.contains($0) }, extra]
    }()

    /// None, Shift, Option, then both: the modifiers characters are looked for with, in the order they're tried.
    private static let modifiers: [(shift: Bool, option: Bool)] = [(false, false), (true, false), (false, true), (true, true)]

    private static func keystrokes(layout data: Data, keyboardType: UInt32) -> [String: Keystroke] {
        data.withUnsafeBytes { raw -> [String: Keystroke] in
            guard let base = raw.baseAddress else { return [:] }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            // What a key types, and the dead key state it leaves: nothing and a state that isn't 0 for a dead key. The
            // modifiers go in as the Carbon flags shifted down a byte.
            func translate(_ code: UInt16, shift: Bool, option: Bool, state: UInt32 = 0, deadKeys: Bool = true) -> (text: String, state: UInt32) {
                var state = state
                var length = 0
                var units = [UniChar](repeating: 0, count: 8)
                let flags = UInt32(((shift ? shiftKey : 0) | (option ? optionKey : 0)) >> 8) & 0xFF
                let options = deadKeys ? 0 : OptionBits(kUCKeyTranslateNoDeadKeysMask)
                guard UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), flags, keyboardType, options,
                                     &state, units.count, &length, &units) == noErr
                else { return ("", 0) }
                return (String(utf16CodeUnits: units, count: length), state)
            }
            var caps: [UInt16: String] = [:]
            for code in keyCodes.joined() {
                let plain = translate(code, shift: false, option: false, deadKeys: false).text
                guard Self.isTyped(plain) else { continue }
                let shifted = translate(code, shift: true, option: false, deadKeys: false).text
                caps[code] = plain == " " ? "Space" : shifted == plain.uppercased() ? plain.uppercased() : plain
            }
            var found: [String: Keystroke] = [:]
            var deadKeys: [(key: Keystroke.Key, state: UInt32)] = []
            // One key, before any dead key and the key after it.
            for codes in keyCodes {
                for (shift, option) in modifiers {
                    for code in codes {
                        guard let cap = caps[code] else { continue }
                        let key = Keystroke.Key(code: code, shift: shift, option: option, cap: cap)
                        let (text, state) = translate(code, shift: shift, option: option)
                        if text.isEmpty, state != 0 {
                            deadKeys.append((key, state))
                        } else if Self.isTyped(text), found[text] == nil {
                            found[text] = Keystroke(keys: [key])
                        }
                    }
                }
            }
            for dead in deadKeys {
                for codes in keyCodes {
                    for (shift, option) in modifiers {
                        for code in codes {
                            guard let cap = caps[code] else { continue }
                            // The state isn't always 0 again after the key that finishes it, but there's a character.
                            let text = translate(code, shift: shift, option: option, state: dead.state).text
                            guard Self.isTyped(text), found[text] == nil else { continue }
                            found[text] = Keystroke(keys: [dead.key, Keystroke.Key(code: code, shift: shift, option: option, cap: cap)])
                        }
                    }
                }
            }
            return found
        }
    }

    /// One character that shows, or a space: not a control character, like those Return, Tab, the arrow keys and the
    /// function keys type, nor two characters, as a dead key and a key it doesn't go with type.
    private static func isTyped(_ text: String) -> Bool {
        guard text.count == 1 else { return false }
        return !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}
