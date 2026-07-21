import Cocoa
import Carbon.HIToolbox

enum HotkeyTrigger {
    static func carbonModifiers(command: Bool, shift: Bool, control: Bool, option: Bool) -> UInt32 {
        var mods: UInt32 = 0
        if command { mods |= UInt32(cmdKey) }
        if shift   { mods |= UInt32(shiftKey) }
        if control { mods |= UInt32(controlKey) }
        if option  { mods |= UInt32(optionKey) }
        return mods
    }

    static func isRegisterable(keyCode: Int, command: Bool, shift: Bool, control: Bool, option: Bool) -> Bool {
        guard keyCode >= 0 else { return false }
        return command || shift || control || option
    }
}
