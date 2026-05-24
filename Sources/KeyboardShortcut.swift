import Cocoa
import CoreGraphics

/// User-defined key combination for `.customShortcut` gesture actions.
struct KeyboardShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var command: Bool = false
    var shift: Bool = false
    var control: Bool = false
    var option: Bool = false

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift   { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        if option  { flags.insert(.maskAlternate) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option  { parts.append("⌥") }
        if shift   { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(KeyCodeLabels.name(for: keyCode))
        return parts.joined()
    }

    var isValid: Bool { keyCode != 0 }

    init(keyCode: UInt16, command: Bool = false, shift: Bool = false,
         control: Bool = false, option: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.control = control
        self.option = option
    }

    init?(yamlKeyCode: Int?, modifiers: [String]?) {
        guard let yamlKeyCode, yamlKeyCode > 0 else { return nil }
        keyCode = UInt16(yamlKeyCode)
        command = false; shift = false; control = false; option = false
        for mod in modifiers ?? [] {
            switch mod.lowercased() {
            case "command", "cmd":  command = true
            case "shift":           shift = true
            case "control", "ctrl": control = true
            case "option", "alt":   option = true
            default: break
            }
        }
    }

    var yamlModifiers: [String] {
        var mods: [String] = []
        if command { mods.append("command") }
        if shift   { mods.append("shift") }
        if control { mods.append("control") }
        if option  { mods.append("option") }
        return mods
    }
}

enum KeyCodeLabels {
    static func name(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x24: return "Return"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x32: return "`"
        case 0x33: return "Delete"
        case 0x35: return "Esc"
        case 0x36, 0x37: return "⌘"
        case 0x38: return "⇧"
        case 0x39: return "Caps Lock"
        case 0x3A: return "⌥"
        case 0x3B: return "⌃"
        case 0x3C: return "Fn"
        case 0x3D: return "F17"
        case 0x3E: return "Volume Up"
        case 0x3F: return "Volume Down"
        case 0x40: return "Mute"
        case 0x41: return "F18"
        case 0x43: return "F19"
        case 0x45: return "F20"
        case 0x47: return "Clear"
        case 0x48: return "F5"
        case 0x49: return "F6"
        case 0x4A: return "F7"
        case 0x4B: return "F3"
        case 0x4C: return "F8"
        case 0x4D: return "F9"
        case 0x4E: return "F11"
        case 0x4F: return "F13"
        case 0x50: return "F16"
        case 0x51: return "F14"
        case 0x52: return "F10"
        case 0x53: return "F12"
        case 0x54: return "F15"
        case 0x55: return "Help"
        case 0x56: return "Home"
        case 0x57: return "Page Up"
        case 0x58: return "Forward Delete"
        case 0x59: return "F4"
        case 0x5A: return "End"
        case 0x5B: return "F2"
        case 0x5C: return "Page Down"
        case 0x5D: return "F1"
        case 0x5E: return "Left"
        case 0x5F: return "Right"
        case 0x60: return "Down"
        case 0x61: return "Up"
        default:   return "Key \(keyCode)"
        }
    }

    static let commonKeys: [(name: String, keyCode: UInt16)] = [
        ("Tab", 0x30), ("Space", 0x31), ("Return", 0x24), ("Esc", 0x35), ("Delete", 0x33),
        ("Left Arrow", 0x5E), ("Right Arrow", 0x5F), ("Down Arrow", 0x60), ("Up Arrow", 0x61),
        ("Option", 0x3A), ("Shift", 0x38), ("Command", 0x37), ("Control", 0x3B)
    ]

    static func keyCode(forToken token: String) -> UInt16? {
        switch token.lowercased().replacingOccurrences(of: "_", with: "") {
        case "tab": return 0x30
        case "space": return 0x31
        case "return", "enter": return 0x24
        case "esc", "escape": return 0x35
        case "delete", "backspace": return 0x33
        case "left", "leftarrow": return 0x5E
        case "right", "rightarrow": return 0x5F
        case "down", "downarrow": return 0x60
        case "up", "uparrow": return 0x61
        case "leftalt", "rightalt", "alt", "option", "leftoption": return 0x3A
        case "leftshift", "rightshift", "shift": return 0x38
        case "leftcmd", "cmd", "command", "leftcommand": return 0x37
        case "rightcmd", "rightcommand": return 0x36
        case "leftctrl", "rightctrl", "ctrl", "control", "leftcontrol", "rightcontrol": return 0x3B
        default:
            if token.lowercased().hasPrefix("key"),
               let value = UInt16(token.dropFirst(3)) {
                return value
            }
            return nil
        }
    }

    static func tokenName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x24: return "return"
        case 0x35: return "escape"
        case 0x33: return "delete"
        case 0x5E: return "left"
        case 0x5F: return "right"
        case 0x60: return "down"
        case 0x61: return "up"
        case 0x3A: return "leftalt"
        case 0x38: return "leftshift"
        case 0x37: return "leftcmd"
        case 0x36: return "rightcmd"
        case 0x3B: return "leftctrl"
        default: return "key\(keyCode)"
        }
    }
}

enum KeyboardInputEvent: String, Codable, CaseIterable {
    case tap = "tap"
    case hold = "hold"
    case release = "release"

    var label: String {
        switch self {
        case .tap: return "Tap"
        case .hold: return "Hold"
        case .release: return "Release"
        }
    }
}

struct KeyboardInputStep: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var event: KeyboardInputEvent = .tap
    var keyCode: UInt16 = 0x30
    var command: Bool = false
    var shift: Bool = false
    var control: Bool = false
    var option: Bool = false

    private enum CodingKeys: String, CodingKey {
        case event, keyCode, command, shift, control, option
    }

    var modifierFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        return flags
    }

    var displayString: String {
        let prefix: String
        switch event {
        case .tap: prefix = "Tap "
        case .hold: prefix = "Hold "
        case .release: prefix = "Release "
        }
        var mods: [String] = []
        if control { mods.append("⌃") }
        if option { mods.append("⌥") }
        if shift { mods.append("⇧") }
        if command { mods.append("⌘") }
        return prefix + mods.joined() + KeyCodeLabels.name(for: keyCode)
    }

    init(event: KeyboardInputEvent = .tap, keyCode: UInt16 = 0x30,
         command: Bool = false, shift: Bool = false, control: Bool = false, option: Bool = false) {
        self.event = event
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.control = control
        self.option = option
    }

    init?(token: String) {
        var raw = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }

        if raw.hasPrefix("+") {
            event = .hold
            raw.removeFirst()
        } else if raw.hasPrefix("-") {
            event = .release
            raw.removeFirst()
        } else {
            event = .tap
        }

        var command = false, shift = false, control = false, option = false
        let parts = raw.components(separatedBy: "+").filter { !$0.isEmpty }
        guard let keyToken = parts.last, let keyCode = KeyCodeLabels.keyCode(forToken: keyToken) else { return nil }
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command", "leftcmd": command = true
            case "shift", "leftshift": shift = true
            case "ctrl", "control", "leftctrl": control = true
            case "alt", "option", "leftalt": option = true
            default: break
            }
        }
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.control = control
        self.option = option
    }

    var token: String {
        let key = KeyCodeLabels.tokenName(for: keyCode)
        switch event {
        case .hold:
            return "+\(key)"
        case .release:
            return "-\(key)"
        case .tap:
            var parts: [String] = []
            if command { parts.append("leftcmd") }
            if shift { parts.append("leftshift") }
            if control { parts.append("leftctrl") }
            if option { parts.append("leftalt") }
            parts.append(key)
            return parts.joined(separator: "+")
        }
    }
}
