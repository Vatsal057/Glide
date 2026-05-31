import Cocoa
import CoreGraphics

final class KeyboardEmulator {
    static let shared = KeyboardEmulator()
    private init() {}

    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)
    private var syntheticHeldFlags: CGEventFlags = []

    func executeKeyboardSteps(_ steps: [KeyboardInputStep]) {
        guard !steps.isEmpty else { return }
        for step in steps {
            switch step.event {
            case .hold:
                syntheticHeldFlags.insert(modifierFlag(for: step.keyCode))
                sendKeyDown(CGKeyCode(step.keyCode), syntheticHeldFlags)
            case .release:
                let releasedFlag = modifierFlag(for: step.keyCode)
                if releasedFlag.isEmpty {
                    sendKeyUp(CGKeyCode(step.keyCode), syntheticHeldFlags)
                } else {
                    syntheticHeldFlags.remove(releasedFlag)
                    sendKeyUp(CGKeyCode(step.keyCode), syntheticHeldFlags)
                }
            case .tap:
                sendKey(CGKeyCode(step.keyCode), syntheticHeldFlags.union(step.modifierFlags))
            }
        }
    }

    func sendKey(_ key: CGKeyCode, _ flags: CGEventFlags) {
        AppLogger.debug("[KeyboardEmulator] Sending key \\(key)")
        guard let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState),
              let kd = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let ku = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
        kd.flags = kd.flags.union(flags)
        ku.flags = ku.flags.union(flags)
        kd.post(tap: .cghidEventTap)
        ku.post(tap: .cghidEventTap)
    }

    private func sendKeyDown(_ key: CGKeyCode, _ flags: CGEventFlags) {
        guard let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) else { return }
        event.flags = event.flags.union(flags)
        event.post(tap: .cghidEventTap)
    }

    private func sendKeyUp(_ key: CGKeyCode, _ flags: CGEventFlags) {
        guard let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
        event.flags = event.flags.union(flags)
        event.post(tap: .cghidEventTap)
    }

    private func modifierFlag(for keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case 0x36, 0x37: return .maskCommand
        case 0x38: return .maskShift
        case 0x3A: return .maskAlternate
        case 0x3B: return .maskControl
        default: return []
        }
    }
}
import Cocoa
import Darwin
import IOKit.pwr_mgt

enum SystemActions {

    static func lockScreen() {
        if let h = dlopen("/System/Library/PrivateFrameworks/Login.framework/Versions/Current/Login", RTLD_LAZY) {
            defer { dlclose(h) }
            if let sym = dlsym(h, "SACLockScreenImmediate") {
                typealias Fn = @convention(c) () -> Void
                unsafeBitCast(sym, to: Fn.self)()
                return
            }
        }
        KeyboardEmulator.shared.sendKey(0x0C, [.maskCommand, .maskControl])   // Ctrl+Cmd+Q fallback
    }

    static func sleepSystem() {
        let port = IOPMFindPowerManagement(mach_port_t(0))
        guard port != 0 else { return }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    static func performMissionControl() {
        let f3: CGKeyCode = 160
        KeyboardEmulator.shared.sendKey(f3, [])
    }

    static func emptyTrash() {
        let script = """
        tell application "Finder"
            empty trash
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            AppLogger.debug("[Action] Empty trash failed: \\(error)")
        }
    }

    static func openFinder() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openDownloads() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        NSWorkspace.shared.open(url)
    }
}
