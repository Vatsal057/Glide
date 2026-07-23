import Foundation

// ─────────────────────────────────────────────
// MARK: - SystemGestureManager
//
// Detects overlap between Glide gestures and the built-in macOS trackpad
// gestures, and can switch the native side off (and back on) so both don't
// fire at once.
//
// State lives across several preference domains that don't agree on a format:
//   • Two trackpad domains gate whether a swipe/tap fires at all. Their "on"
//     value is 2 (finger count), "off" is 0 — NOT a 0/1 bool.
//   • com.apple.dock additionally gates Mission Control and App Exposé with
//     plain bools; the Dock only re-reads these after it restarts.
// A vertical 3/4-finger swipe therefore needs BOTH its trackpad key AND the
// matching Dock key cleared, or the native action still triggers.
//
// Re-enabling restores each key's exact pre-disable value (snapshotted into
// Glide's own prefs), so a user who was on "four fingers" isn't reset to three.
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
        /// com.apple.dock bool keys that also gate this gesture (Mission Control
        /// / App Exposé). Cleared alongside the trackpad key so the Dock stops it.
        let dockKeys: [String]
        /// True when killing the Dock is enough to apply a change; false when the
        /// change (pure space-switching) only takes full effect after a re-login.
        let appliesWithoutLogout: Bool
    }

    static let threeFingerHoriz = NativeGesture(
        key: "TrackpadThreeFingerHorizSwipeGesture",
        title: "3-Finger Swipe Left/Right (Switch Pages / Full-Screen Apps)",
        defaultEnabled: true, dockKeys: [], appliesWithoutLogout: false)
    static let threeFingerVert = NativeGesture(
        key: "TrackpadThreeFingerVertSwipeGesture",
        title: "3-Finger Swipe Up/Down (Mission Control / App Exposé)",
        defaultEnabled: true,
        dockKeys: ["showMissionControlGestureEnabled", "showAppExposeGestureEnabled"],
        appliesWithoutLogout: true)
    static let fourFingerHoriz = NativeGesture(
        key: "TrackpadFourFingerHorizSwipeGesture",
        title: "4-Finger Swipe Left/Right (Switch Full-Screen Apps)",
        defaultEnabled: false, dockKeys: [], appliesWithoutLogout: false)
    static let fourFingerVert = NativeGesture(
        key: "TrackpadFourFingerVertSwipeGesture",
        title: "4-Finger Swipe Up/Down (Mission Control / App Exposé)",
        defaultEnabled: false,
        dockKeys: ["showMissionControlGestureEnabled", "showAppExposeGestureEnabled"],
        appliesWithoutLogout: true)
    static let threeFingerTap = NativeGesture(
        key: "TrackpadThreeFingerTapGesture",
        title: "3-Finger Tap (Look Up & Data Detectors)",
        defaultEnabled: false, dockKeys: [], appliesWithoutLogout: true)
    // Never reported as conflicts: Glide has no pinch gestures and its
    // processor rejects pinch-shaped input (pinchSpreadThreshold), so native
    // pinch/spread can't collide. Kept in `all` only so copies disabled by an
    // earlier build can still be re-enabled via disabledByGlide().
    static let launchpadPinch = NativeGesture(
        key: "TrackpadFourFingerPinchGesture",
        title: "Pinch with Thumb & 3 Fingers (Launchpad)",
        defaultEnabled: true,
        dockKeys: ["showLaunchpadGestureEnabled"],
        appliesWithoutLogout: true)
    static let showDesktopSpread = NativeGesture(
        key: "TrackpadFiveFingerPinchGesture",
        title: "Spread with Thumb & 3 Fingers (Show Desktop)",
        defaultEnabled: true,
        dockKeys: ["showDesktopGestureEnabled"],
        appliesWithoutLogout: true)

    static let all = [threeFingerHoriz, threeFingerVert, fourFingerHoriz, fourFingerVert,
                      threeFingerTap, launchpadPinch, showDesktopSpread]

    struct Conflict: Identifiable, Equatable {
        var id: String { native.key }
        let native: NativeGesture
        /// Display names of the Glide gestures that collide with it.
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

    /// Native gestures Glide previously disabled (a backup snapshot exists), so
    /// they can be offered for re-enabling even though they no longer conflict.
    static func disabledByGlide() -> [NativeGesture] {
        all.filter { backups()[$0.key] != nil }
    }

    /// Native gestures that are still on while a Glide gesture uses the same trigger.
    static func currentConflicts(rules: [GestureRule], appSwitcher: AppSwitcherSettings) -> [Conflict] {
        var triggers: [String: [String]] = [:]   // native key → glide gesture names

        func add(_ native: NativeGesture, _ label: String) {
            triggers[native.key, default: []].append(label)
        }

        if appSwitcher.enabled {
            add(threeFingerHoriz, "App Switcher (3-finger swipe)")
        }
        for rule in rules where rule.isActive {
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
            case (3, .click), (3, .forceClick), (3, .tapHold):
                add(threeFingerTap, label)
            default:
                break
            }
        }

        return all.compactMap { native in
            guard let labels = triggers[native.key], isNativeEnabled(native) else { return nil }
            return Conflict(native: native, glideTriggers: labels)
        }
    }

    // MARK: - Disabling / enabling

    /// Turns the given native gestures off, snapshotting their current values
    /// first so they can be restored. Restarts the Dock once. No-op when empty.
    static func disableNativeGestures(_ gestures: [NativeGesture]) {
        let toDisable = gestures.filter(isNativeEnabled)
        guard !toDisable.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var store = backups()
            for gesture in toDisable {
                // Snapshot every key we touch (only if not already backed up, so a
                // re-run doesn't overwrite the real value with our own 0).
                if store[gesture.key] == nil {
                    store[gesture.key] = snapshot(gesture)
                }
                for domain in trackpadDomains {
                    write(domain: domain, key: gesture.key, int: 0)
                }
                for dockKey in gesture.dockKeys {
                    write(domain: dockDomain, key: dockKey, bool: false)
                }
                AppLogger.debug("[SystemGesture] Disabled native \(gesture.key)")
            }
            saveBackups(store)
            runProcess("/usr/bin/killall", ["Dock"])
        }
    }

    /// Restores each key to its snapshotted pre-disable value (falling back to the
    /// macOS default "on" value when no snapshot exists). Restarts the Dock once.
    static func reEnableNativeGestures(_ gestures: [NativeGesture]) {
        guard !gestures.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var store = backups()
            for gesture in gestures {
                let saved = store[gesture.key]
                for domain in trackpadDomains {
                    write(domain: domain, key: gesture.key,
                          int: saved?[domain + "/" + gesture.key] ?? nativeOnValue)
                }
                for dockKey in gesture.dockKeys {
                    let savedDock = saved?[dockDomain + "/" + dockKey]
                    write(domain: dockDomain, key: dockKey, bool: (savedDock ?? 1) != 0)
                }
                store[gesture.key] = nil
                AppLogger.debug("[SystemGesture] Re-enabled native \(gesture.key)")
            }
            saveBackups(store)
            runProcess("/usr/bin/killall", ["Dock"])
        }
    }

    /// Auto mode: disable every native gesture that currently collides with a
    /// configured Glide gesture. Safe to call often — skips work when clean.
    static func reconcileIfAutoEnabled() {
        guard Settings.shared.autoDisableNativeGestures else { return }
        let conflicts = currentConflicts(rules: Settings.shared.rules,
                                         appSwitcher: Settings.shared.appSwitcher)
        disableNativeGestures(conflicts.map(\.native))
    }

    // MARK: - Backup persistence (Glide's own prefs)

    private static let backupsKey = "nativeGestureBackups"

    /// gesture.key → { "domain/key": intValue } snapshot of everything we changed.
    private static func backups() -> [String: [String: Int]] {
        (UserDefaults.standard.dictionary(forKey: backupsKey) as? [String: [String: Int]]) ?? [:]
    }

    private static func saveBackups(_ store: [String: [String: Int]]) {
        if store.isEmpty {
            UserDefaults.standard.removeObject(forKey: backupsKey)
        } else {
            UserDefaults.standard.set(store, forKey: backupsKey)
        }
    }

    private static func snapshot(_ gesture: NativeGesture) -> [String: Int] {
        var snap: [String: Int] = [:]
        for domain in trackpadDomains {
            if let v = UserDefaults(suiteName: domain)?.object(forKey: gesture.key) as? Int {
                snap[domain + "/" + gesture.key] = v
            }
        }
        for dockKey in gesture.dockKeys {
            if let v = UserDefaults(suiteName: dockDomain)?.object(forKey: dockKey) as? Int {
                snap[dockDomain + "/" + dockKey] = v
            }
        }
        return snap
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
