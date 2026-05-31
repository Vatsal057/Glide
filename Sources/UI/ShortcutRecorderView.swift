import SwiftUI
import AppKit

/// Click-to-record control that captures the next key combination.
struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut?
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var eventTapRecorder: ShortcutEventTapRecorder?
    @State private var pendingModifierShortcut: KeyboardShortcut?

    var body: some View {
        HStack(spacing: 8) {
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 120, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Button(isRecording ? "Stop" : "Record") {
                if isRecording { stopRecording() } else { startRecording() }
            }

            if shortcut != nil {
                Button("Clear") { shortcut = nil }
            }
        }
        .onDisappear { stopRecording() }
    }

    private var displayText: String {
        if isRecording { return "Press keys…" }
        if let s = shortcut, s.isValid { return s.displayString }
        return "Not set"
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleEvent(event)
            return nil
        }
        eventTapRecorder = ShortcutEventTapRecorder(
            onShortcut: { captured in
                shortcut = captured
                stopRecording()
            },
            onCancel: {
                stopRecording()
            }
        )
        eventTapRecorder?.start()
    }

    private func stopRecording() {
        isRecording = false
        pendingModifierShortcut = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        eventTapRecorder?.stop()
        eventTapRecorder = nil
    }

    private func handleEvent(_ event: NSEvent) {
        guard isRecording else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .flagsChanged {
            let keyCode = UInt16(event.keyCode)
            if isPressedModifierKey(keyCode, flags: flags) {
                pendingModifierShortcut = KeyboardShortcut(keyCode: keyCode)
            } else if let pendingModifierShortcut,
                      keyCode == pendingModifierShortcut.keyCode {
                shortcut = pendingModifierShortcut
                stopRecording()
            }
            return
        }

        guard event.type == .keyDown else { return }

        let keyCode = UInt16(event.keyCode)
        if keyCode == 53 { // Escape — cancel
            stopRecording()
            return
        }

        let captured = KeyboardShortcut(
            keyCode: keyCode,
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            control: flags.contains(.control),
            option: flags.contains(.option)
        )

        guard captured.isValid else { return }
        shortcut = captured
        stopRecording()
    }

    private func isPressedModifierKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 0x36, 0x37:
            return flags.contains(.command)
        case 0x38:
            return flags.contains(.shift)
        case 0x3A:
            return flags.contains(.option)
        case 0x3B:
            return flags.contains(.control)
        default:
            return false
        }
    }
}

private final class ShortcutEventTapRecorder {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingModifierShortcut: KeyboardShortcut?
    private let onShortcut: (KeyboardShortcut) -> Void
    private let onCancel: () -> Void

    init(onShortcut: @escaping (KeyboardShortcut) -> Void, onCancel: @escaping () -> Void) {
        self.onShortcut = onShortcut
        self.onCancel = onCancel
    }

    func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let recorder = Unmanaged<ShortcutEventTapRecorder>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .keyDown {
                    recorder.handleKeyDown(event)
                    return nil
                }
                if type == .flagsChanged {
                    recorder.handleFlagsChanged(event)
                    return nil
                }
                return nil
            },
            userInfo: unmanagedSelf
        )

        guard let eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        pendingModifierShortcut = nil
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        DispatchQueue.main.async {
            if keyCode == 53 {
                self.onCancel()
                return
            }
            let flags = event.flags
            self.onShortcut(KeyboardShortcut(
                keyCode: keyCode,
                command: flags.contains(.maskCommand),
                shift: flags.contains(.maskShift),
                control: flags.contains(.maskControl),
                option: flags.contains(.maskAlternate)
            ))
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if isPressedModifierKey(keyCode, flags: flags) {
            pendingModifierShortcut = KeyboardShortcut(keyCode: keyCode)
            return
        }
        guard let pendingModifierShortcut,
              keyCode == pendingModifierShortcut.keyCode else {
            return
        }
        self.pendingModifierShortcut = nil
        DispatchQueue.main.async {
            self.onShortcut(pendingModifierShortcut)
        }
    }

    private func isPressedModifierKey(_ keyCode: UInt16, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 0x36, 0x37:
            return flags.contains(.maskCommand)
        case 0x38:
            return flags.contains(.maskShift)
        case 0x3A:
            return flags.contains(.maskAlternate)
        case 0x3B:
            return flags.contains(.maskControl)
        default:
            return false
        }
    }
}
