import Cocoa
import ServiceManagement

// ─────────────────────────────────────────────
// MARK: - AppDelegate
// ─────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: State
    private var statusItem: NSStatusItem!
    private var enabled = true
    private lazy var engine = GestureEngine.shared

    // MARK: Launch at Login

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                AppLogger.debug("[Glide] Launch at Login registered")
            } else {
                try SMAppService.mainApp.unregister()
                AppLogger.debug("[Glide] Launch at Login unregistered")
            }
        } catch {
            print("[Glide] Launch at Login error: \(error.localizedDescription)")
        }
        buildMenu()
    }

    // MARK: Launch
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.debug("[Glide] Launching")

        // Restore settings from the live config.yaml in Application Support
        // (no-op if the file doesn't exist yet — defaults are used instead)
        GlideConfigStore.shared.load()

        setupStatusBar()
        checkPermissions()

        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wnc.addObserver(self, selector: #selector(systemDidWake), name: name, object: nil)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            wnc.addObserver(self, selector: #selector(systemWillSleep), name: name, object: nil)
        }
        wnc.addObserver(self, selector: #selector(appDidTerminate(_:)),
                        name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // MARK: Permissions

    private func checkPermissions() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        if trusted {
            AppLogger.debug("[Glide] Accessibility granted — starting engine")
            engine.start()
        } else {
            print("[Glide] Accessibility not granted — polling")
            showPermissionsAlert()
            pollForAccessibility()
        }
    }

    private func showPermissionsAlert() {
        let a = NSAlert()
        a.messageText     = "Accessibility Permission Required"
        a.informativeText = """
        Glide needs Accessibility access to detect trackpad gestures and control windows.

        1. macOS has opened System Settings → Privacy & Security → Accessibility.
        2. Find "Glide" in the list and toggle it ON.
        3. The app will start automatically once permission is granted.
        """
        a.addButton(withTitle: "Open System Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func pollForAccessibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if AXIsProcessTrusted() {
                AppLogger.debug("[Glide] Accessibility granted — starting engine")
                self?.engine.start()
                self?.refreshIcon()
            } else {
                self?.pollForAccessibility()
            }
        }
    }

    // MARK: Wake / Terminate observers

    /// Tracks pending wake-restart work items so we can cancel them if
    /// we receive another wake notification before they fire.
    private var wakeRestartItems: [DispatchWorkItem] = []

    @objc private func systemDidWake() {
        guard enabled else { return }
        AppLogger.debug("[Glide] System woke — scheduling restart cascade")

        // Cancel any pending restarts from a previous wake
        wakeRestartItems.forEach { $0.cancel() }
        wakeRestartItems.removeAll()

        // Cascade of restarts at increasing delays.
        // Different Macs reinitialize trackpad hardware at different speeds.
        let delays: [TimeInterval] = [0.0, 2.0, 5.0, 10.0]
        for delay in delays {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.enabled else { return }
                AppLogger.debug("[Glide] Wake restart at +\(delay)s")
                self.engine.stop()
                self.engine.start()
            }
            wakeRestartItems.append(item)
            if delay == 0 {
                DispatchQueue.main.async(execute: item)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            }
        }
    }

    @objc private func systemWillSleep() {
        guard enabled else { return }
        AppLogger.debug("[Glide] System going to sleep — stopping engine")
        engine.stop()
    }

    @objc private func appDidTerminate(_ n: Notification) {
        guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        ActionExecutor.shared.pruneSavedFrame(for: app.processIdentifier)
    }

    // MARK: Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshIcon()
        buildMenu()
    }

    private func refreshIcon() {
        guard let btn = statusItem.button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(cfg)
        btn.image?.isTemplate = true
        btn.appearsDisabled = !enabled
    }

    private func buildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Glide", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: enabled ? "Disable" : "Enable",
                                action: #selector(toggleEnabled), keyEquivalent: "t"))
        menu.addItem(.separator())

        // Launch at Login toggle
        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Help",          action: #selector(showHelp),        keyEquivalent: "h"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Glide", action: #selector(quitApp),      keyEquivalent: "q"))

        // Wire targets
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        enabled ? engine.start() : engine.stop()
        refreshIcon()
        buildMenu()
        AppLogger.debug("[Glide] Engine \(enabled ? "enabled" : "disabled")")
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled)
    }

    @MainActor @objc private func showPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func showHelp() {
        let a = NSAlert()
        a.messageText = "How to Use Glide"
        a.informativeText = """
        Glide intercepts raw trackpad input and maps multi-finger gestures to macOS actions.

        Default gestures:
        • 3-finger click       → Quit app under cursor
        • 3-finger swipe ←/→   → Switch apps (App Switcher)
        • 3-finger swipe up    → Mission Control
        • 3-finger swipe down  → Minimize all apps
        • 4-finger swipe up    → Maximize window
        • 4-finger swipe down  → Restore window
        • 5-finger swipe up    → Enter fullscreen
        • 5-finger swipe down  → Exit fullscreen

        Reciprocal gestures:
        • Immediate reverse swipe closes Mission Control
        • Immediate reverse swipe restores apps minimized by Glide
        • Slow / Normal / Fast speeds can map to different actions

        You can add, remove, or customise all gestures in Preferences.

        Required permissions:
        • Accessibility — to control windows and simulate keys
        """
        a.addButton(withTitle: "Got it")
        a.runModal()
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
