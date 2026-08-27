import Cocoa
import CoreGraphics
import Darwin
import IOKit.pwr_mgt

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ idOut: inout UInt32) -> AXError

// ─────────────────────────────────────────────
// MARK: - ActionExecutor
// ─────────────────────────────────────────────

final class WindowTargeting {

    static let shared = WindowTargeting()
    private init() {}

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

    // MARK: - Minimize / Restore state

    private struct MinimizedWindowRecord {
        let window: AXUIElement
        let pid: pid_t
    }

    private struct MinimizeAllSession {
        /// Only windows that were visible *before* the gesture (we minimized them).
        var windows: [MinimizedWindowRecord]
        let frontmostPID: pid_t?
        /// PIDs that were already minimized before we ran — we leave those alone.
        let preMinimizedPIDs: Set<pid_t>
    }

    private var minimizeAllSession: MinimizeAllSession?
    /// Tracks in-flight async work so we can cancel a restore if minimize fires again.
    private var pendingRestoreWorkItems: [DispatchWorkItem] = []

    // MARK: - App under cursor

    func quitAppAtCursor(_ location: NSPoint) {
        guard let pid = pidAtLocation(location) else { return }
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    func forceQuitAtCursor() {
        guard let pid = pidAtLocation(NSEvent.mouseLocation) else { return }
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
        activateAnotherApp(excluding: pid)
    }

    func hideAppAtCursor(othersOnly: Bool = false) {
        guard let pid = pidAtLocation(NSEvent.mouseLocation) else { return }
        if othersOnly {
            NSRunningApplication(processIdentifier: pid)?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                KeyboardEmulator.shared.sendKey(0x04, [.maskCommand, .maskAlternate])
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

    func openApp(path: String) {
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

    func minimizeFocused() {
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

    func minimizeAllApps() {
        // Cancel any in-flight restore work so minimize always wins.
        pendingRestoreWorkItems.forEach { $0.cancel() }
        pendingRestoreWorkItems = []

        let myPID    = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Snapshot which PIDs already had every window minimized — don't record those,
        // so we don't accidentally un-minimize them on restore.
        var preMinimizedPIDs = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != myPID {
            let wins = windows(for: app.processIdentifier)
            if !wins.isEmpty && wins.allSatisfy({ axBool($0, attribute: kAXMinimizedAttribute as CFString) == true }) {
                preMinimizedPIDs.insert(app.processIdentifier)
            }
        }

        var backWindows:  [MinimizedWindowRecord] = []
        var frontWindows: [MinimizedWindowRecord] = []

        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular
               && app.processIdentifier != myPID
               && !preMinimizedPIDs.contains(app.processIdentifier) {
            for w in windows(for: app.processIdentifier) {
                guard shouldMinimizeWindow(w) else { continue }
                let record = MinimizedWindowRecord(window: w, pid: app.processIdentifier)
                if app.processIdentifier == frontPID {
                    frontWindows.append(record)
                } else {
                    backWindows.append(record)
                }
            }
        }

        // Send all minimize commands at once — macOS handles concurrent AX writes
        // fine and all windows animate simultaneously (like Show Desktop).
        let ordered = backWindows + frontWindows
        for record in ordered {
            setAXBool(record.window, attribute: kAXMinimizedAttribute as CFString, value: true)
        }

        if !ordered.isEmpty {
            minimizeAllSession = MinimizeAllSession(
                windows: ordered,
                frontmostPID: frontPID,
                preMinimizedPIDs: preMinimizedPIDs
            )
        }

        // After animations finish, surface the Finder / Desktop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.finder" }?
                .activate(options: .activateIgnoringOtherApps)
        }
    }

    func restoreMinimizedApps() {
        pruneStaleMinimizedWindows()
        guard let session = minimizeAllSession, !session.windows.isEmpty else { return }

        // Clear immediately so a rapid second gesture can start fresh.
        minimizeAllSession = nil

        // Cancel any previous in-flight restore (shouldn't normally happen, but be safe).
        pendingRestoreWorkItems.forEach { $0.cancel() }
        pendingRestoreWorkItems = []

        // Restore in reverse order (frontmost app's windows come back on top).
        let toRestore    = session.windows.reversed()
        let frontmostPID = session.frontmostPID

        for (idx, record) in toRestore.enumerated() {
            let item = DispatchWorkItem {
                _ = self.setAXBool(record.window, attribute: kAXMinimizedAttribute as CFString, value: false)
            }
            pendingRestoreWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.04, execute: item)
        }

        // Activate the previously-frontmost app once all animations have settled.
        let totalDelay = Double(toRestore.count) * 0.04 + 0.12
        let activateItem = DispatchWorkItem {
            if let pid = frontmostPID,
               let app = NSRunningApplication(processIdentifier: pid),
               !app.isTerminated {
                app.activate(options: .activateIgnoringOtherApps)
            }
            // Clear work-item list when fully done.
            self.pendingRestoreWorkItems.removeAll()
        }
        pendingRestoreWorkItems.append(activateItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay, execute: activateItem)
    }

    /// Unminimizes every minimized window of the given app (app-switcher commit).
    func unminimizeWindows(of pid: pid_t) {
        for w in windows(for: pid) where axBool(w, attribute: kAXMinimizedAttribute as CFString) == true {
            setAXBool(w, attribute: kAXMinimizedAttribute as CFString, value: false)
        }
    }

    func maximize() {
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

    func restore() {
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

    func closeWindow() {
        guard let w = targetWindow() else { return }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, kAXCloseButtonAttribute as CFString, &ref) == .success,
           let btn = axElement(from: ref) {
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
        }
    }

    func setFullscreen(_ targetState: Bool?) {
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

    func snap(_ fraction: CGRect) {
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

    func centerWindow() {
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

    func moveToNextDisplay() {
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

    func activateAdjacentApp(forward: Bool) {
        // MRU order (same as the switcher) — raw runningApplications is launch order
        // and shifts as apps come and go, making "next app" unpredictable.
        let apps = AppSwitcherState.shared.getOrderedApps()
        guard apps.count > 1, let cur = NSWorkspace.shared.frontmostApplication,
              let idx = apps.firstIndex(where: { $0.processIdentifier == cur.processIdentifier }) else { return }
        let next = forward
            ? apps[(idx + 1) % apps.count]
            : apps[(idx + apps.count - 1) % apps.count]
            
        if let window = windows(for: next.processIdentifier).first {
            focus(window: window)
        } else {
            next.activate(options: .activateIgnoringOtherApps)
        }
    }

    func focus(window: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid > 0 else { return }

        var windowID: UInt32 = 0
        if _AXUIElementGetWindow(window, &windowID) == .success && windowID > 0 {
            if GLDWFocusWindow(pid, windowID) {
                return
            }
        }
        
        // Fallback if C-bridge fails or private API is unavailable
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
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

    private func axRole(_ e: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func axSubrole(_ e: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
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

    /// The first Accessibility request to a process pays a one-off connection
    /// handshake — measured at ~40ms per application, ~250ms across a typical set.
    /// Paying that on the first switcher open is exactly the quarter-second stall
    /// the panel must not have, so it is paid in the background ahead of time.
    /// Every later request to the same process costs well under a millisecond.
    func warmAccessibilityConnection(for pid: pid_t) {
        DispatchQueue.global(qos: .utility).async { _ = self.windows(for: pid) }
    }

    func warmAccessibilityConnections() {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map(\.processIdentifier)
        DispatchQueue.global(qos: .utility).async {
            for pid in pids { _ = self.windows(for: pid) }
        }
    }

    func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { return [] }
        return wins
    }

    /// One pass over the window manager, shared by every application in a switcher
    /// open. Accessibility only ever describes windows on the active Space, so the
    /// set of windows that exist — and whether each is on this Space or merely
    /// ordered out — comes from the WindowServer instead.
    private struct WindowServerSnapshot {
        /// Front-to-back, per owning process. Layer 0 and at least 40×40, so menus,
        /// tooltips, shadows and status items never reach the switcher.
        var idsByProcess: [pid_t: [CGWindowID]] = [:]
        var sizes: [CGWindowID: CGSize] = [:]
        var titles: [CGWindowID: String] = [:]
        var onCurrentSpace: Set<CGWindowID> = []
        var orderedIn: Set<CGWindowID> = []
    }

    private func copyWindowServerIDs(currentSpaceOnly: Bool, orderedInOnly: Bool) -> Set<CGWindowID>? {
        guard let unmanaged = GLDWCopyWindowIDs(currentSpaceOnly, orderedInOnly) else { return nil }
        let ids = unmanaged.takeRetainedValue() as NSArray
        return Set(ids.compactMap { ($0 as? NSNumber).map { CGWindowID($0.uint32Value) } })
    }

    private func windowServerSnapshot() -> WindowServerSnapshot {
        var snapshot = WindowServerSnapshot()
        // nil means the private symbols are gone (a future macOS). Everything then
        // falls back to the on-screen flag, which only sees the active Space —
        // the old behaviour, rather than an empty switcher.
        let managed = copyWindowServerIDs(currentSpaceOnly: false, orderedInOnly: false)
        let current = copyWindowServerIDs(currentSpaceOnly: true, orderedInOnly: false)
        let ordered = copyWindowServerIDs(currentSpaceOnly: false, orderedInOnly: true)
        // An empty answer is treated as no answer: reporting every window as
        // "another Space" would be worse than the pre-Spaces heuristic.
        let useOnscreenFlag = managed == nil || current?.isEmpty != false
        snapshot.onCurrentSpace = current ?? []
        snapshot.orderedIn = ordered ?? []

        guard let info = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return snapshot }

        for row in info {
            guard let pidNumber = row[kCGWindowOwnerPID as String] as? NSNumber,
                  let layerNumber = row[kCGWindowLayer as String] as? NSNumber,
                  layerNumber.intValue == 0,
                  let idNumber = row[kCGWindowNumber as String] as? NSNumber,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any] else { continue }
            let size = CGSize(
                width: (bounds["Width"] as? NSNumber)?.doubleValue ?? 0,
                height: (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            )
            guard size.width >= 40, size.height >= 40 else { continue }

            let id = CGWindowID(idNumber.uint32Value)
            // The window manager knows which of an application's surfaces are real
            // windows; Core Graphics also lists hidden scratch windows that no
            // switcher should offer.
            if let managed, !managed.contains(id) { continue }
            if useOnscreenFlag,
               (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true {
                snapshot.onCurrentSpace.insert(id)
            }
            if ordered == nil { snapshot.orderedIn.insert(id) }
            snapshot.idsByProcess[pidNumber.int32Value, default: []].append(id)
            snapshot.sizes[id] = size
            // Only populated when the user has granted Screen Recording; used as a
            // title of last resort for windows Accessibility cannot describe.
            if let name = row[kCGWindowName as String] as? String, !name.isEmpty {
                snapshot.titles[id] = name
            }
        }
        return snapshot
    }

    func switcherWindows(for apps: [NSRunningApplication]) -> [[AppSwitcherWindow]] {
        let snapshot = windowServerSnapshot()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        return apps.map { app in
            let windowIDs = snapshot.idsByProcess[app.processIdentifier] ?? []
            guard !windowIDs.isEmpty else { return [] }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.1)
            var focusedRef: CFTypeRef?
            let focusedWindow: AXUIElement? = {
                guard AXUIElementCopyAttributeValue(
                    appElement,
                    kAXFocusedWindowAttribute as CFString,
                    &focusedRef
                ) == .success else { return nil }
                return axElement(from: focusedRef)
            }()
            let focusedID = focusedWindow.flatMap(cgWindowID)

            var elementsByID: [CGWindowID: AXUIElement] = [:]
            for window in windows(for: app.processIdentifier) {
                if let id = cgWindowID(for: window) { elementsByID[id] = window }
            }

            var result = windowIDs.compactMap { windowID -> AppSwitcherWindow? in
                let element = elementsByID[windowID]
                let isOrderedIn = snapshot.orderedIn.contains(windowID)
                guard isSwitcherWindow(
                    element,
                    isOrderedIn: isOrderedIn,
                    size: snapshot.sizes[windowID] ?? .zero
                ) else { return nil }
                let axTitle = element
                    .flatMap { axString($0, attribute: kAXTitleAttribute as CFString) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = [axTitle, snapshot.titles[windowID], app.localizedName]
                    .compactMap { $0 }
                    .first { !$0.isEmpty }
                return AppSwitcherWindow(
                    id: Int(windowID),
                    processIdentifier: app.processIdentifier,
                    windowID: windowID,
                    element: element,
                    title: title ?? "Untitled Window",
                    isMinimized: element.map { axBool($0, attribute: kAXMinimizedAttribute as CFString) == true }
                        ?? false,
                    isOnCurrentSpace: snapshot.onCurrentSpace.contains(windowID),
                    isApplicationHidden: app.isHidden
                )
            }

            if let focusedID,
               let index = result.firstIndex(where: { $0.windowID == focusedID }) {
                let focused = result.remove(at: index)
                if app.processIdentifier == frontmostPID, !result.isEmpty {
                    // Returning to the app you are already using should pick its
                    // alternate window first, mirroring the intent of ⌘`.
                    result.append(focused)
                } else {
                    result.insert(focused, at: 0)
                }
            }
            return result
        }
    }

    func activateSwitcherWindow(_ window: AppSwitcherWindow, in app: NSRunningApplication) {
        app.unhide()
        if window.isMinimized, let element = window.element {
            _ = setAXBool(element, attribute: kAXMinimizedAttribute as CFString, value: false)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        func focus(_ element: AXUIElement?) {
            guard let element else { return }
            AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, element)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }

        // Claim the exact target before activating the process. A successful
        // WindowServer focus alone does not guarantee that macOS moves to the
        // target's Space, so it must never short-circuit this sequence.
        focus(window.element)
        app.activate(options: .activateIgnoringOtherApps)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self else { return }
            let element = window.element ?? window.windowID.flatMap { targetID in
                self.windows(for: app.processIdentifier).first { candidate in
                    self.cgWindowID(for: candidate) == targetID
                }
            }
            focus(element)
            if let windowID = window.windowID {
                _ = GLDWFocusWindow(app.processIdentifier, windowID)
            }

            // The app activation and Space transition are asynchronous. Reapply
            // the AX focus after the transition so macOS cannot fall back to the
            // application's most recently focused window on another Space.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                focus(element)
            }
        }
    }

    private func cgWindowID(for window: AXUIElement) -> CGWindowID? {
        var windowID: UInt32 = 0
        return _AXUIElementGetWindow(window, &windowID) == .success ? windowID : nil
    }

    private func axString(_ element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
    }

    /// The switcher represents document-style windows, not sheets, dialogs, or
    /// floating panels. Window management actions are deliberately more permissive,
    /// since they legitimately operate on dialogs.
    ///
    /// A window with no AX element lives on another Space (or its application
    /// refuses Accessibility): the WindowServer is then the only witness, and it
    /// only vouches for windows that are ordered in.
    private func isSwitcherWindow(_ window: AXUIElement?, isOrderedIn: Bool, size: CGSize) -> Bool {
        guard let window else {
            // Nothing can report a subrole here, so shape stands in for it. A
            // full-screen Space adds a display-wide title strip alongside the real
            // window; no document window is that letterboxed.
            return isOrderedIn && size.width >= 200 && size.height >= 100
        }
        guard axRole(window) == (kAXWindowRole as String) else { return false }
        // Subrole degrades to AXDialog while a window is ordered out — minimized,
        // or its application hidden — so it only means anything while ordered in.
        guard isOrderedIn, let subrole = axSubrole(window) else { return true }
        return subrole == (kAXStandardWindowSubrole as String)
    }

    private func shouldMinimizeWindow(_ window: AXUIElement) -> Bool {
        guard axBool(window, attribute: kAXMinimizedAttribute as CFString) == false else { return false }
        guard axBool(window, attribute: "AXFullScreen" as CFString) != true else { return false }
        guard let frame = axFrame(window), frame.width >= 1, frame.height >= 1 else { return false }
        return true
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

    private func pruneStaleMinimizedWindows() {
        guard var session = minimizeAllSession else { return }
        session.windows.removeAll { record in
            // Drop if the app has quit.
            if NSRunningApplication(processIdentifier: record.pid)?.isTerminated == true { return true }
            // Drop if the window is no longer minimized (e.g. user manually restored it).
            return axBool(record.window, attribute: kAXMinimizedAttribute as CFString) != true
        }
        if session.windows.isEmpty {
            minimizeAllSession = nil
        } else {
            minimizeAllSession = session
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

}
