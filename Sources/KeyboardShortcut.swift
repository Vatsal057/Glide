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

private enum KeyCodeLabels {
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
        case 0x37: return "⌘"
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
}
