import SwiftUI
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EngineBridge.shared.startEngine()
        checkAccessibilityPermission()
    }

    private func checkAccessibilityPermission() {
        if AXIsProcessTrusted() { return }

        // Prompt the user — passing `kAXTrustedCheckOptionPrompt` shows the
        // native macOS dialog and opens Accessibility in System Settings.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

@main
struct GestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        GlideConfigStore.shared.load()
    }

    @StateObject private var preferencesStore = PreferencesStore.shared
    @StateObject private var engineBridge = EngineBridge.shared

    var body: some Scene {
        MenuBarExtra("Glide", systemImage: "hand.draw") {
            MenuBarView()
                .environmentObject(preferencesStore)
                .environmentObject(engineBridge)
        }
        .menuBarExtraStyle(.menu)

        Window("Glide Preferences", id: "preferences") {
            PreferencesWindow()
                .environmentObject(preferencesStore)
                .environmentObject(engineBridge)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)

        SwiftUI.Settings { EmptyView() }
    }
}
