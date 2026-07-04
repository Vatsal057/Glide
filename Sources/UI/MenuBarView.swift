import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge:  EngineBridge
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("Open Preferences…") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "preferences")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Toggle("Enable Gestures", isOn: $engineBridge.isEnabled)

        if !preferencesStore.accessibilityGranted {
            Button("⚠️ Grant Accessibility Access…") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Text("\(preferencesStore.rules.filter(\.isActive).count) active gestures")
            .foregroundStyle(.secondary)

        Divider()

        Button("Check for Updates…") {
            NSWorkspace.shared.open(URL(string: "https://github.com/Vatsal057/Glide/releases/latest")!)
        }

        Text("Glide \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit Glide") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
