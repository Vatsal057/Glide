import Cocoa
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: - Menu item catalog
// ─────────────────────────────────────────────

struct MenuItemOption: Identifiable, Hashable {
    /// Full path segments, e.g. ["File", "New Tab"]
    let path: [String]
    var id: String { path.joined(separator: " › ") }
    var displayTitle: String { id }
}

struct MenuItemScanResult {
    let options: [MenuItemOption]
    let failureReason: String?
}

enum MenuItemCatalog {

    private static let pathSeparator = "\u{1E}"

    @MainActor
    static func scanAsync(bundleID: String?) async -> MenuItemScanResult {
        guard AXIsProcessTrusted() else {
            return MenuItemScanResult(
                options: [],
                failureReason: "Glide needs Accessibility access. Open System Settings → Privacy & Security → Accessibility and enable Glide."
            )
        }

        guard let app = resolveRunningApp(bundleID: bundleID) else {
            return MenuItemScanResult(
                options: [],
                failureReason: "The target app is not running. Open it, then click Refresh."
            )
        }

        app.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 250_000_000)

        let processName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let bundle = app.bundleIdentifier ?? ""
        let pid = app.processIdentifier

        let scanResult: MenuItemScanResult = await Task.detached(priority: .userInitiated) {
            if let fromScript = optionsViaAppleScript(processName: processName, bundleID: bundle), !fromScript.isEmpty {
                return MenuItemScanResult(
                    options: fromScript.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending },
                    failureReason: nil
                )
            }

            let fromAX = optionsViaAX(pid: pid)
            if !fromAX.isEmpty {
                return MenuItemScanResult(
                    options: fromAX.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending },
                    failureReason: nil
                )
            }

            return MenuItemScanResult(
                options: [],
                failureReason: """
                Could not read menus for \(processName).

                • Click Refresh with \(processName) open and in the foreground.
                • In System Settings → Privacy & Security → Automation, allow Glide to control System Events.
                • Some apps (including Electron apps) expose fewer menus until their menu bar is visible.
                """
            )
        }.value

        return scanResult
    }

    // MARK: - AppleScript (primary — works for Obsidian, Safari, Xcode, etc.)

    private static func optionsViaAppleScript(processName: String, bundleID: String) -> [MenuItemOption]? {
        let escapedName = escapeAppleScript(processName)
        let escapedBundle = escapeAppleScript(bundleID)
        let sep = pathSeparator

        let scriptSource = """
        set pathSep to "\(sep)"
        set results to {}

        tell application "System Events"
            set targetProc to missing value
            try
                if "\(escapedBundle)" is not "" then
                    set targetProc to first process whose bundle identifier is "\(escapedBundle)"
                end if
            end try
            if targetProc is missing value then
                try
                    set targetProc to first process whose name is "\(escapedName)"
                end try
            end if
            if targetProc is missing value then return results

            tell targetProc
                repeat with topMenu in menus of menu bar 1
                    set topName to name of topMenu
                    if topName is not missing value and topName is not "" then
                        my collectMenuItems(topMenu, topName, pathSep, results)
                    end if
                end repeat
            end tell
        end tell

        return results

        on collectMenuItems(theMenu, pathPrefix, pathSep, results)
            try
                repeat with mi in menu items of theMenu
                    try
                        set itemName to name of mi
                        if itemName is missing value or itemName is "" then
                            -- skip
                        else
                        set newPrefix to pathPrefix & pathSep & itemName
                        try
                            set subMenu to menu 1 of mi
                            my collectMenuItems(subMenu, newPrefix, pathSep, results)
                        on error
                            copy newPrefix to end of results
                        end try
                        end if
                    end try
                end repeat
            end try
        end collectMenuItems
        """

        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: scriptSource)?.executeAndReturnError(&error) else {
            if let error { AppLogger.debug("[MenuItem] AppleScript error: \(error)") }
            return nil
        }

        if descriptor.descriptorType == typeAEList {
            return parsePathListDescriptor(descriptor)
        }
        if let single = descriptor.stringValue {
            return parsePathLines([single])
        }
        return []
    }

    private static func parsePathListDescriptor(_ list: NSAppleEventDescriptor) -> [MenuItemOption] {
        var lines: [String] = []
        let count = list.numberOfItems
        guard count > 0 else { return [] }
        for i in 1...count {
            if let s = list.atIndex(i)?.stringValue { lines.append(s) }
        }
        return parsePathLines(lines)
    }

    private static func parsePathLines(_ lines: [String]) -> [MenuItemOption] {
        var seen = Set<String>()
        var options: [MenuItemOption] = []
        for line in lines {
            let parts = line.split(separator: "\u{1E}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { continue }
            let key = parts.joined(separator: "/")
            guard seen.insert(key).inserted else { continue }
            options.append(MenuItemOption(path: parts))
        }
        return options
    }

    // MARK: - Accessibility API (fallback)

    private static func optionsViaAX(pid: pid_t) -> [MenuItemOption] {
        let axApp = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = axElement(from: menuBarRef) else { return [] }

        var results: [MenuItemOption] = []
        for child in axChildren(menuBar) {
            let role = axRole(child) ?? ""
            if role == (kAXMenuBarItemRole as String) {
                guard let title = axTitle(child), !title.isEmpty,
                      let menu = axMenuForBarItem(child) else { continue }
                collectItems(in: menu, path: [title], into: &results)
            } else if role == (kAXMenuRole as String) {
                guard let title = axTitle(child), !title.isEmpty else { continue }
                collectItems(in: child, path: [title], into: &results)
            }
        }
        return results
    }

    private static func collectItems(in menu: AXUIElement, path: [String], into results: inout [MenuItemOption]) {
        for child in axChildren(menu) {
            guard let role = axRole(child) else { continue }
            let title = axTitle(child) ?? ""
            if title.isEmpty { continue }
            if axBool(child, kAXEnabledAttribute as CFString) == false { continue }

            if role == (kAXMenuItemRole as String) {
                let itemPath = path + [title]
                if let submenu = axSubmenu(child) {
                    collectItems(in: submenu, path: itemPath, into: &results)
                } else {
                    results.append(MenuItemOption(path: itemPath))
                }
            } else if role == (kAXMenuRole as String) {
                collectItems(in: child, path: path + [title], into: &results)
            }
        }
    }

    private static func resolveRunningApp(bundleID: String?) -> NSRunningApplication? {
        if let bundleID {
            return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
        }
        return NSWorkspace.shared.frontmostApplication.flatMap {
            $0.activationPolicy == .regular ? $0 : nil
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Shared AX helpers (catalog + executor)
// ─────────────────────────────────────────────

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
          let list = ref as? [AXUIElement] else { return [] }
    return list
}

private func axSubmenu(_ item: AXUIElement) -> AXUIElement? {
    axChildren(item).first { axRole($0) == (kAXMenuRole as String) }
}

private func axMenuForBarItem(_ item: AXUIElement) -> AXUIElement? {
    if let sub = axSubmenu(item) { return sub }
    var ref: CFTypeRef?
    if AXUIElementCopyAttributeValue(item, "AXMenu" as CFString, &ref) == .success {
        return axElement(from: ref)
    }
    return nil
}

private func axTitle(_ element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
    if let s = ref as? String, !s.isEmpty { return s }
    if let attr = ref as? NSAttributedString { return attr.string }
    return nil
}

private func axRole(_ element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
    return ref as? String
}

private func axBool(_ element: AXUIElement, _ attr: CFString) -> Bool? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
    return ref as? Bool
}

private func axElement(from ref: CFTypeRef?) -> AXUIElement? {
    guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(ref, to: AXUIElement.self)
}

private func escapeAppleScript(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
}

// ─────────────────────────────────────────────
// MARK: - Menu item execution (System Events)
// ─────────────────────────────────────────────

enum MenuItemExecutor {

    /// Clicks a menu item in the target app. `bundleID` nil uses the frontmost regular app.
    static func perform(path: [String], bundleID: String?) {
        guard path.count >= 2 else {
            AppLogger.debug("[MenuItem] Path too short: \(path)")
            return
        }
        let run = { performOnMain(path: path, bundleID: bundleID) }
        if Thread.isMainThread { run() }
        else { DispatchQueue.main.sync(execute: run) }
    }

    private static func performOnMain(path: [String], bundleID: String?) {
        guard let app = resolveApp(bundleID: bundleID) else {
            AppLogger.debug("[MenuItem] No target app for menu \(path.joined(separator: " › "))")
            return
        }

        app.activate(options: [.activateIgnoringOtherApps])
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))

        let pid = app.processIdentifier
        if performViaAX(path: path, pid: pid) {
            AppLogger.debug("[MenuItem] AX clicked \(path.joined(separator: " › "))")
            return
        }

        let processName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let bundle = app.bundleIdentifier ?? ""
        let clause = MenuItemCatalog.buildClickClause(path: path)
        runClickScript(processName: processName, bundleID: bundle, clause: clause, path: path)
    }

    /// Presses a menu item via Accessibility (no System Events automation required).
    private static func performViaAX(path: [String], pid: pid_t) -> Bool {
        guard path.count >= 2 else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = axElement(from: menuBarRef) else { return false }

        guard let topMenu = findMenuBarMenu(named: path[0], in: menuBar) else { return false }
        var currentMenu = topMenu
        var index = 1
        while index < path.count - 1 {
            guard let item = findMenuItem(named: path[index], in: currentMenu),
                  let submenu = axSubmenu(item) else { return false }
            _ = axPress(item)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            currentMenu = submenu
            index += 1
        }
        guard let leaf = findMenuItem(named: path[path.count - 1], in: currentMenu) else { return false }
        return axPress(leaf)
    }

    private static func titlesMatch(_ observed: String?, _ expected: String) -> Bool {
        guard let observed else { return false }
        if observed == expected { return true }
        let normObs = observed.replacingOccurrences(of: "...", with: "…")
        let normExp = expected.replacingOccurrences(of: "...", with: "…")
        return normObs == normExp
    }

    private static func findMenuBarMenu(named title: String, in menuBar: AXUIElement) -> AXUIElement? {
        for child in axChildren(menuBar) {
            if titlesMatch(axTitle(child), title) {
                if axRole(child) == (kAXMenuRole as String) { return child }
                if let menu = axMenuForBarItem(child) { return menu }
            }
        }
        return nil
    }

    private static func findMenuItem(named title: String, in menu: AXUIElement) -> AXUIElement? {
        for child in axChildren(menu) {
            guard axRole(child) == (kAXMenuItemRole as String) else { continue }
            if titlesMatch(axTitle(child), title) { return child }
        }
        return nil
    }

    private static func axPress(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func runClickScript(processName: String, bundleID: String, clause: String, path: [String]) {
        let escapedName = escapeAppleScript(processName)
        let escapedBundle = escapeAppleScript(bundleID)
        let script = """
        tell application "System Events"
            set targetProc to missing value
            try
                if "\(escapedBundle)" is not "" then
                    set targetProc to first process whose bundle identifier is "\(escapedBundle)"
                end if
            end try
            if targetProc is missing value then
                set targetProc to first process whose name is "\(escapedName)"
            end if
            tell targetProc
                click \(clause)
            end tell
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            AppLogger.debug("[MenuItem] Failed \(path.joined(separator: " › ")): \(error)")
        } else {
            AppLogger.debug("[MenuItem] Clicked \(path.joined(separator: " › ")) in \(processName)")
        }
    }

    private static func resolveApp(bundleID: String?) -> NSRunningApplication? {
        if let bundleID {
            return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy == .regular else { return nil }
        return front
    }
}

extension MenuItemCatalog {

    /// Builds AppleScript click target, e.g. `menu item "New Tab" of menu "File" of menu bar 1`
    static func buildClickClause(path: [String]) -> String {
        guard path.count >= 2 else { return "" }
        var anchor = "menu \"\(escapeAppleScript(path[0]))\" of menu bar 1"
        if path.count == 2 {
            return "menu item \"\(escapeAppleScript(path[1]))\" of \(anchor)"
        }
        for i in 1..<(path.count - 1) {
            anchor = "menu item \"\(escapeAppleScript(path[i]))\" of \(anchor)"
        }
        let leaf = path[path.count - 1]
        let parentMenu = path[path.count - 2]
        return "menu item \"\(escapeAppleScript(leaf))\" of menu \"\(escapeAppleScript(parentMenu))\" of \(anchor)"
    }
}
