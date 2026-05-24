import Cocoa
import CoreGraphics
import Darwin
import IOKit.pwr_mgt

// ─────────────────────────────────────────────
// MARK: - ActionExecutor
// ─────────────────────────────────────────────

final class ActionExecutor {

    static let shared = ActionExecutor()
    private init() {}

    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)
    private var syntheticHeldFlags: CGEventFlags = []

    // MARK: - Maximize / Restore frame memory

    private struct WindowKey: Hashable {
        let pid: pid_t; let identity: Int
    }

    private var savedFrames: [WindowKey: CGRect] = [:]

    /// Prunes savedFrames entries for PIDs that are no longer running.
    /// Only runs when the dict exceeds 20 entries to avoid background overhead.
    private func pruneOrphanedFrames() {
        guard savedFrames.count > 20 else { return }
        let running = Set(NSWorkspace.shared.runningApplications.map { $0.processIdentifier })
        savedFrames = savedFrames.filter { running.contains($0.key.pid) }
    }

    func pruneSavedFrame(for pid: pid_t) {
        savedFrames = savedFrames.filter { $0.key.pid != pid }
        pruneStaleMinimizedWindows(for: pid)
    }

    // MARK: - Minimize / Restore state

    var hasRestorableMinimizedApps: Bool {
        pruneStaleMinimizedWindows()
        return !lastMinimizedWindows.isEmpty
    }

    private var lastMinimizedWindows: [AXUIElement] = []
    private var frontmostBeforeMinimize: NSRunningApplication?

    // MARK: - Action dispatch

    func execute(_ action: GestureAction, appPath: String? = nil, menuItemPath: [String]? = nil,
                 menuTargetBundleID: String? = nil, customShortcut: KeyboardShortcut? = nil,
                 advancedKeyboard: [KeyboardInputStep] = []) {
        AppLogger.debug("[Action] \(action.rawValue)")
        switch action {

        // App lifecycle
        case .quitApp:           quitAppAtCursor(NSEvent.mouseLocation)
        case .forceQuitApp:      forceQuitAtCursor()
        case .quitFrontmost:     NSWorkspace.shared.frontmostApplication?.terminate()
        case .hideApp:           hideAppAtCursor()
        case .hideOthers:        hideAppAtCursor(othersOnly: true)
        case .openApp:           if let path = appPath { openApp(path: path) }

        // App switching
        case .appSwitcherNext:   sendKey(0x30, .maskCommand)
        case .appSwitcherPrev:   sendKey(0x30, [.maskCommand, .maskShift])
        case .switchAppNext:     activateAdjacentApp(forward: true)
        case .switchAppPrev:     activateAdjacentApp(forward: false)

        // Window state
        case .minimizeWindow:        minimizeFocused()
        case .minimizeAllApps:       minimizeAllApps()
        case .restoreMinimizedApps:  restoreMinimizedApps()
        case .maximizeWindow:        maximize()
        case .restoreWindow:         restore()
        case .closeWindow:           closeWindow()
        case .enterFullscreen:       setFullscreen(true)
        case .exitFullscreen:        setFullscreen(false)
        case .toggleFullscreen:      setFullscreen(nil)
        case .cycleWindows:          sendKey(0x32, .maskCommand)

        // Window snapping
        case .snapLeft:         snap(CGRect(x: 0,   y: 0,   width: 0.5, height: 1))
        case .snapRight:        snap(CGRect(x: 0.5, y: 0,   width: 0.5, height: 1))
        case .snapTopLeft:      snap(CGRect(x: 0,   y: 0.5, width: 0.5, height: 0.5))
        case .snapTopRight:     snap(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        case .snapBottomLeft:   snap(CGRect(x: 0,   y: 0,   width: 0.5, height: 0.5))
        case .snapBottomRight:  snap(CGRect(x: 0.5, y: 0,   width: 0.5, height: 0.5))
        case .centerWindow:     centerWindow()
        case .moveNextDisplay:  moveToNextDisplay()

        // System
        case .missionControl:   performMissionControl()
        case .appExpose:        sendKey(125, .maskControl)
        case .showDesktop:      sendKey(103, [])
        case .launchpad:        sendKey(131, [])
        case .spotlight:        sendKey(0x31, .maskCommand)
        case .notifCenter:
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.notificationcenterui.dockControllerActivated"),
                object: nil, deliverImmediately: true)
        case .lockScreen:       lockScreen()
        case .sleep:            sleepSystem()
        case .screenshotArea:          sendKey(0x15, [.maskCommand, .maskShift])
        case .screenshotFull:          sendKey(0x14, [.maskCommand, .maskShift])
        case .screenshotAreaClipboard: sendKey(0x15, [.maskCommand, .maskShift, .maskControl])
        case .screenshotFullClipboard: sendKey(0x14, [.maskCommand, .maskShift, .maskControl])
        case .screenshotToolbar:       sendKey(0x16, [.maskCommand, .maskShift])

        case .customMenuItem:
            if let path = menuItemPath {
                MenuItemExecutor.perform(path: path, bundleID: menuTargetBundleID)
            }

        case .customShortcut:
            if let shortcut = customShortcut, shortcut.isValid {
                sendKey(CGKeyCode(shortcut.keyCode), shortcut.cgEventFlags)
            }

        case .advancedKeyboard:
            executeKeyboardSteps(advancedKeyboard)

        case .emptyTrash:    emptyTrash()
        case .openFinder:    openFinder()
        case .openDownloads: openDownloads()

        case .doNothing: break
        }
    }

    private func emptyTrash() {
        let script = """
        tell application "Finder"
            empty trash
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            AppLogger.debug("[Action] Empty trash failed: \(error)")
        }
    }

    private func openFinder() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openDownloads() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        NSWorkspace.shared.open(url)
    }

    private func performMissionControl() {
        guard let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState) else { return }
        let f3: CGKeyCode = 160
        CGEvent(keyboardEventSource: src, virtualKey: f3, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: f3, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // MARK: - App under cursor

    func quitAppAtCursor(_ location: NSPoint) {
        guard let pid = pidAtLocation(location) else { return }
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    private func forceQuitAtCursor() {
        guard let pid = pidAtLocation(NSEvent.mouseLocation) else { return }
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
        activateAnotherApp(excluding: pid)
    }

    private func hideAppAtCursor(othersOnly: Bool = false) {
        guard let pid = pidAtLocation(NSEvent.mouseLocation) else { return }
        if othersOnly {
            NSRunningApplication(processIdentifier: pid)?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.sendKey(0x04, [.maskCommand, .maskAlternate])
            }
        } else {
            NSRunningApplication(processIdentifier: pid)?.hide()
        }
    }

    private func activateAnotherApp(excluding pid: pid_t) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSWorkspace.shared.runningApplications
                .first { $0.activationPolicy == .regular
                      && $0.processIdentifier != pid
                      && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate(options: .activateIgnoringOtherApps)
        }
    }

    private func openApp(path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: .init()) { _, _ in }
    }

    // MARK: - Window targeting

    private func targetWindow() -> AXUIElement? {
        switch Settings.shared.windowTargetingMode {
        case .focusedThenCursor: return focusedWindow() ?? windowAtCursor()
        case .cursorThenFocused: return windowAtCursor() ?? focusedWindow()
        }
    }

    func windowAtCursor(_ location: NSPoint? = nil) -> AXUIElement? {
        let cgPt  = quartzPoint(from: location ?? NSEvent.mouseLocation)
        let myPID = ProcessInfo.processInfo.processIdentifier

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for win in list {
            guard let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid    = win[kCGWindowOwnerPID as String] as? pid_t,
                  let layer  = win[kCGWindowLayer as String] as? Int,
                  pid != myPID, layer == 0 else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            guard rect.contains(cgPt) else { continue }
            let appEl = AXUIElementCreateApplication(pid)
            var wRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &wRef) == .success,
                  let windows = wRef as? [AXUIElement] else { continue }
            for w in windows {
                if let f = axFrame(w), abs(f.minX - rect.minX) < 20, abs(f.minY - rect.minY) < 20 { return w }
            }
            return windows.first
        }
        return nil
    }

    private func pidAtLocation(_ loc: NSPoint) -> pid_t? {
        let cgPt  = quartzPoint(from: loc)
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for win in list {
            guard let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid    = win[kCGWindowOwnerPID as String] as? pid_t,
                  let layer  = win[kCGWindowLayer as String] as? Int,
                  pid != myPID, layer == 0 else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(cgPt) { return pid }
        }
        return nil
    }

    private func focusedWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success else { return nil }
        return axElement(from: ref)
    }

    // MARK: - Window state queries

    func isFrontmostWindowFullscreen() -> Bool {
        guard let w = focusedWindow() else { return false }
        return axBool(w, attribute: "AXFullScreen" as CFString) ?? false
    }

    func isFrontmostWindowMaximized() -> Bool {
        guard let w = focusedWindow() else { return false }
        return isWindowMaximized(w)
    }

    internal func isWindowMaximized(_ window: AXUIElement) -> Bool {
        guard let frame = axFrame(window), let screen = screen(for: window) else { return false }
        let visible   = axFrame(fromVisibleFrame: screen.visibleFrame)
        let tolerance: CGFloat = 16
        return abs(frame.minX - visible.minX) <= tolerance
            && abs(frame.minY - visible.minY) <= tolerance
            && abs(frame.width  - visible.width)  <= tolerance
            && abs(frame.height - visible.height) <= tolerance
    }

    // MARK: - Window operations

    private func minimizeFocused() {
        guard let w = targetWindow() else { return }
        minimize(window: w)
    }

    private func minimize(window: AXUIElement) {
        let currentApp = NSWorkspace.shared.frontmostApplication
        guard setAXBool(window, attribute: kAXMinimizedAttribute as CFString, value: true) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.activateNextApp(excluding: currentApp)
        }
    }

    private func activateNextApp(excluding current: NSRunningApplication?) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
            && $0.processIdentifier != myPID
            && $0.processIdentifier != (current?.processIdentifier ?? 0)
            && !$0.isHidden
        }
        let appWithVisible = apps.first { app in
            self.windows(for: app.processIdentifier).contains {
                self.axBool($0, attribute: kAXMinimizedAttribute as CFString) == false
            }
        }
        if let next = appWithVisible ?? apps.first {
            next.activate(options: .activateIgnoringOtherApps)
        } else {
            NSApp.deactivate()
        }
    }

    private func minimizeAllApps() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        frontmostBeforeMinimize = NSWorkspace.shared.frontmostApplication
        let frontPID = frontmostBeforeMinimize?.processIdentifier ?? 0

        var backWindows:  [AXUIElement] = []
        var frontWindows: [AXUIElement] = []

        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != myPID {
            for w in windows(for: app.processIdentifier) {
                guard axBool(w, attribute: kAXMinimizedAttribute as CFString) == false else { continue }
                if let f = axFrame(w), f.width < 1 || f.height < 1 { continue }
                if app.processIdentifier == frontPID {
                    frontWindows.append(w)
                } else {
                    backWindows.append(w)
                }
            }
        }

        var minimizedNow: [AXUIElement] = []
        for w in backWindows + frontWindows {
            if setAXBool(w, attribute: kAXMinimizedAttribute as CFString, value: true) {
                minimizedNow.append(w)
            }
        }
        lastMinimizedWindows = minimizedNow

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.finder" }?
                .activate(options: .activateIgnoringOtherApps)
        }
    }

    private func restoreMinimizedApps() {
        pruneStaleMinimizedWindows()
        guard !lastMinimizedWindows.isEmpty else { return }

        let toRestore   = lastMinimizedWindows.reversed()
        let savedFront  = frontmostBeforeMinimize

        for (idx, w) in toRestore.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.03) {
                _ = self.setAXBool(w, attribute: kAXMinimizedAttribute as CFString, value: false)
            }
        }

        let totalDelay = Double(lastMinimizedWindows.count) * 0.03 + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            if let app = savedFront, !app.isTerminated {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }

        lastMinimizedWindows.removeAll()
        frontmostBeforeMinimize = nil
    }

    private func maximize() {
        guard let w = targetWindow() else { return }
        pruneOrphanedFrames()
        if axBool(w, attribute: kAXMinimizedAttribute as CFString) == true {
            _ = setAXBool(w, attribute: kAXMinimizedAttribute as CFString, value: false)
        }
        if !isWindowMaximized(w), let frame = axFrame(w) {
            savedFrames[windowKey(for: w)] = frame
        }
        guard let screen = screen(for: w) else { return }
        setFrame(w, axFrame(fromVisibleFrame: screen.visibleFrame))
    }

    private func restore() {
        guard let w = targetWindow() else { return }
        if axBool(w, attribute: kAXMinimizedAttribute as CFString) == true {
            _ = setAXBool(w, attribute: kAXMinimizedAttribute as CFString, value: false)
            return
        }
        if isWindowMaximized(w) {
            let key = windowKey(for: w)
            if let saved = savedFrames.removeValue(forKey: key) {
                setFrame(w, saved)
            } else if let fallback = defaultRestoredFrame(for: w) {
                setFrame(w, fallback)
            }
        } else {
            minimize(window: w)
        }
    }

    private func closeWindow() {
        guard let w = targetWindow() else { return }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, kAXCloseButtonAttribute as CFString, &ref) == .success,
           let btn = axElement(from: ref) {
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
        }
    }

    private func setFullscreen(_ targetState: Bool?) {
        guard let w = targetWindow() else { return }
        if axBool(w, attribute: kAXMinimizedAttribute as CFString) == true {
            _ = setAXBool(w, attribute: kAXMinimizedAttribute as CFString, value: false)
        }
        let isFS = axBool(w, attribute: "AXFullScreen" as CFString) ?? false
        let next = targetState ?? !isFS
        guard next != isFS else { return }
        _ = setAXBool(w, attribute: "AXFullScreen" as CFString, value: next)
    }

    // MARK: - Snapping

    private func snap(_ fraction: CGRect) {
        guard let w = targetWindow() else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let mainH = globalScreenMaxY()
        let vf    = screen.visibleFrame
        let x  = vf.minX + vf.width  * fraction.minX
        let y  = vf.minY + vf.height * fraction.minY
        let sw = vf.width  * fraction.width
        let sh = vf.height * fraction.height
        setFrame(w, CGRect(x: x, y: mainH - (y + sh), width: sw, height: sh))
    }

    private func centerWindow() {
        guard let w = targetWindow(), let f = axFrame(w) else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let mainH = globalScreenMaxY()
        let vf    = screen.visibleFrame
        let cx    = vf.minX + (vf.width  - f.width)  / 2
        let cy    = vf.minY + (vf.height - f.height) / 2
        var pos   = CGPoint(x: cx, y: mainH - cy - f.height)
        if let pr = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pr)
        }
    }

    private func moveToNextDisplay() {
        guard let w = targetWindow(), NSScreen.screens.count > 1, let f = axFrame(w) else { return }
        let mainH     = globalScreenMaxY()
        let cocoaY    = mainH - f.minY - f.height
        let winCentre = CGPoint(x: f.midX, y: cocoaY + f.height / 2)
        let screens   = NSScreen.screens
        guard let curIdx = screens.firstIndex(where: { $0.frame.contains(winCentre) }) else { return }
        let cur  = screens[curIdx]
        let next = screens[(curIdx + 1) % screens.count]
        let relX = (f.minX - cur.frame.minX) / cur.frame.width
        let relY = (cocoaY - cur.frame.minY) / cur.frame.height
        let nx   = next.frame.minX + relX * next.frame.width
        let ny   = next.frame.minY + relY * next.frame.height
        var pos  = CGPoint(x: nx, y: mainH - ny - f.height)
        if let pr = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pr)
        }
    }

    // MARK: - App switching

    private func activateAdjacentApp(forward: Bool) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        guard let cur = NSWorkspace.shared.frontmostApplication,
              let idx = apps.firstIndex(where: { $0.processIdentifier == cur.processIdentifier }) else { return }
        let next = forward
            ? apps[(idx + 1) % apps.count]
            : apps[(idx + apps.count - 1) % apps.count]
        next.activate(options: .activateIgnoringOtherApps)
    }

    // MARK: - System actions

    private func lockScreen() {
        // Try private Login framework
        if let h = dlopen("/System/Library/PrivateFrameworks/Login.framework/Versions/Current/Login", RTLD_LAZY) {
            defer { dlclose(h) }
            if let sym = dlsym(h, "SACLockScreenImmediate") {
                typealias Fn = @convention(c) () -> Void
                unsafeBitCast(sym, to: Fn.self)()
                return
            }
        }
        sendKey(0x0C, [.maskCommand, .maskControl])   // Ctrl+Cmd+Q fallback
    }

    private func sleepSystem() {
        // FIX: IOPMFindPowerManagement returns a send right — must release with IOServiceClose.
        let port = IOPMFindPowerManagement(mach_port_t(0))
        guard port != 0 else { return }
        IOPMSleepSystem(port)
        IOServiceClose(port)   // release the Mach send right to prevent port leak
    }

    // MARK: - AX helpers

    private func axFrame(_ w: AXUIElement) -> CGRect? {
        var pr: CFTypeRef?, sr: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pr)
        AXUIElementCopyAttributeValue(w, kAXSizeAttribute     as CFString, &sr)
        guard let pv = axValue(from: pr), let sv = axValue(from: sr) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(pv, .cgPoint, &pos), AXValueGetValue(sv, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    private func setFrame(_ w: AXUIElement, _ frame: CGRect) {
        var pos  = frame.origin; var size = frame.size
        if let pr = AXValueCreate(.cgPoint, &pos)  { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pr) }
        if let sr = AXValueCreate(.cgSize,  &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute     as CFString, sr) }
    }

    private func axBool(_ e: AXUIElement, attribute: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute, &ref) == .success else { return nil }
        return ref as? Bool
    }

    @discardableResult
    private func setAXBool(_ e: AXUIElement, attribute: CFString, value: Bool) -> Bool {
        AXUIElementSetAttributeValue(e, attribute, value as CFTypeRef) == .success
    }

    private func axValue(from ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXValue.self)
    }

    private func axElement(from ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    private func windowKey(for w: AXUIElement) -> WindowKey {
        var pid: pid_t = 0
        AXUIElementGetPid(w, &pid)
        return WindowKey(pid: pid, identity: Int(CFHash(w)))
    }

    private func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { return [] }
        return wins
    }

    private func pid(for element: AXUIElement) -> pid_t? {
        var p: pid_t = 0
        guard AXUIElementGetPid(element, &p) == .success else { return nil }
        return p
    }

    private func screen(for window: AXUIElement) -> NSScreen? {
        guard let frame = axFrame(window) else { return NSScreen.main }
        let cocoa  = cocoaFrame(fromAXFrame: frame)
        let center = CGPoint(x: cocoa.midX, y: cocoa.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
    }

    private func defaultRestoredFrame(for window: AXUIElement) -> CGRect? {
        guard let screen = screen(for: window) else { return nil }
        let vf = screen.visibleFrame
        let w  = vf.width * 0.7; let h = vf.height * 0.7
        return axFrame(fromVisibleFrame: CGRect(
            x: vf.minX + (vf.width - w) / 2,
            y: vf.minY + (vf.height - h) / 2,
            width: w, height: h))
    }

    private func pruneStaleMinimizedWindows(for pid: pid_t? = nil) {
        lastMinimizedWindows.removeAll { w in
            if let pid, self.pid(for: w) == pid { return true }
            return axBool(w, attribute: kAXMinimizedAttribute as CFString) != true
        }
    }

    func isApplicationMinimized(_ app: NSRunningApplication) -> Bool {
        windows(for: app.processIdentifier).contains {
            axBool($0, attribute: kAXMinimizedAttribute as CFString) == true
        }
    }

    // MARK: - Coordinate conversion

    private func globalScreenMaxY() -> CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
    }

    private func quartzPoint(from cocoaPoint: CGPoint) -> CGPoint {
        CGPoint(x: cocoaPoint.x, y: globalScreenMaxY() - cocoaPoint.y)
    }

    private func cocoaFrame(fromAXFrame frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: globalScreenMaxY() - frame.maxY,
               width: frame.width, height: frame.height)
    }

    private func axFrame(fromVisibleFrame frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: globalScreenMaxY() - frame.maxY,
               width: frame.width, height: frame.height)
    }

    // MARK: - Key event helper

    func executeKeyboardSteps(_ steps: [KeyboardInputStep]) {
        guard !steps.isEmpty else { return }
        for step in steps {
            switch step.event {
            case .hold:
                syntheticHeldFlags.insert(modifierFlag(for: step.keyCode))
                sendKeyDown(CGKeyCode(step.keyCode), syntheticHeldFlags)
            case .release:
                let releasedFlag = modifierFlag(for: step.keyCode)
                if releasedFlag.isEmpty {
                    sendKeyUp(CGKeyCode(step.keyCode), syntheticHeldFlags)
                } else {
                    syntheticHeldFlags.remove(releasedFlag)
                    sendKeyUp(CGKeyCode(step.keyCode), syntheticHeldFlags)
                }
            case .tap:
                sendKey(CGKeyCode(step.keyCode), syntheticHeldFlags.union(step.modifierFlags))
            }
        }
    }

    private func sendKey(_ key: CGKeyCode, _ flags: CGEventFlags) {
        guard let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState),
              let kd = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let ku = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
        kd.flags = flags; kd.post(tap: .cghidEventTap)
        ku.flags = flags; ku.post(tap: .cghidEventTap)
    }

    private func sendKeyDown(_ key: CGKeyCode, _ flags: CGEventFlags) {
        guard let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func sendKeyUp(_ key: CGKeyCode, _ flags: CGEventFlags) {
        guard let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func modifierFlag(for keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case 0x36, 0x37: return .maskCommand
        case 0x38: return .maskShift
        case 0x3A: return .maskAlternate
        case 0x3B: return .maskControl
        default: return []
        }
    }

}
