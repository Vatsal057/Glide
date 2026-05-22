import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - ActionExecutor

final class ActionExecutor {

    static let shared = ActionExecutor()
    private init() {}

    // App-switcher state
    private var switcherActive = false
    private var switcherApps:   [NSRunningApplication] = []
    private var switcherIndex:  Int = 0
    private var switcherDismissWorkItem: DispatchWorkItem?

    // Window restore cache: pid → original frame
    private var savedFrames: [pid_t: CGRect] = [:]

    // MARK: - Public

    func execute(_ action: GestureAction, targetApp: String = "") {
        DispatchQueue.main.async { [self] in
            self._execute(action, targetApp: targetApp)
        }
    }

    func executeReciprocal(of action: GestureAction) {
        DispatchQueue.main.async { [self] in
            self._executeReciprocal(of: action)
        }
    }

    // MARK: - Private dispatch

    private func _execute(_ action: GestureAction, targetApp: String) {
        switch action {

        // ── Apps ─────────────────────────────────────────────────────────────
        case .quitAppUnderCursor:       quitApp(underCursor: true, force: false)
        case .forceQuitAppUnderCursor:  quitApp(underCursor: true, force: true)
        case .quitFrontmostApp:         quitApp(underCursor: false, force: false)
        case .hideAppUnderCursor:       hideApp(underCursor: true)
        case .hideOtherApps:            hideOtherApps()
        case .openApp:                  openApp(named: targetApp)
        case .nextApp:                  stepSwitcher(forward: true)
        case .prevApp:                  stepSwitcher(forward: false)
        case .activateNextApp:          activateAdjacentApp(forward: true)
        case .activatePrevApp:          activateAdjacentApp(forward: false)

        // ── Windows ──────────────────────────────────────────────────────────
        case .minimizeWindow:           sendKey(0x6E, flags: .maskCommand)   // Cmd+M
        case .minimizeAllApps:          minimizeAll()
        case .restoreMinimizedApps:     restoreMinimized()
        case .maximizeWindow:           maximizeWindow()
        case .restoreWindow:            restoreWindow()
        case .closeWindow:              sendKey(0x0D, flags: .maskCommand)   // Cmd+W
        case .enterFullscreen:          sendKey(0x03, flags: [.maskCommand, .maskControl])
        case .exitFullscreen:           sendKey(0x03, flags: [.maskCommand, .maskControl])
        case .toggleFullscreen:         sendKey(0x03, flags: [.maskCommand, .maskControl])
        case .cycleWindows:             sendKey(0x32, flags: .maskCommand)   // Cmd+`
        case .snapLeft:                 snapWindow(.left)
        case .snapRight:                snapWindow(.right)
        case .snapTopLeft:              snapWindow(.topLeft)
        case .snapTopRight:             snapWindow(.topRight)
        case .snapBottomLeft:           snapWindow(.bottomLeft)
        case .snapBottomRight:          snapWindow(.bottomRight)
        case .centerWindow:             centerWindow()
        case .moveToNextDisplay:        moveWindowToNextDisplay()

        // ── Screenshots ──────────────────────────────────────────────────────
        case .screenshotArea:           sendKey(0x04, flags: [.maskShift, .maskCommand])           // Shift+Cmd+4
        case .screenshotFull:           sendKey(0x14, flags: [.maskShift, .maskCommand])           // Shift+Cmd+3
        case .screenshotAreaClipboard:  sendKey(0x04, flags: [.maskShift, .maskCommand, .maskControl])
        case .screenshotFullClipboard:  sendKey(0x14, flags: [.maskShift, .maskCommand, .maskControl])
        case .screenshotToolbar:        sendKey(0x04, flags: [.maskShift, .maskCommand, .maskAlternate]) // Shift+Cmd+Opt+5 → toolbar

        // ── Editing ──────────────────────────────────────────────────────────
        case .copy:         sendKey(0x08, flags: .maskCommand)   // Cmd+C
        case .paste:        sendKey(0x09, flags: .maskCommand)   // Cmd+V
        case .cut:          sendKey(0x07, flags: .maskCommand)   // Cmd+X
        case .undo:         sendKey(0x06, flags: .maskCommand)   // Cmd+Z
        case .redo:         sendKey(0x06, flags: [.maskCommand, .maskShift])
        case .selectAll:    sendKey(0x00, flags: .maskCommand)   // Cmd+A
        case .find:         sendKey(0x03, flags: .maskCommand)   // Cmd+F
        case .emojiSymbols: sendKey(0x31, flags: [.maskCommand, .maskControl])  // Ctrl+Cmd+Space
        case .reloadPage:   sendKey(0x0F, flags: .maskCommand)   // Cmd+R
        case .newTab:       sendKey(0x11, flags: .maskCommand)   // Cmd+T

        // ── Media & Display ──────────────────────────────────────────────────
        case .volumeUp:        sendMediaKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown:      sendMediaKey(NX_KEYTYPE_SOUND_DOWN)
        case .mute:            sendMediaKey(NX_KEYTYPE_MUTE)
        case .playPause:       sendMediaKey(NX_KEYTYPE_PLAY)
        case .nextTrack:       sendMediaKey(NX_KEYTYPE_NEXT)
        case .prevTrack:       sendMediaKey(NX_KEYTYPE_PREVIOUS)
        case .brightnessUp:    sendMediaKey(NX_KEYTYPE_BRIGHTNESS_UP)
        case .brightnessDown:  sendMediaKey(NX_KEYTYPE_BRIGHTNESS_DOWN)

        // ── System ───────────────────────────────────────────────────────────
        case .missionControl:      sendKey(0x7E, flags: .maskControl)   // Ctrl+Up
        case .appExpose:           sendKey(0x7D, flags: .maskControl)   // Ctrl+Down
        case .showDesktop:         sendKey(0x77, flags: .maskCommand)   // F11 → Show Desktop
        case .launchpad:           launchLaunchpad()
        case .spotlight:           sendKey(0x31, flags: .maskCommand)   // Cmd+Space
        case .notificationCenter:  openNotificationCenter()
        case .lockScreen:          lockScreen()
        case .sleep:               sleep_()
        case .emptyTrash:          emptyTrash()
        case .openFinder:          NSWorkspace.shared.launchApplication("Finder")
        case .openDownloads:       NSWorkspace.shared.open(URL(fileURLWithPath: ("~/Downloads" as NSString).expandingTildeInPath))

        case .doNothing: break
        }
    }

    private func _executeReciprocal(of action: GestureAction) {
        switch action {
        case .maximizeWindow:   restoreWindow()
        case .restoreWindow:    maximizeWindow()
        case .enterFullscreen:  sendKey(0x03, flags: [.maskCommand, .maskControl])
        case .minimizeWindow:   sendKey(0x6D, flags: .maskCommand)  // Cmd+Opt+M (de-minimise heuristic)
        case .hideAppUnderCursor: NSWorkspace.shared.frontmostApplication?.activate(options: [])
        case .nextApp:          stepSwitcher(forward: false)
        case .prevApp:          stepSwitcher(forward: true)
        case .snapLeft:         snapWindow(.right)
        case .snapRight:        snapWindow(.left)
        default: break
        }
    }

    // MARK: - Key events

    /// Send a CGEvent key tap with the given virtual key code and flags.
    private func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let dn  = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up  = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        dn?.flags = flags
        up?.flags = flags
        dn?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Post an NX media key via a system-defined event.
    private func sendMediaKey(_ key: Int32) {
        func event(down: Bool) -> NSEvent? {
            let data1 = Int((key << 16) | (down ? (0xA << 8) : (0xB << 8)))
            return NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
        }
        event(down: true)?.cgEvent?.post(tap: .cgAnnotatedSessionEventTap)
        event(down: false)?.cgEvent?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - App actions

    private func quitApp(underCursor: Bool, force: Bool) {
        let app = underCursor ? appUnderCursor() : NSWorkspace.shared.frontmostApplication
        guard let app = app else { return }
        if force {
            app.forceTerminate()
        } else {
            app.terminate()
        }
    }

    private func hideApp(underCursor: Bool) {
        let app = underCursor ? appUnderCursor() : NSWorkspace.shared.frontmostApplication
        app?.hide()
    }

    private func hideOtherApps() {
        let front = NSWorkspace.shared.frontmostApplication
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app != front {
            app.hide()
        }
    }

    private func openApp(named name: String) {
        guard !name.isEmpty else { return }
        let candidates = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            ("~/Applications/\(name).app" as NSString).expandingTildeInPath
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.launchApplication(path)
                return
            }
        }
        // Fall back to bundle-ID or partial name search
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - App Switcher

    private func stepSwitcher(forward: Bool) {
        if !switcherActive {
            switcherApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            switcherIndex = switcherApps.firstIndex { $0.isActive } ?? 0
            switcherActive = true
        }
        let count = switcherApps.count
        guard count > 0 else { return }
        switcherIndex = (switcherIndex + (forward ? 1 : -1) + count) % count
        switcherApps[switcherIndex].activate(options: [.activateIgnoringOtherApps])

        // Auto-dismiss after idle
        switcherDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissSwitcher()
        }
        switcherDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func dismissSwitcher() { switcherActive = false }

    private func activateAdjacentApp(forward: Bool) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        guard !apps.isEmpty else { return }
        let idx = (apps.firstIndex { $0.isActive } ?? 0)
        let next = (idx + (forward ? 1 : -1) + apps.count) % apps.count
        apps[next].activate(options: [.activateIgnoringOtherApps])
    }

    private func appUnderCursor() -> NSRunningApplication? {
        let loc = NSEvent.mouseLocation
        let screenH = NSScreen.main?.frame.height ?? 800
        let cgPt = CGPoint(x: loc.x, y: screenH - loc.y)
        // Use CGWindowList to find window at cursor
        let opts = CGWindowListOption.optionOnScreenOnly
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid    = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(cgPt) {
                return NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
            }
        }
        return nil
    }

    // MARK: - Window actions via AX

    /// Returns the AXUIElement for the focused window of the frontmost app.
    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &win) == .success,
              CFGetTypeID(win!) == AXUIElementGetTypeID() else { return nil }
        return (win as! AXUIElement)
    }

    private func windowFrame(_ win: AXUIElement) -> CGRect? {
        var posRef:  CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)  == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString,     &sizeRef) == .success else { return nil }
        var pos  = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef  as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize,  &size)
        return CGRect(origin: pos, size: size)
    }

    private func setWindowFrame(_ win: AXUIElement, _ frame: CGRect) {
        var pos  = frame.origin
        var size = frame.size
        if let pv = AXValueCreate(.cgPoint, &pos)  { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize,  &size)  { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString,    sv) }
    }

    private func maximizeWindow() {
        guard let win    = focusedWindow(),
              let screen = NSScreen.main else { return }

        // Save current frame for restore
        if let cur = windowFrame(win),
           let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            savedFrames[pid] = cur
        }

        let f = screen.visibleFrame
        setWindowFrame(win, CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height))
    }

    private func restoreWindow() {
        guard let win = focusedWindow(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let saved = savedFrames[pid] else { return }
        setWindowFrame(win, saved)
        savedFrames.removeValue(forKey: pid)
    }

    private func minimizeAll() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var wins: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &wins) == .success,
                  let windowList = wins as? [AXUIElement] else { continue }
            for w in windowList {
                AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            }
        }
    }

    private func restoreMinimized() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var wins: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &wins) == .success,
                  let windowList = wins as? [AXUIElement] else { continue }
            for w in windowList {
                var minimized: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized) == .success,
                   (minimized as? Bool) == true {
                    AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                }
            }
        }
    }

    // Snap targets
    private enum SnapQuadrant { case left, right, topLeft, topRight, bottomLeft, bottomRight }

    private func snapWindow(_ quad: SnapQuadrant) {
        guard let win    = focusedWindow(),
              let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let half = CGSize(width: f.width / 2, height: f.height / 2)
        let frame: CGRect
        switch quad {
        case .left:        frame = CGRect(x: f.minX,            y: f.minY,            width: half.width, height: f.height)
        case .right:       frame = CGRect(x: f.midX,            y: f.minY,            width: half.width, height: f.height)
        case .topLeft:     frame = CGRect(x: f.minX,            y: f.midY,            width: half.width, height: half.height)
        case .topRight:    frame = CGRect(x: f.midX,            y: f.midY,            width: half.width, height: half.height)
        case .bottomLeft:  frame = CGRect(x: f.minX,            y: f.minY,            width: half.width, height: half.height)
        case .bottomRight: frame = CGRect(x: f.midX,            y: f.minY,            width: half.width, height: half.height)
        }
        setWindowFrame(win, frame)
    }

    private func centerWindow() {
        guard let win    = focusedWindow(),
              let screen = NSScreen.main,
              let cur    = windowFrame(win) else { return }
        let f = screen.visibleFrame
        let newOrigin = CGPoint(x: f.midX - cur.width / 2, y: f.midY - cur.height / 2)
        setWindowFrame(win, CGRect(origin: newOrigin, size: cur.size))
    }

    private func moveWindowToNextDisplay() {
        guard let win = focusedWindow(), NSScreen.screens.count > 1 else { return }
        guard let cur = windowFrame(win) else { return }

        // Find which screen the window is currently on
        let screens = NSScreen.screens
        let current = screens.first { $0.frame.contains(CGPoint(x: cur.midX, y: cur.midY)) } ?? screens[0]
        guard let idx = screens.firstIndex(of: current) else { return }
        let next = screens[(idx + 1) % screens.count]

        // Map relative position onto next screen
        let relX = (cur.minX - current.visibleFrame.minX) / current.visibleFrame.width
        let relY = (cur.minY - current.visibleFrame.minY) / current.visibleFrame.height
        let newX = next.visibleFrame.minX + relX * next.visibleFrame.width
        let newY = next.visibleFrame.minY + relY * next.visibleFrame.height
        setWindowFrame(win, CGRect(origin: CGPoint(x: newX, y: newY), size: cur.size))
    }

    // MARK: - System actions

    private func launchLaunchpad() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.launchpad.launcher") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: F4 keycode
            sendKey(0x7C, flags: [])
        }
    }

    private func openNotificationCenter() {
        // Ctrl+F8 is the standard shortcut exposed to Accessibility
        // More reliable: click menu bar clock via AX
        let systemUIServer = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        systemUIServer?.activate(options: [])
        // Shift+Cmd+\ opens NC in Sequoia/Sonoma
        sendKey(0x2A, flags: [.maskShift, .maskCommand])
    }

    private func lockScreen() {
        let src = CGEventSource(stateID: .hidSystemState)
        // Ctrl+Cmd+Q
        let dn = CGEvent(keyboardEventSource: src, virtualKey: 0x0C, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x0C, keyDown: false)
        dn?.flags = [.maskControl, .maskCommand]
        up?.flags = [.maskControl, .maskCommand]
        dn?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func sleep_() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        if FileManager.default.fileExists(atPath: url.path) {
            Process.launchedProcess(launchPath: url.path, arguments: ["-suspend"])
        } else {
            // Use pmset
            Process.launchedProcess(launchPath: "/usr/bin/pmset", arguments: ["sleepnow"])
        }
    }

    private func emptyTrash() {
        let script = "tell application \"Finder\" to empty trash"
        if let s = NSAppleScript(source: script) { s.executeAndReturnError(nil) }
    }
}
