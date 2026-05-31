import Cocoa
import CoreGraphics

func sendKey(_ key: CGKeyCode, _ flags: CGEventFlags) {
    let src = CGEventSource(stateID: .hidSystemState)
    guard let kd = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
          let ku = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
    kd.flags = flags; kd.post(tap: .cghidEventTap)
    ku.flags = flags; ku.post(tap: .cghidEventTap)
    print("Sent key \(key)")
}

// Send Mission Control F3 (160)
sendKey(160, [])
