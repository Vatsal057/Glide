import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var gestureStore:  GestureStore
    @EnvironmentObject var appSettings:   AppSettings
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

        Text("\(gestureStore.rules.filter(\.isEnabled).count) active gestures")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit Gesture") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

// Invisible launcher view — starts the engine once the environment is ready
struct EngineStarter: View {
    @EnvironmentObject var gestureStore: GestureStore
    @EnvironmentObject var appSettings:  AppSettings
    @EnvironmentObject var engineBridge: EngineBridge

    var body: some View {
        EmptyView()
            .onAppear {
                engineBridge.startEngine(store: gestureStore, settings: appSettings)
            }
            // Live-propagate store changes to engine (rules can change in Preferences)
            .onChange(of: gestureStore.rules.map(\.id)) { _ in
                GestureEngine.shared.store = gestureStore
            }
            .onChange(of: appSettings.activationThreshold) { _ in
                GestureEngine.shared.settings = appSettings
            }
    }
}
