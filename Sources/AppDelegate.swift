import Cocoa

// ─────────────────────────────────────────────
// MARK: - AppDelegate
// ─────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var enabled = true
    private lazy var engine = GestureEngine.shared

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.debug("[Glide] Launching")

        GlideConfigStore.shared.load()   // restores settings from config.yaml; no-op if missing

        setupStatusBar()
        checkPermissions()

        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(self, selector: #selector(systemDidWake),
                        name: NSWorkspace.didWakeNotification, object: nil)
        wnc.addObserver(self, selector: #selector(systemDidWake),
                        name: NSWorkspace.screensDidWakeNotification, object: nil)
        wnc.addObserver(self, selector: #selector(systemWillSleep),
                        name: NSWorkspace.willSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(systemWillSleep),
                        name: NSWorkspace.screensDidSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(appDidTerminate(_:)),
                        name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // MARK: Permissions

    private func checkPermissions() {
        if AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        ) {
            AppLogger.debug("[Glide] Accessibility granted — starting engine")
            engine.start()
        } else {
            print("[Glide] Accessibility not granted — polling")
            pollForAccessibility()
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

    // MARK: Wake / Sleep observers

    /// Pending wake-restart work items so we can cancel them on rapid successive wakes.
    private var pendingWakeRestarts: [DispatchWorkItem] = []

    @objc private func systemDidWake() {
        guard enabled else { return }
        AppLogger.debug("[Glide] System woke — scheduling restarts")

        // Cancel any restart already in flight
        pendingWakeRestarts.forEach { $0.cancel() }
        pendingWakeRestarts.removeAll()

        // Immediate restart + one delayed restart to handle slow trackpad hardware init.
        // Two delays cover all known Mac models; more delays provided diminishing returns.
        for delay in [0.0, 3.0] {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.enabled else { return }
                AppLogger.debug("[Glide] Wake restart at +\(delay)s")
                self.engine.forceReinitializeInputPipeline()
            }
            pendingWakeRestarts.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    @objc private func systemWillSleep() {
        guard enabled else { return }
        AppLogger.debug("[Glide] System sleeping — stopping engine")
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
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Glide",    action: #selector(quitApp),         keyEquivalent: "q"))

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

    @MainActor @objc private func showPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
