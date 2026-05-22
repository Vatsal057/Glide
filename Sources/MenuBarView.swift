import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge:  EngineBridge
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("Open Preferences…") {
            openWindow(id: "preferences")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Toggle("Enable Gestures", isOn: $engineBridge.isEnabled)

        Divider()

        Text("\(preferencesStore.rules.filter(\.isActive).count) active gestures")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit Glide") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
