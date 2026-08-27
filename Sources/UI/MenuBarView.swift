import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge:  EngineBridge
    @ObservedObject private var updater = UpdateChecker.shared
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("Open Preferences…") {
            showPreferences()
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

        updateItem

        Text("Glide \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit Glide") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// Updates are downloaded and installed inside the app, so every path here
    /// leads to the General tab rather than out to the browser.
    @ViewBuilder
    private var updateItem: some View {
        switch updater.state {
        case .available(let update):
            Button("Install Update \(update.tag)…") {
                showPreferences(tab: .general)
                updater.downloadAndInstall(update)
            }

        case .installed:
            Button("Relaunch to Finish Update") {
                updater.relaunch()
            }

        case .downloading, .installing:
            Text("Updating Glide…")
                .foregroundStyle(.secondary)

        case .idle, .checking, .upToDate, .failed, .manualInstall:
            Button("Check for Updates…") {
                showPreferences(tab: .general)
                updater.check()
            }
        }
    }

    private func showPreferences(tab: PrefsTab? = nil) {
        if let tab { PreferencesNavigator.shared.tab = tab }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "preferences")
        NSApp.activate(ignoringOtherApps: true)
    }
}
