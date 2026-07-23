import Foundation

// ─────────────────────────────────────────────
// MARK: - SystemGestureManager
//
// Reports which built-in macOS trackpad gestures Glide's suppression tap
// overrides at runtime. Glide no longer rewrites the system's trackpad
// preferences — blocking is per-gesture in the event tap, so the native
// side stays configured exactly as the user left it.
//
// `restoreLingeringBackups()` is a one-shot migration for machines where an
// earlier build disabled native gestures via `defaults write`: any key still
// sitting at 0 is restored to its snapshotted value, then the backup is
// cleared.
// ─────────────────────────────────────────────

enum SystemGestureManager {

    private static let trackpadDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]
    private static let dockDomain = "com.apple.dock"

    /// macOS stores an enabled swipe/tap as its finger count (2), not a bool.
    private static let nativeOnValue = 2

    struct NativeGesture: Identifiable, Equatable {
        var id: String { key }
        /// Primary trackpad key — identity + the gate that decides if it fires.
        let key: String
        let title: String
        /// Assumed state when the key is absent (macOS enables 3-finger variants
        /// by default; the 4-finger ones are opt-in).
        let defaultEnabled: Bool
        /// com.apple.dock bool keys that also gate this gesture. Only used by
        /// the backup-restore migration.
        let dockKeys: [String]
    }

    static let threeFingerHoriz = NativeGesture(
        key: "TrackpadThreeFingerHorizSwipeGesture",
        title: "3-Finger Swipe Left/Right (Switch Pages / Full-Screen Apps)",
        defaultEnabled: true, dockKeys: [])
    static let threeFingerVert = NativeGesture(
        key: "TrackpadThreeFingerVertSwipeGesture",
        title: "3-Finger Swipe Up/Down (Mission Control / App Exposé)",
        defaultEnabled: true,
        dockKeys: ["showMissionControlGestureEnabled", "showAppExposeGestureEnabled"])
    static let fourFingerHoriz = NativeGesture(
        key: "TrackpadFourFingerHorizSwipeGesture",
        title: "4-Finger Swipe Left/Right (Switch Full-Screen Apps)",
        defaultEnabled: false, dockKeys: [])
    static let fourFingerVert = NativeGesture(
        key: "TrackpadFourFingerVertSwipeGesture",
        title: "4-Finger Swipe Up/Down (Mission Control / App Exposé)",
        defaultEnabled: false,
        dockKeys: ["showMissionControlGestureEnabled", "showAppExposeGestureEnabled"])
    static let threeFingerTap = NativeGesture(
        key: "TrackpadThreeFingerTapGesture",
        title: "3-Finger Tap (Look Up & Data Detectors)",
        defaultEnabled: false, dockKeys: [])
    static let launchpadPinch = NativeGesture(
        key: "TrackpadFourFingerPinchGesture",
        title: "Pinch with Thumb & 3 Fingers (Launchpad)",
        defaultEnabled: true,
        dockKeys: ["showLaunchpadGestureEnabled"])
    static let showDesktopSpread = NativeGesture(
        key: "TrackpadFiveFingerPinchGesture",
        title: "Spread with Thumb & 3 Fingers (Show Desktop)",
        defaultEnabled: true,
        dockKeys: ["showDesktopGestureEnabled"])

    static let all = [threeFingerHoriz, threeFingerVert, fourFingerHoriz, fourFingerVert,
                      threeFingerTap, launchpadPinch, showDesktopSpread]

    struct GestureOverride: Identifiable, Equatable {
        var id: String { native.key }
        let native: NativeGesture
        /// Display names of the Glide gestures that take over this trigger.
        let glideTriggers: [String]
    }

    // MARK: - Detection

    static func isNativeEnabled(_ gesture: NativeGesture) -> Bool {
        // Enabled if ANY trackpad domain says so — built-in and Bluetooth pads
        // can disagree, and the gesture fires on whichever pad has it on.
        var sawValue = false
        for domain in trackpadDomains {
            if let value = UserDefaults(suiteName: domain)?.object(forKey: gesture.key) as? Int {
                if value != 0 { return true }
                sawValue = true
            }
        }
        return sawValue ? false : gesture.defaultEnabled
    }

    /// Native gestures that are enabled in System Settings but whose events the
    /// suppression tap swallows. Mirrors the tap's actual blocking: per finger
    /// count AND per axis — a count's unconfigured axis stays native. Pinches
    /// block per finger count via their own set (thumb counts as a finger, so
    /// a "4-finger" native pinch is 4 contacts). Native taps are never
    /// blocked, so 3-finger tap isn't listed.
    static func overriddenGestures(rules: [GestureRule], appSwitcher: AppSwitcherSettings) -> [GestureOverride] {
        var triggers: [String: [String]] = [:]   // native key → glide gesture names

        func add(_ native: NativeGesture, _ label: String) {
            triggers[native.key, default: []].append(label)
        }

        if appSwitcher.enabled {
            let label = "App Switcher (\(appSwitcher.fingers)-finger swipe)"
            if appSwitcher.fingers == 3 { add(threeFingerHoriz, label) }
            if appSwitcher.fingers == 4 { add(fourFingerHoriz, label) }
        }
        for rule in rules where rule.isActive && !rule.isKeyboardBinding {
            let label = rule.displayName
            switch (rule.fingers, rule.direction) {
            case (3, .swipeLeft), (3, .swipeRight), (3, .swipeLeftRight):
                add(threeFingerHoriz, label)
            case (3, .swipeUp), (3, .swipeDown), (3, .swipeUpDown):
                add(threeFingerVert, label)
            case (4, .swipeLeft), (4, .swipeRight), (4, .swipeLeftRight):
                add(fourFingerHoriz, label)
            case (4, .swipeUp), (4, .swipeDown), (4, .swipeUpDown):
                add(fourFingerVert, label)
            case (4, .pinchIn), (4, .pinchOut):
                add(launchpadPinch, label)
            case (5, .pinchIn), (5, .pinchOut):
                add(showDesktopSpread, label)
            default:
                break
            }
        }

        return all.compactMap { native in
            guard let labels = triggers[native.key], isNativeEnabled(native) else { return nil }
            return GestureOverride(native: native, glideTriggers: labels)
        }
    }

    // MARK: - One-shot restore of gestures disabled by earlier builds

    /// Earlier builds turned native gestures off with `defaults write` and kept
    /// a snapshot. Blocking is now done in the event tap, so restore anything
    /// still zeroed to its snapshotted value and clear the backup. Keys the
    /// user has since re-enabled by hand are left untouched.
    static func restoreLingeringBackups() {
        let store = backups()
        guard !store.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var restoredAny = false
            for gesture in all {
                guard let saved = store[gesture.key] else { continue }
                for domain in trackpadDomains {
                    let current = UserDefaults(suiteName: domain)?.object(forKey: gesture.key) as? Int
                    if current == 0 {
                        write(domain: domain, key: gesture.key,
                              int: saved[domain + "/" + gesture.key] ?? nativeOnValue)
                        restoredAny = true
                    }
                }
                for dockKey in gesture.dockKeys {
                    let current = UserDefaults(suiteName: dockDomain)?.object(forKey: dockKey) as? Int
                    if current == 0 {
                        write(domain: dockDomain, key: dockKey,
                              bool: (saved[dockDomain + "/" + dockKey] ?? 1) != 0)
                        restoredAny = true
                    }
                }
                AppLogger.debug("[SystemGesture] Restored native \(gesture.key) from backup")
            }
            UserDefaults.standard.removeObject(forKey: backupsKey)
            if restoredAny { runProcess("/usr/bin/killall", ["Dock"]) }
        }
    }

    // MARK: - Backup persistence (Glide's own prefs)

    private static let backupsKey = "nativeGestureBackups"

    /// gesture.key → { "domain/key": intValue } snapshot of everything an
    /// earlier build changed.
    private static func backups() -> [String: [String: Int]] {
        (UserDefaults.standard.dictionary(forKey: backupsKey) as? [String: [String: Int]]) ?? [:]
    }

    // MARK: - defaults writes

    private static func write(domain: String, key: String, int value: Int) {
        runProcess("/usr/bin/defaults", ["write", domain, key, "-int", String(value)])
    }

    private static func write(domain: String, key: String, bool value: Bool) {
        runProcess("/usr/bin/defaults", ["write", domain, key, "-bool", value ? "true" : "false"])
    }

    private static func runProcess(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
