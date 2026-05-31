import Cocoa

let src = CGEventSource(stateID: .hidSystemState)
let kd = CGEvent(keyboardEventSource: src, virtualKey: 160, keyDown: true)
print("Default flags: \(kd?.flags.rawValue ?? 0)")
