import Cocoa
import CoreGraphics
import Darwin
import IOKit.pwr_mgt

// ─────────────────────────────────────────────
// MARK: - ActionExecutor
// ─────────────────────────────────────────────

final class ActionExecutor {

    private struct WindowKey: Hashable {
        let pid: pid_t
        let identity: Int
    }

    static let shared = ActionExecutor()
    private init() {}
    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)

    // Saved frames for maximize/restore
    private var savedFrames: [WindowKey: CGRect] = [:]
    var hasRestorableMinimizedApps: Bool {
        pruneStaleMinimizedWindows()
        return !lastMinimizedWindows.isEmpty
    }

    private var lastMinimizedWindows: [AXUIElement] = []

    /// Removes savedFrames entries for PIDs that are no longer in the running app list.
    /// Called lazily from maximize() rather than on a timer to avoid background overhead.
    /// Only runs when savedFrames exceeds 20 entries (typical sessions accumulate far fewer).
    private func pruneOrphanedFrames() {
        guard savedFrames.count > 20 else { return }
        let runningPIDs = Set(
            NSWorkspace.shared.runningApplications.map { $0.processIdentifier }
        )
        savedFrames = savedFrames.filter { runningPIDs.contains($0.key.pid) }
    }

    func pruneSavedFrame(for pid: pid_t) {
        savedFrames = savedFrames.filter { $0.key.pid != pid }
        pruneStaleMinimizedWindows(for: pid)
    }

    // MARK: Dispatch

    func execute(_ action: GestureAction, appPath: String? = nil) {
        AppLogger.debug("[Action] Executing: \(action.rawValue)")
        switch action {

        // ── App lifecycle ──────────────────────────────────────────────────
        case .quitApp:
            quitAppAtCursor(NSEvent.mouseLocation)
        case .forceQuitApp:
            forceQuitAtCursor()
        case .quitFrontmost:
            NSWorkspace.shared.frontmostApplication?.terminate()
        case .hideApp:
            hideAppAtCursor()
        case .hideOthers:
            hideAppAtCursor(othersOnly: true)
        case .openApp:
            if let path = appPath { openApp(path: path) }

        // ── App switching ──────────────────────────────────────────────────
        // These are handled directly in GestureEngine for continuous scrolling.
        // But if mapped as a one-shot, fire once.
        case .appSwitcherNext:
            sendKey(0x30, .maskCommand)    // Cmd+Tab
        case .appSwitcherPrev:
            sendKey(0x30, [.maskCommand, .maskShift])
        case .switchAppNext:
            activateAdjacentApp(forward: true)
        case .switchAppPrev:
            activateAdjacentApp(forward: false)

        // ── Window state ──────────────────────────────────────────────────
        case .minimizeWindow:
            minimizeFocused()
        case .minimizeAllApps:
            minimizeAllApps()
        case .restoreMinimizedApps:
            restoreMinimizedApps()
        case .maximizeWindow:
            maximize(windowAtCursor: true)
        case .restoreWindow:
            restore(windowAtCursor: true)
        case .closeWindow:
            closeWindow()
        case .enterFullscreen:
            setFullscreen(true)
        case .exitFullscreen:
            setFullscreen(false)
        case .toggleFullscreen:
            setFullscreen(nil)
        case .cycleWindows:
            sendKey(0x32, .maskCommand)    // Cmd+`

        // ── Window snapping ───────────────────────────────────────────────
        case .snapLeft:         snap(CGRect(x: 0,   y: 0,   width: 0.5, height: 1))
        case .snapRight:        snap(CGRect(x: 0.5, y: 0,   width: 0.5, height: 1))
        case .snapTopLeft:      snap(CGRect(x: 0,   y: 0.5, width: 0.5, height: 0.5))
        case .snapTopRight:     snap(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        case .snapBottomLeft:   snap(CGRect(x: 0,   y: 0,   width: 0.5, height: 0.5))
        case .snapBottomRight:  snap(CGRect(x: 0.5, y: 0,   width: 0.5, height: 0.5))
        case .centerWindow:     centerWindow()
        case .moveNextDisplay:  moveToNextDisplay()

        // ── System ────────────────────────────────────────────────────────
        case .missionControl:
            performMissionControl()
        case .appExpose:
            sendKey(125, .maskControl)
        case .showDesktop:
            sendKey(103, [])   // F11
        case .launchpad:
            sendKey(131, [])
        case .spotlight:
            sendKey(0x31, .maskCommand)    // Cmd+Space
        case .notifCenter:
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.notificationcenterui.dockControllerActivated"),
                object: nil, deliverImmediately: true)
        case .lockScreen:
            lockScreen()
        case .sleep:
            sleepSystem()
        case .screenshotArea:
            sendKey(0x15, [.maskCommand, .maskShift])   // Cmd+Shift+4
        case .screenshotFull:
            sendKey(0x14, [.maskCommand, .maskShift])   // Cmd+Shift+3

        case .doNothing:
            break
        }
    }

    private func performMissionControl() {
        guard let src = eventSource() else { return }
        let f3: CGKeyCode = 160 // Mission Control hardware key
        CGEvent(keyboardEventSource: src, virtualKey: f3, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: f3, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func eventSource() -> CGEventSource? {
        keyEventSource ?? CGEventSource(stateID: .hidSystemState)
    }

    // MARK: - App Under Cursor

    func quitAppAtCursor(_ location: NSPoint) {
        guard let pid = pidAtLocation(location) else {
            AppLogger.debug("[Action] quitApp — no window at cursor"); return
        }
        AppLogger.debug("[Action] Quitting PID \(pid)")
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    private func forceQuitAtCursor() {
        guard let pid = pidAtLocation(NSEvent.mouseLocation) else { return }
        AppLogger.debug("[Action] Force-quitting PID \(pid)")
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
        activateAnotherApp(excluding: pid)
    }

    private func hideAppAtCursor(othersOnly: Bool = false) {
        guard let pid = pidAtLocation(NSEvent.mouseLocation) else { return }
        if othersOnly {
            // Activate target, then Cmd+Opt+H
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
                .first { $0.activationPolicy == .regular && $0.processIdentifier != pid
                         && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate(options: .activateIgnoringOtherApps)
        }
    }

    private func openApp(path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: .init()) { _, _ in }
    }

    // MARK: - Window helpers

    /// AX element for the window topmost at the given screen-coordinate (Cocoa origin).
    func windowAtCursor(_ location: NSPoint? = nil) -> AXUIElement? {
        let mouse  = location ?? NSEvent.mouseLocation
        let cgPt   = quartzPoint(from: mouse)
        let myPID  = ProcessInfo.processInfo.processIdentifier

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

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
        let cgPt = quartzPoint(from: loc)
        let myPID = ProcessInfo.processInfo.processIdentifier

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

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

    private func axFrame(_ w: AXUIElement) -> CGRect? {
        var pr: CFTypeRef?, sr: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pr)
        AXUIElementCopyAttributeValue(w, kAXSizeAttribute     as CFString, &sr)
        guard let pv = axValue(from: pr), let sv = axValue(from: sr) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(pv, .cgPoint, &pos),
              AXValueGetValue(sv, .cgSize,  &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    private func setFrame(_ w: AXUIElement, _ frame: CGRect) {
        var pos  = frame.origin
        var size = frame.size
        if let pr = AXValueCreate(.cgPoint, &pos)  { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pr) }
        if let sr = AXValueCreate(.cgSize,  &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute     as CFString, sr) }
    }

    private func windowKey(for window: AXUIElement) -> WindowKey {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return WindowKey(pid: pid, identity: Int(CFHash(window)))
    }

    private func globalScreenMaxY() -> CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
    }

    private func quartzPoint(from cocoaPoint: CGPoint) -> CGPoint {
        CGPoint(x: cocoaPoint.x, y: globalScreenMaxY() - cocoaPoint.y)
    }

    private func cocoaFrame(fromAXFrame frame: CGRect) -> CGRect {
        let mainH = globalScreenMaxY()
        return CGRect(x: frame.minX, y: mainH - frame.maxY, width: frame.width, height: frame.height)
    }

    private func axFrame(fromVisibleFrame frame: CGRect) -> CGRect {
        let mainH = globalScreenMaxY()
        return CGRect(x: frame.minX, y: mainH - frame.maxY, width: frame.width, height: frame.height)
    }

    private func screen(for window: AXUIElement) -> NSScreen? {
        guard let frame = axFrame(window) else { return NSScreen.main }
        let cocoa = cocoaFrame(fromAXFrame: frame)
        let center = CGPoint(x: cocoa.midX, y: cocoa.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
    }

    private func targetWindow() -> AXUIElement? {
        switch Settings.shared.windowTargetingMode {
        case .focusedThenCursor:
            return focusedWindow() ?? windowAtCursor()
        case .cursorThenFocused:
            return windowAtCursor() ?? focusedWindow()
        }
    }

    func isFrontmostWindowFullscreen() -> Bool {
        guard let w = focusedWindow() else { return false }
        return axBool(w, attribute: "AXFullScreen" as CFString) ?? false
    }

    func isFrontmostWindowMaximized() -> Bool {
        guard let w = focusedWindow() else { return false }
        return isWindowMaximized(w)
    }

    internal func isWindowMaximized(_ window: AXUIElement) -> Bool {
        guard let frame = axFrame(window),
              let screen = screen(for: window) else { return false }

        let visible = axFrame(fromVisibleFrame: screen.visibleFrame)
        let tolerance: CGFloat = 16

        return abs(frame.minX - visible.minX) <= tolerance
            && abs(frame.minY - visible.minY) <= tolerance
            && abs(frame.width - visible.width) <= tolerance
            && abs(frame.height - visible.height) <= tolerance
    }

    private func defaultRestoredFrame(for window: AXUIElement) -> CGRect? {
        guard let screen = screen(for: window) else { return nil }
        let visible = screen.visibleFrame
        let width = visible.width * 0.7
        let height = visible.height * 0.7
        let x = visible.minX + (visible.width - width) / 2
        let y = visible.minY + (visible.height - height) / 2
        return axFrame(fromVisibleFrame: CGRect(x: x, y: y, width: width, height: height))
    }

    private func axBool(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? Bool
    }

    @discardableResult
    private func setAXBool(_ element: AXUIElement, attribute: CFString, value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute, value as CFTypeRef) == .success
    }

    private func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return [] }
        return windows
    }

    private func pid(for element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func axValue(from ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXValue.self)
    }

    private func axElement(from ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    private func pruneStaleMinimizedWindows(for pid: pid_t? = nil) {
        lastMinimizedWindows.removeAll { window in
            if let pid, self.pid(for: window) == pid {
                return true
            }
            return axBool(window, attribute: kAXMinimizedAttribute as CFString) != true
        }
    }

    func isApplicationMinimized(_ app: NSRunningApplication) -> Bool {
        for window in windows(for: app.processIdentifier) {
            if axBool(window, attribute: kAXMinimizedAttribute as CFString) == true {
                return true
            }
        }
        return false
    }

    private func focusedWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success else {
            return nil
        }
        return axElement(from: ref)
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

    /// Activates the next visible (non-minimized) regular app, excluding the given app.
    /// If no such app exists, deactivates everything.
    private func activateNextApp(excluding current: NSRunningApplication?) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
            && $0.processIdentifier != myPID
            && $0.processIdentifier != (current?.processIdentifier ?? 0)
            && !$0.isHidden
        }
        // Prefer apps that still have visible (non-minimized) windows
        let appWithVisible = apps.first { app in
            self.windows(for: app.processIdentifier).contains {
                self.axBool($0, attribute: kAXMinimizedAttribute as CFString) == false
            }
        }
        if let next = appWithVisible ?? apps.first {
            next.activate(options: .activateIgnoringOtherApps)
        } else {
            // Nothing to activate — step back to Finder or deactivate
            NSApp.deactivate()
        }
    }

    private func minimizeAllApps() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != myPID
        }

        var minimizedNow: [AXUIElement] = []
        for app in apps {
            for window in windows(for: app.processIdentifier) {
                guard axBool(window, attribute: kAXMinimizedAttribute as CFString) == false else { continue }
                if setAXBool(window, attribute: kAXMinimizedAttribute as CFString, value: true) {
                    minimizedNow.append(window)
                }
            }
        }

        lastMinimizedWindows = minimizedNow

        // All windows are now minimized — activate Finder so no user app is frontmost.
        // NSApp.deactivate() only affects Glide itself; we need to explicitly
        // hand focus to Finder, which is macOS's "desktop / no app" state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let finder = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.apple.finder"
            }) {
                finder.activate(options: .activateIgnoringOtherApps)
            }
        }
    }

    private func restoreMinimizedApps() {
        pruneStaleMinimizedWindows()
        guard !lastMinimizedWindows.isEmpty else { return }
        for window in lastMinimizedWindows {
            _ = setAXBool(window, attribute: kAXMinimizedAttribute as CFString, value: false)
        }
        lastMinimizedWindows.removeAll()
    }

    private func maximize(windowAtCursor: Bool) {
        _ = windowAtCursor
        let w = targetWindow()
        guard let w else { return }

        // FIX: Prune savedFrames entries for PIDs of apps that are no longer running.
        // Previously this dictionary grew unboundedly because pruneSavedFrame(pid:) was
        // only called when an app *terminated* — not when individual windows were closed.
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

    private func restore(windowAtCursor: Bool) {
        _ = windowAtCursor
        let w = targetWindow()
        guard let w else { return }

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
        let isFullscreen = axBool(w, attribute: "AXFullScreen" as CFString) ?? false
        let nextState = targetState ?? !isFullscreen
        guard nextState != isFullscreen else { return }
        _ = setAXBool(w, attribute: "AXFullScreen" as CFString, value: nextState)
    }

    // MARK: - Snapping

    private func snap(_ fraction: CGRect) {
        guard let w = targetWindow() else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = (NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main) else { return }
        let mainH = globalScreenMaxY()
        let vf    = screen.visibleFrame

        let x  = vf.minX + vf.width  * fraction.minX
        let y  = vf.minY + vf.height * fraction.minY
        let sw = vf.width  * fraction.width
        let sh = vf.height * fraction.height
        let cgY = mainH - (y + sh)

        setFrame(w, CGRect(x: x, y: cgY, width: sw, height: sh))
    }

    private func centerWindow() {
        guard let w = targetWindow() else { return }
        guard let f = axFrame(w) else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = (NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main) else { return }
        let mainH = globalScreenMaxY()
        let vf    = screen.visibleFrame
        let cx    = vf.minX + (vf.width  - f.width)  / 2
        let cy    = vf.minY + (vf.height - f.height) / 2
        let cgY   = mainH - cy - f.height
        var pos   = CGPoint(x: cx, y: cgY)
        if let pr = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pr) }
    }

    private func moveToNextDisplay() {
        guard let w = targetWindow() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1, let f = axFrame(w) else { return }
        let mainH = globalScreenMaxY()

        // Determine which screen the window is on
        let cocoaY  = mainH - f.minY - f.height
        let winCentre = CGPoint(x: f.midX, y: cocoaY + f.height / 2)
        guard let curIdx = screens.firstIndex(where: { $0.frame.contains(winCentre) }) else { return }
        let next = screens[(curIdx + 1) % screens.count]
        let cur  = screens[curIdx]

        // Relative position on current screen → same position on next
        let relX = (f.minX - cur.frame.minX) / cur.frame.width
        let relY = (cocoaY - cur.frame.minY) / cur.frame.height
        let nx   = next.frame.minX + relX * next.frame.width
        let ny   = next.frame.minY + relY * next.frame.height
        let cgY  = mainH - ny - f.height

        var pos = CGPoint(x: nx, y: cgY)
        if let pr = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pr) }
    }

    // MARK: - App switching (non-switcher)

    private func activateAdjacentApp(forward: Bool) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        guard let cur = NSWorkspace.shared.frontmostApplication,
              let idx = apps.firstIndex(where: { $0.processIdentifier == cur.processIdentifier }) else { return }
        let next = forward ? apps[(idx + 1) % apps.count] : apps[(idx + apps.count - 1) % apps.count]
        next.activate(options: .activateIgnoringOtherApps)
    }

    // MARK: - System

    private func lockScreen() {
        // Try private Login framework first
        if let h = dlopen("/System/Library/PrivateFrameworks/Login.framework/Versions/Current/Login", RTLD_LAZY) {
            defer { dlclose(h) }
            if let sym = dlsym(h, "SACLockScreenImmediate") {
                typealias Fn = @convention(c) () -> Void
                unsafeBitCast(sym, to: Fn.self)()
                return
            }
        }
        // Fallback: Ctrl+Cmd+Q
        sendKey(0x0C, [.maskCommand, .maskControl])
    }

    private func sleepSystem() {
        let port = IOPMFindPowerManagement(mach_port_t(0))
        guard port != 0 else { return }
        IOPMSleepSystem(port)
    }

    // MARK: - Key event helper

    private func sendKey(_ key: CGKeyCode, _ flags: CGEventFlags) {
        guard let src = eventSource(),
              let kd = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let ku = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
        kd.flags = flags
        kd.post(tap: .cghidEventTap)
        ku.flags = flags
        ku.post(tap: .cghidEventTap)
    }
}
