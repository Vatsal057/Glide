import Cocoa
import CoreGraphics
import Darwin

// ─────────────────────────────────────────────
// MARK: - ActionExecutor
// ─────────────────────────────────────────────

final class ActionExecutor {

    static let shared = ActionExecutor()
    private init() {}

    var hasRestorableMinimizedApps: Bool {
        WindowTargeting.shared.hasRestorableMinimizedApps
    }

    func pruneSavedFrame(for pid: pid_t) {
        WindowTargeting.shared.pruneSavedFrame(for: pid)
    }

    func isFrontmostWindowFullscreen() -> Bool {
        WindowTargeting.shared.isFrontmostWindowFullscreen()
    }

    func isFrontmostWindowMaximized() -> Bool {
        WindowTargeting.shared.isFrontmostWindowMaximized()
    }

    func quitAppAtCursor(_ location: NSPoint) {
        WindowTargeting.shared.quitAppAtCursor(location)
    }

    // MARK: - Action dispatch

    func execute(_ action: GestureAction, appPath: String? = nil, menuItemPath: [String]? = nil,
                 menuTargetBundleID: String? = nil, customShortcut: KeyboardShortcut? = nil,
                 advancedKeyboard: [KeyboardInputStep] = [],
                 shortcutName: String? = nil, script: String? = nil) {
        AppLogger.debug("[Action] \(action.rawValue)")
        switch action {

        // App lifecycle
        case .quitApp:           WindowTargeting.shared.quitAppAtCursor(NSEvent.mouseLocation)
        case .forceQuitApp:      WindowTargeting.shared.forceQuitAtCursor()
        case .quitFrontmost:     NSWorkspace.shared.frontmostApplication?.terminate()
        case .hideApp:           WindowTargeting.shared.hideAppAtCursor()
        case .hideOthers:        WindowTargeting.shared.hideAppAtCursor(othersOnly: true)
        case .openApp:           if let path = appPath { WindowTargeting.shared.openApp(path: path) }

        // App switching
        case .appSwitcherNext:   KeyboardEmulator.shared.sendKey(0x30, .maskCommand)
        case .appSwitcherPrev:   KeyboardEmulator.shared.sendKey(0x30, [.maskCommand, .maskShift])
        case .switchAppNext:     WindowTargeting.shared.activateAdjacentApp(forward: true)
        case .switchAppPrev:     WindowTargeting.shared.activateAdjacentApp(forward: false)

        // Window state
        case .minimizeWindow:        WindowTargeting.shared.minimizeFocused()
        case .minimizeAllApps:       WindowTargeting.shared.minimizeAllApps()
        case .restoreMinimizedApps:  WindowTargeting.shared.restoreMinimizedApps()
        case .maximizeWindow:        WindowTargeting.shared.maximize()
        case .restoreWindow:         WindowTargeting.shared.restore()
        case .closeWindow:           WindowTargeting.shared.closeWindow()
        case .enterFullscreen:       WindowTargeting.shared.setFullscreen(true)
        case .exitFullscreen:        WindowTargeting.shared.setFullscreen(false)
        case .toggleFullscreen:      WindowTargeting.shared.setFullscreen(nil)
        case .cycleWindows:          KeyboardEmulator.shared.sendKey(0x32, .maskCommand)

        // Window snapping
        case .snapLeft:         WindowTargeting.shared.snap(CGRect(x: 0,   y: 0,   width: 0.5, height: 1))
        case .snapRight:        WindowTargeting.shared.snap(CGRect(x: 0.5, y: 0,   width: 0.5, height: 1))
        case .snapTopLeft:      WindowTargeting.shared.snap(CGRect(x: 0,   y: 0.5, width: 0.5, height: 0.5))
        case .snapTopRight:     WindowTargeting.shared.snap(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        case .snapBottomLeft:   WindowTargeting.shared.snap(CGRect(x: 0,   y: 0,   width: 0.5, height: 0.5))
        case .snapBottomRight:  WindowTargeting.shared.snap(CGRect(x: 0.5, y: 0,   width: 0.5, height: 0.5))
        case .centerWindow:     WindowTargeting.shared.centerWindow()
        case .moveNextDisplay:  WindowTargeting.shared.moveToNextDisplay()

        // System
        case .missionControl:   SystemActions.performMissionControl()
        case .appExpose:        KeyboardEmulator.shared.sendKey(125, .maskControl)
        case .showDesktop:      KeyboardEmulator.shared.sendKey(103, [])
        case .launchpad:        KeyboardEmulator.shared.sendKey(131, [])
        case .spotlight:        KeyboardEmulator.shared.sendKey(0x31, .maskCommand)
        case .notifCenter:
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.notificationcenterui.dockControllerActivated"),
                object: nil, deliverImmediately: true)
        case .lockScreen:       SystemActions.lockScreen()
        case .sleep:            SystemActions.sleepSystem()
        case .screenshotArea:          KeyboardEmulator.shared.sendKey(0x15, [.maskCommand, .maskShift])
        case .screenshotFull:          KeyboardEmulator.shared.sendKey(0x14, [.maskCommand, .maskShift])
        case .screenshotAreaClipboard: KeyboardEmulator.shared.sendKey(0x15, [.maskCommand, .maskShift, .maskControl])
        case .screenshotFullClipboard: KeyboardEmulator.shared.sendKey(0x14, [.maskCommand, .maskShift, .maskControl])
        case .screenshotToolbar:       KeyboardEmulator.shared.sendKey(0x16, [.maskCommand, .maskShift])

        case .customMenuItem:
            if let path = menuItemPath {
                MenuItemExecutor.perform(path: path, bundleID: menuTargetBundleID)
            }

        case .customShortcut:
            if let shortcut = customShortcut, shortcut.isValid {
                KeyboardEmulator.shared.sendKey(CGKeyCode(shortcut.keyCode), shortcut.cgEventFlags)
            }

        case .advancedKeyboard:
            KeyboardEmulator.shared.executeKeyboardSteps(advancedKeyboard)

        case .runShortcut:
            if let name = shortcutName { SystemActions.runShortcut(named: name) }

        case .runShellCommand:
            if let script { SystemActions.runShellCommand(script) }

        case .runAppleScript:
            if let script { SystemActions.runAppleScript(script) }

        // Media & display
        case .playPause:      SystemActions.sendMediaKey(.play)
        case .nextTrack:      SystemActions.sendMediaKey(.next)
        case .previousTrack:  SystemActions.sendMediaKey(.previous)
        case .volumeUp:       SystemActions.sendMediaKey(.volumeUp)
        case .volumeDown:     SystemActions.sendMediaKey(.volumeDown)
        case .muteToggle:     SystemActions.sendMediaKey(.mute)
        case .brightnessUp:   SystemActions.sendMediaKey(.brightnessUp)
        case .brightnessDown: SystemActions.sendMediaKey(.brightnessDown)

        case .emptyTrash:    SystemActions.emptyTrash()
        case .openFinder:    SystemActions.openFinder()
        case .openDownloads: SystemActions.openDownloads()

        case .doNothing: break
        }
    }
}
