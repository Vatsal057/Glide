import SwiftUI
import AppKit

/// Click-to-record control that captures the next key combination.
struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut?
    @State private var isRecording = false
    @State private var monitor: Any?

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
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        guard isRecording else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .flagsChanged {
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
}
