import SwiftUI
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EngineBridge.shared.startEngine()
        if OnboardingController.shouldShow {
            OnboardingController.shared.show()
        } else {
            checkAccessibilityPermission()
        }
        // Re-assert on launch — System Settings may have re-enabled native gestures.
        SystemGestureManager.reconcileIfAutoEnabled()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlideConfigStore.shared.flushPendingSave()
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
import SwiftUI
import Cocoa
import Combine
import ApplicationServices

/// Connects the SwiftUI App lifecycle to the background engine and handles sleep/wake logic.
@MainActor
final class EngineBridge: ObservableObject {
    static let shared = EngineBridge()
    private init() {}

    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                GestureEngine.shared.start()
            } else {
                GestureEngine.shared.stop()
            }
        }
    }

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver:  NSObjectProtocol?
    private var accessibilityActiveObserver: NSObjectProtocol?
    private var accessibilityPollTimer: Timer?
    private var tapHealthTimer: Timer?
    /// User's toggle state captured at sleep so wake can restore it instead of
    /// force-enabling gestures the user had switched off.
    private var wasEnabledBeforeSleep = true
    private var started = false

    func startEngine() {
        guard !started else { return }
        started = true

        let engine = GestureEngine.shared
        if isEnabled {
            engine.start()
        }

        startAccessibilityMonitoring()

        // Stop/restart around sleep-wake cycle (trackpad hardware reinits after wake)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NSLog("[App] Sleep — stopping engine")
                self?.wasEnabledBeforeSleep = self?.isEnabled ?? true
                GestureEngine.shared.stop()
                self?.isEnabled = false
            }
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                NSLog("[App] Wake — restoring engine (enabled: \(self.wasEnabledBeforeSleep))")
                GestureEngine.shared.stop()
                self.isEnabled = self.wasEnabledBeforeSleep
            }
        }

        // Event taps get silently disabled by macOS (timeouts, permission churn).
        // Periodically verify and revive them while gestures are enabled.
        tapHealthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                let engine = GestureEngine.shared
                guard engine.isRunning else { return }
                engine.inputManager.checkHealth()
            }
        }
    }

    private func startAccessibilityMonitoring() {
        guard !AXIsProcessTrusted() else {
            PreferencesStore.shared.refreshAccessibilityStatus()
            return
        }

        accessibilityActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeEngineIfAccessibilityGranted()
            }
        }

        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.resumeEngineIfAccessibilityGranted()
            }
        }
        if let timer = accessibilityPollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopAccessibilityMonitoring() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        if let observer = accessibilityActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            accessibilityActiveObserver = nil
        }
    }

    private func resumeEngineIfAccessibilityGranted() {
        guard AXIsProcessTrusted() else { return }

        stopAccessibilityMonitoring()
        PreferencesStore.shared.refreshAccessibilityStatus()

        guard isEnabled else { return }
        GestureEngine.shared.start()
    }

    deinit {
        accessibilityPollTimer?.invalidate()
        if let observer = accessibilityActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = wakeObserver  { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }
}
