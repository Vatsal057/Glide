import Cocoa
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: - Menu item catalog (AX)
// ─────────────────────────────────────────────

struct MenuItemOption: Identifiable, Hashable {
    /// Full path segments, e.g. ["File", "New Tab"]
    let path: [String]
    var id: String { path.joined(separator: " › ") }
    var displayTitle: String { id }
}

enum MenuItemCatalog {

    /// Lists menu items for a running app (`bundleID` nil → frontmost regular app).
    static func options(bundleID: String?) -> [MenuItemOption] {
        guard let app = resolveRunningApp(bundleID: bundleID) else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = axElement(from: menuBarRef) else { return [] }

        var results: [MenuItemOption] = []
        for topMenu in axChildren(menuBar) {
            guard let menuTitle = axTitle(topMenu), !menuTitle.isEmpty else { continue }
            collectItems(in: topMenu, path: [menuTitle], into: &results)
        }
        return results.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
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

    // MARK: AX helpers

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let list = ref as? [AXUIElement] else { return [] }
        return list
    }

    private static func axSubmenu(_ item: AXUIElement) -> AXUIElement? {
        for child in axChildren(item) {
            if axRole(child) == (kAXMenuRole as String) { return child }
        }
        return nil
    }

    private static func axTitle(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
        if let s = ref as? String, !s.isEmpty { return s }
        if let attr = ref as? NSAttributedString { return attr.string }
        return nil
    }

    private static func axRole(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func axBool(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        return ref as? Bool
    }

    private static func axElement(from ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }
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
        guard let app = resolveApp(bundleID: bundleID) else {
            AppLogger.debug("[MenuItem] No target app")
            return
        }

        app.activate(options: [.activateIgnoringOtherApps])
        usleep(80_000)

        guard let processName = app.localizedName ?? app.bundleIdentifier else { return }
        let clause = buildClickClause(path: path)
        let script = """
        tell application "System Events"
          tell process "\(escapeAppleScript(processName))"
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

    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
