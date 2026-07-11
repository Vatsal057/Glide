import Cocoa
import CoreGraphics
import Darwin
import IOKit.pwr_mgt

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
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        guard let cur = NSWorkspace.shared.frontmostApplication,
              let idx = apps.firstIndex(where: { $0.processIdentifier == cur.processIdentifier }) else { return }
        let next = forward
            ? apps[(idx + 1) % apps.count]
            : apps[(idx + apps.count - 1) % apps.count]
        next.activate(options: .activateIgnoringOtherApps)
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

    func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { return [] }
        return wins
    }

    func hasRealWindow(for pid: pid_t) -> Bool {
        windows(for: pid).contains { window in
            guard axRole(window) == (kAXWindowRole as String) else { return false }
            if let subrole = axSubrole(window) {
                return subrole == (kAXStandardWindowSubrole as String)
                    || subrole == (kAXDialogSubrole as String)
                    || subrole == (kAXSystemDialogSubrole as String)
            }
            guard let frame = axFrame(window), frame.width >= 40, frame.height >= 40 else { return false }
            return true
        }
    }

    func finderHasAnyWindow() -> Bool {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) else {
            return false
        }
        // CGWindowList sees windows in every Space and minimized ones, and needs no
        // Automation permission. AX (kAXWindowsAttribute) misses other-Space windows,
        // so it's only a last resort.
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return hasRealWindow(for: finder.processIdentifier)
        }
        let pid = Int(finder.processIdentifier)
        return info.contains { win in
            guard win[kCGWindowOwnerPID as String] as? Int == pid,
                  win[kCGWindowLayer as String] as? Int == 0,
                  (win[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return false }
            // Finder always owns helper windows even with nothing open — observed:
            // full-width 1728×33 strips and a 64×64 proxy. Real Finder windows can't
            // go below ~344×236, so a generous 150×100 floor separates them cleanly.
            return bounds.width >= 150 && bounds.height >= 100
        }
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

}
