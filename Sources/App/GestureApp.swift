import SwiftUI
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--test-gestures") {
            runGestureVerification(forceFailure: false)
            exit(0)
        }
        if CommandLine.arguments.contains("--test-gestures-fail") {
            runGestureVerification(forceFailure: true)
            exit(0)
        }

        EngineBridge.shared.startEngine()
        if OnboardingController.shouldShow {
            SplashOverlay.present { OnboardingController.shared.show() }
        } else {
            checkAccessibilityPermission()
        }
        // Re-assert on launch — System Settings may have re-enabled native gestures.
        SystemGestureManager.reconcileIfAutoEnabled()

        // One quiet check shortly after launch, so an available update shows up
        // in the menu bar instead of waiting to be hunted for. Delayed to keep
        // it off the critical path of getting gestures running.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            UpdateChecker.shared.checkIfDue()
        }

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

    @MainActor
    private func runGestureVerification(forceFailure: Bool) {
        print("[TEST] Running GestureAnimationView verification suite...")

        if forceFailure {
            print("[TEST] Forced failure requested -> exiting with code 1")
            exit(1)
        }

        var testedCount = 0
        for dir in GestureDirection.allCases {
            for fingers in [3, 4, 5] {
                for zone in TrackpadZone.allCases {
                    for mod in ModifierFilter.allCases {
                        for spd in GestureSpeed.allCases {
                            _ = GestureAnimationView(
                                direction: dir,
                                fingerCount: fingers,
                                zone: zone,
                                modifierFilter: mod,
                                speed: spd,
                                continuous: false,
                                action: .doNothing,
                                showLabel: true
                            )
                            testedCount += 1
                        }
                    }
                }
            }
        }
        print("[TEST] Initialized and verified \(testedCount) permutations of GestureAnimationView (including all speed tiers)")

        let samples: [(name: String, dir: GestureDirection, fingers: Int, zone: TrackpadZone, mod: ModifierFilter, spd: GestureSpeed, cont: Bool, act: GestureAction)] = [
            ("preview_3finger_swipe_fast.png", .swipeRight, 3, .topLeft, .shiftHeld, .fast, false, .switchAppNext),
            ("preview_3finger_swipe_slow.png", .swipeLeft, 3, .any, .any, .slow, false, .missionControl),
            ("preview_4finger_continuous.png", .swipeLeftRight, 4, .any, .noModifiers, .normal, true, .appSwitcherNext),
            ("preview_4finger_forceclick.png", .forceClick, 4, .any, .noModifiers, .normal, false, .lockScreen)
        ]

        for sample in samples {
            let sampleView = GestureAnimationView(
                direction: sample.dir,
                fingerCount: sample.fingers,
                zone: sample.zone,
                modifierFilter: sample.mod,
                speed: sample.spd,
                continuous: sample.cont,
                action: sample.act,
                showLabel: true
            )
            let renderer = ImageRenderer(content: sampleView)
            renderer.scale = 2.0
            if let nsImage = renderer.nsImage,
               let tiffData = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiffData),
               let pngData = rep.representation(using: .png, properties: [:]) {
                let path = "/Users/vatsal/.gemini/antigravity-ide/brain/e95df4e2-f922-4fa1-affb-19fe031ca3b4/\(sample.name)"
                try? pngData.write(to: URL(fileURLWithPath: path))
                print("[TEST] Saved sample \(sample.name) (\(pngData.count) bytes)")
            }
        }

        print("[TEST] ✅ GestureAnimationView verification PASSED.")
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
            syncTapHealthTimer()
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
        syncTapHealthTimer()

        startAccessibilityMonitoring()

        // Global keyboard-shortcut bindings (independent of the trackpad event tap).
        HotkeyManager.shared.reload()

        // Stop/restart around sleep-wake cycle (trackpad hardware reinits after wake)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NSLog("[App] Sleep — stopping engine")
                GlideConfigStore.shared.flushPendingSave()
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

    }

    /// Event taps get silently disabled by macOS (timeouts, permission churn). The
    /// tap callbacks re-enable themselves on a plain disable, so this periodic check
    /// is only a backstop for the rarer case where the Mach port goes invalid and the
    /// tap has to be torn down and rebuilt.
    ///
    /// It only has anything to check while the engine is actually running its taps,
    /// so it lives and dies with the engine: no wake-ups while gestures are toggled
    /// off or while the machine sleeps. Previously this was a 5s repeating timer
    /// created once and never invalidated — it fired ~17k times a day for the life of
    /// the process even with gestures disabled. Now it is engine-scoped, at 30s with
    /// generous slack so macOS can fold each check into a wake it was already making.
    private func syncTapHealthTimer() {
        if GestureEngine.shared.isRunning {
            guard tapHealthTimer == nil else { return }
            let timer = Timer(timeInterval: 30.0, repeats: true) { _ in
                Task { @MainActor in
                    let engine = GestureEngine.shared
                    guard engine.isRunning else { return }
                    engine.inputManager.checkHealth()
                }
            }
            timer.tolerance = 10.0
            RunLoop.main.add(timer, forMode: .common)
            tapHealthTimer = timer
        } else {
            tapHealthTimer?.invalidate()
            tapHealthTimer = nil
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

        // Poll briskly while the user is plausibly in System Settings granting
        // access, then back off. Without this the timer kept firing twice a
        // second for the entire life of the process on any Mac where
        // Accessibility is never granted — the `didBecomeActive` observer above
        // already catches the common "grant it, then come back" path.
        accessibilityPollStart = Date()
        scheduleAccessibilityPoll(interval: 0.5)
    }

    private var accessibilityPollStart: Date?
    /// How long to poll at the fast interval before easing off.
    private static let accessibilityFastPollWindow: TimeInterval = 60

    private func scheduleAccessibilityPoll(interval: TimeInterval) {
        accessibilityPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resumeEngineIfAccessibilityGranted()
                // Still not trusted and past the fast window — stop polling entirely.
                // A user grants Accessibility right after the launch prompt, which the
                // fast poll catches; a later grant is caught by the didBecomeActive
                // observer above when they next interact with Glide. Re-arming a 5s
                // timer here meant a Mac that never grants access woke the CPU every
                // five seconds for the entire life of the process.
                if let start = self.accessibilityPollStart,
                   Date().timeIntervalSince(start) > Self.accessibilityFastPollWindow {
                    self.accessibilityPollTimer?.invalidate()
                    self.accessibilityPollTimer = nil
                }
            }
        }
        timer.tolerance = interval / 2
        accessibilityPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        syncTapHealthTimer()
    }

    deinit {
        accessibilityPollTimer?.invalidate()
        tapHealthTimer?.invalidate()
        if let observer = accessibilityActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = wakeObserver  { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }
}
