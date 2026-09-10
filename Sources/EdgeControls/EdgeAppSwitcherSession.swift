import Cocoa
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeAppSwitcherSession
//
// Manages an active app switcher interaction initiated by scrubbing an edge.
// Seamlessly coordinates with Glide's AppSwitcherOverlayController and
// WindowTargeting to provide buttery-smooth app switching.
// ─────────────────────────────────────────────────────────────────────────────

final class EdgeAppSwitcherSession {
    private var apps: [NSRunningApplication] = []
    private var windowsByApp: [[AppSwitcherWindow]] = []
    private var selectedAppIndex: Int = 0
    private var usesCustomOverlay: Bool = false
    private var hasNativeCmdTabDown: Bool = false
    private(set) var isActive: Bool = false

    func begin(movingForward: Bool = true) -> Bool {
        guard !isActive else { return true }

        let systemApps = AppSwitcherState.shared.getOrderedApps()
        guard systemApps.count > 1 else { return false }
        let systemWindows = WindowTargeting.shared.switcherWindows(for: systemApps)

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let skipFinder = Settings.shared.appSwitcher.skipWindowlessFinder
        let customIndices = systemApps.indices.filter { index in
            !(skipFinder
              && systemApps[index].bundleIdentifier == "com.apple.finder"
              && systemWindows[index].isEmpty)
        }
        let customApps = customIndices.map { systemApps[$0] }
        let customWindows = customIndices.map { systemWindows[$0] }
        guard !customApps.isEmpty else { return false }

        let customIndex: Int = {
            guard let frontmostPID,
                  let frontIndex = customApps.firstIndex(where: { $0.processIdentifier == frontmostPID }) else {
                return movingForward ? 0 : customApps.count - 1
            }
            if movingForward { return (frontIndex + 1) < customApps.count ? (frontIndex + 1) : 0 }
            return frontIndex > 0 ? (frontIndex - 1) : (customApps.count - 1)
        }()

        self.apps = customApps
        self.windowsByApp = customWindows
        self.selectedAppIndex = customIndex
        self.isActive = true

        Haptic.switcherOpen()

        if Settings.shared.appSwitcher.style == .newer,
           AppSwitcherOverlayController.shared.show(
            apps: customApps,
            windowsByApp: customWindows,
            selectedAppIndex: customIndex,
            selectedWindowIndex: 0
        ) {
            usesCustomOverlay = true
            hasNativeCmdTabDown = false
            return true
        }

        // Native Cmd+Tab fallback
        usesCustomOverlay = false
        hasNativeCmdTabDown = true
        KeyboardEmulator.shared.sendKey(0x37, [.maskCommand]) // Cmd down
        return true
    }

    func step(forward: Bool) {
        guard isActive, !apps.isEmpty else { return }

        if forward {
            selectedAppIndex = (selectedAppIndex + 1) % apps.count
        } else {
            selectedAppIndex = (selectedAppIndex - 1 + apps.count) % apps.count
        }

        Haptic.switcherStep()

        if usesCustomOverlay {
            AppSwitcherOverlayController.shared.select(
                appIndex: selectedAppIndex,
                windowIndex: 0
            )
        }
    }

    func commit() {
        guard isActive else { return }
        defer {
            isActive = false
            apps = []
            windowsByApp = []
            hasNativeCmdTabDown = false
        }

        Haptic.switcherCommit()

        if usesCustomOverlay {
            AppSwitcherOverlayController.shared.hide()
            let selectedApp = apps.indices.contains(selectedAppIndex) ? apps[selectedAppIndex] : nil
            if let selectedApp,
               windowsByApp.indices.contains(selectedAppIndex),
               let firstWindow = windowsByApp[selectedAppIndex].first {
                WindowTargeting.shared.activateSwitcherWindow(firstWindow, in: selectedApp)
            } else {
                selectedApp?.unhide()
                selectedApp?.activate(options: .activateIgnoringOtherApps)
            }
        } else if hasNativeCmdTabDown {
            KeyboardEmulator.shared.sendKey(0x37, []) // Cmd up
        }
    }

    func cancel() {
        guard isActive else { return }
        defer {
            isActive = false
            apps = []
            windowsByApp = []
            hasNativeCmdTabDown = false
        }

        if usesCustomOverlay {
            AppSwitcherOverlayController.shared.hide()
        } else if hasNativeCmdTabDown {
            KeyboardEmulator.shared.sendKey(0x37, [])
        }
    }
}
