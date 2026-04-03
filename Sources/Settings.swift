import Cocoa

// ─────────────────────────────────────────────
// MARK: - Enums
// ─────────────────────────────────────────────

enum GestureFingers: Int, Codable, CaseIterable {
    case two = 2, three = 3, four = 4, five = 5
    var label: String { "\(rawValue) Fingers" }
}

enum GestureDirection: String, Codable, CaseIterable {
    case click           = "Click"
    case swipeLeft       = "Swipe Left"
    case swipeRight      = "Swipe Right"
    case swipeUp         = "Swipe Up"
    case swipeDown       = "Swipe Down"
}

enum GestureSpeed: String, Codable, CaseIterable {
    case any    = "Any Speed"
    case slow   = "Slow"
    case normal = "Normal"
    case fast   = "Fast"

    static var allCases: [GestureSpeed] { [.slow, .normal, .fast] }
}

enum WindowTargetingMode: String, Codable, CaseIterable {
    case focusedThenCursor = "Focused Window First"
    case cursorThenFocused = "Window Under Cursor First"

    var label: String { rawValue }
}

enum GestureAction: String, Codable, CaseIterable {
    // App lifecycle
    case quitApp          = "Quit App Under Cursor"
    case forceQuitApp     = "Force Quit App Under Cursor"
    case quitFrontmost    = "Quit Frontmost App"
    case hideApp          = "Hide App Under Cursor"
    case hideOthers       = "Hide Other Apps"
    case openApp          = "Open App…"

    // App switching
    case appSwitcherNext  = "Next App (App Switcher)"
    case appSwitcherPrev  = "Previous App (App Switcher)"
    case switchAppNext    = "Activate Next App"
    case switchAppPrev    = "Activate Previous App"

    // Window state
    case minimizeWindow   = "Minimize Window"
    case minimizeAllApps  = "Minimize All Apps"
    case restoreMinimizedApps = "Restore Minimized Apps"
    case maximizeWindow   = "Maximize Window"
    case restoreWindow    = "Restore/Un-maximize Window"
    case closeWindow      = "Close Window"
    case enterFullscreen  = "Enter Fullscreen"
    case exitFullscreen   = "Exit Fullscreen"
    case toggleFullscreen = "Toggle Fullscreen"
    case cycleWindows     = "Cycle Windows (⌘`)"

    // Window snapping
    case snapLeft         = "Snap: Left Half"
    case snapRight        = "Snap: Right Half"
    case snapTopLeft      = "Snap: Top-Left"
    case snapTopRight     = "Snap: Top-Right"
    case snapBottomLeft   = "Snap: Bottom-Left"
    case snapBottomRight  = "Snap: Bottom-Right"
    case centerWindow     = "Center Window"
    case moveNextDisplay  = "Move to Next Display"

    // macOS system
    case missionControl   = "Mission Control"
    case appExpose        = "App Exposé"
    case showDesktop      = "Show Desktop"
    case launchpad        = "Launchpad"
    case spotlight        = "Spotlight"
    case notifCenter      = "Notification Center"
    case lockScreen       = "Lock Screen"
    case sleep            = "Sleep"
    case screenshotArea   = "Screenshot (Area)"
    case screenshotFull   = "Screenshot (Full)"

    // Meta
    case doNothing        = "Do Nothing"

    /// Returns the natural inverse action, or nil if this action is not reversible.
    var inverseAction: GestureAction? {
        switch self {
        // Toggle-style: same action reverses itself
        case .missionControl:    return .missionControl
        case .appExpose:         return .appExpose
        case .showDesktop:       return .showDesktop
        case .launchpad:         return .launchpad
        case .toggleFullscreen:  return .toggleFullscreen
        case .notifCenter:       return .notifCenter

        // State pairs
        case .enterFullscreen:       return .exitFullscreen
        case .exitFullscreen:        return .enterFullscreen
        case .maximizeWindow:        return .restoreWindow
        case .restoreWindow:         return .maximizeWindow
        case .minimizeWindow:        return .restoreWindow
        case .minimizeAllApps:       return .restoreMinimizedApps
        case .restoreMinimizedApps:  return .minimizeAllApps

        // Snap → restore
        case .snapLeft:          return .restoreWindow
        case .snapRight:         return .restoreWindow
        case .snapTopLeft:       return .restoreWindow
        case .snapTopRight:      return .restoreWindow
        case .snapBottomLeft:    return .restoreWindow
        case .snapBottomRight:   return .restoreWindow
        case .centerWindow:      return .restoreWindow

        // App switching
        case .switchAppNext:     return .switchAppPrev
        case .switchAppPrev:     return .switchAppNext

        // Destructive / one-shot — no inverse
        case .quitApp, .forceQuitApp, .quitFrontmost,
             .closeWindow, .hideApp, .hideOthers,
             .openApp, .cycleWindows, .moveNextDisplay,
             .spotlight, .lockScreen, .sleep,
             .screenshotArea, .screenshotFull,
             .appSwitcherNext, .appSwitcherPrev,
             .doNothing:
            return nil
        }
    }

    /// Whether this action has a natural inverse and supports reciprocal gestures.
    var supportsReciprocal: Bool { inverseAction != nil }
}

// ─────────────────────────────────────────────
// MARK: - GestureRule
// ─────────────────────────────────────────────

struct GestureRule: Codable, Identifiable, Equatable {
    var id        = UUID()
    var fingers:   Int              = 3
    var direction: GestureDirection = .click
    var speed:     GestureSpeed     = .normal
    var action:    GestureAction    = .doNothing
    var appPath:   String?          // for openApp
    var appFilter: String?          // bundle-ID; nil = any app
    var reciprocalEnabled: Bool     = true  // allow reverse gesture to undo this action

    init(fingers: Int, direction: GestureDirection, speed: GestureSpeed = .normal,
         action: GestureAction, appPath: String? = nil, appFilter: String? = nil,
         reciprocalEnabled: Bool = true) {
        self.fingers   = fingers
        self.direction = direction
        self.speed     = speed
        self.action    = action
        self.appPath   = appPath
        self.appFilter = appFilter
        self.reciprocalEnabled = reciprocalEnabled
    }

    // Make Codable robust against future enum cases
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decodeIfPresent(UUID.self,             forKey: .id))   ?? UUID()
        fingers   = (try? c.decode(Int.self,                       forKey: .fingers)) ?? 3
        direction = (try? c.decode(GestureDirection.self,          forKey: .direction)) ?? .click
        speed     = (try? c.decodeIfPresent(GestureSpeed.self,     forKey: .speed)) ?? .normal
        action    = (try? c.decode(GestureAction.self,             forKey: .action)) ?? .doNothing
        appPath   = try? c.decodeIfPresent(String.self,            forKey: .appPath)
        appFilter = try? c.decodeIfPresent(String.self,            forKey: .appFilter)
        reciprocalEnabled = (try? c.decodeIfPresent(Bool.self,     forKey: .reciprocalEnabled)) ?? true
    }
}

struct GestureTuning: Codable, Equatable {
    /// How far (normalised coords) a finger must travel before a swipe locks in.
    var initialThreshold: Float = 0.018

    /// How far the centroid must move per app-switcher step.
    var appSwitcherStepThreshold: Float = 0.003

    /// Minimum time between app-switcher steps.
    var appSwitcherDebounce: TimeInterval = 0.10

    /// Average centroid delta/frame above which a gesture is classified as "Fast".
    /// Higher = harder to trigger fast gestures. InputActions uses ~20 px/event for swipes;
    /// our normalised coords are ~0.0–1.0, so 0.008 is a sensible default.
    var fastVelocityThreshold: Float = 0.008

    /// Average centroid delta/frame below which a gesture is classified as "Slow".
    /// Lower = only very deliberate crawling gestures register as slow.
    var slowVelocityThreshold: Float = 0.003

    /// Number of frames to average when computing gesture velocity.
    /// Matches InputActions' `inputEventsToSample` (default 3).
    var speedSampleCount: Int = 3

    // ── Pinch veto / candidate phase ──

    /// Number of frames to collect before locking a session as swipe.
    /// Minimum enforced: 3 (to let gestures reveal themselves).
    var candidateFrames: Int = 3

    /// Cumulative spread change across all candidate frames above which the session is vetoed.
    var pinchSpreadThreshold: Float = 0.015

    /// Per-frame spread delta above which the session is vetoed immediately.
    var pinchFrameSpreadThreshold: Float = 0.008

    /// Minimum directional coherence (0–1) to accept as swipe. Lower = more lenient.
    var swipeCoherenceThreshold: Float = 0.30

    /// Angle tolerance in degrees for each cardinal direction (InputActions: DEFAULT_SWIPE_ANGLE_TOLERANGE = 20).
    /// Each cardinal direction spans ±angleTolerance from its axis.
    /// 45° = full quadrants (no dead zones); lower = narrower wedges with diagonal dead zones.
    var swipeAngleTolerance: Float = 45

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        initialThreshold         = try c.decodeIfPresent(Float.self,         forKey: .initialThreshold)         ?? 0.018
        appSwitcherStepThreshold = try c.decodeIfPresent(Float.self,         forKey: .appSwitcherStepThreshold) ?? 0.003
        appSwitcherDebounce      = try c.decodeIfPresent(TimeInterval.self,  forKey: .appSwitcherDebounce)      ?? 0.10
        // Velocity-based speed params (replacing legacy time-based ones)
        fastVelocityThreshold    = try c.decodeIfPresent(Float.self,         forKey: .fastVelocityThreshold)    ?? 0.008
        slowVelocityThreshold    = try c.decodeIfPresent(Float.self,         forKey: .slowVelocityThreshold)    ?? 0.003
        speedSampleCount         = try c.decodeIfPresent(Int.self,           forKey: .speedSampleCount)         ?? 3
        candidateFrames          = try c.decodeIfPresent(Int.self,           forKey: .candidateFrames)          ?? 3
        pinchSpreadThreshold     = try c.decodeIfPresent(Float.self,         forKey: .pinchSpreadThreshold)     ?? 0.015
        pinchFrameSpreadThreshold = try c.decodeIfPresent(Float.self,        forKey: .pinchFrameSpreadThreshold) ?? 0.008
        swipeCoherenceThreshold  = try c.decodeIfPresent(Float.self,         forKey: .swipeCoherenceThreshold)  ?? 0.3
        swipeAngleTolerance      = try c.decodeIfPresent(Float.self,         forKey: .swipeAngleTolerance)      ?? 45
    }
}

// ─────────────────────────────────────────────
// MARK: - Settings
// ─────────────────────────────────────────────

final class Settings {
    static let shared = Settings()
    private init() {}

    private struct RuleIdentity: Hashable {
        let fingers: Int
        let direction: GestureDirection
        let speed: GestureSpeed
        let appFilter: String?
    }

    private let kRules = "gestureRulesV3"
    private let kRulesVersion = "gestureRulesSchemaVersion"
    private let kTuning = "gestureTuningV2"
    private let kWindowTargetingMode = "windowTargetingModeV1"
    private let kDebugLogging = "debugLoggingV1"
    private let kHapticFeedback = "hapticFeedbackV1"
    // Legacy keys — for one-time migration only
    private let kLegacyTuning = "gestureTuningV1"
    private let kLegacyInitialThreshold = "adv_swipeThreshold"
    private let kLegacyAppSwitcherStepThreshold = "adv_stepThreshold"
    private let currentRulesVersion = 6

    // Simple in-memory cache
    private var _rules: [GestureRule]?
    private var _tuning: GestureTuning?
    private var _windowTargetingMode: WindowTargetingMode?
    private var _debugLogging: Bool?
    private var _hapticFeedback: Bool?

    var rules: [GestureRule] {
        get {
            if let cached = _rules { return cached }
            if let data   = UserDefaults.standard.data(forKey: kRules),
               let decoded = try? JSONDecoder().decode([GestureRule].self, from: data) {
                let migrated = canonicalizeRules(migrateRulesIfNeeded(decoded))
                persistRules(migrated)
                _rules = migrated
                return migrated
            }
            let defaults = canonicalizeRules(Self.defaultRules)
            _rules = defaults
            persistRules(defaults)
            return defaults
        }
        set {
            let normalized = canonicalizeRules(newValue)
            _rules = normalized
            persistRules(normalized)
        }
    }

    func invalidateCache() {
        _rules = nil
        _tuning = nil
        _windowTargetingMode = nil
        _debugLogging = nil
        _hapticFeedback = nil
    }

    var tuning: GestureTuning {
        get {
            if let cached = _tuning { return cached }
            if let data = UserDefaults.standard.data(forKey: kTuning),
               let decoded = try? JSONDecoder().decode(GestureTuning.self, from: data) {
                _tuning = decoded
                return decoded
            }
            // Try migrating from legacy V1 tuning (velocity-based) — just use fresh defaults
            // since velocity values don't translate meaningfully to time values.
            let defaults = migratedLegacyTuning() ?? GestureTuning()
            _tuning = defaults
            if let data = try? JSONEncoder().encode(defaults) {
                UserDefaults.standard.set(data, forKey: kTuning)
            }
            return defaults
        }
        set {
            let normalized = normalizedTuning(newValue)
            _tuning = normalized
            if let data = try? JSONEncoder().encode(normalized) {
                UserDefaults.standard.set(data, forKey: kTuning)
            }
        }
    }

    func resetTuning() {
        tuning = GestureTuning()
    }

    var windowTargetingMode: WindowTargetingMode {
        get {
            if let cached = _windowTargetingMode { return cached }
            if let raw = UserDefaults.standard.string(forKey: kWindowTargetingMode),
               let decoded = WindowTargetingMode(rawValue: raw) {
                _windowTargetingMode = decoded
                return decoded
            }
            let value: WindowTargetingMode = .focusedThenCursor
            _windowTargetingMode = value
            return value
        }
        set {
            _windowTargetingMode = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: kWindowTargetingMode)
        }
    }

    var debugLoggingEnabled: Bool {
        get {
            if let cached = _debugLogging { return cached }
            if UserDefaults.standard.object(forKey: kDebugLogging) != nil {
                let value = UserDefaults.standard.bool(forKey: kDebugLogging)
                _debugLogging = value
                return value
            }
            _debugLogging = false
            return false
        }
        set {
            _debugLogging = newValue
            UserDefaults.standard.set(newValue, forKey: kDebugLogging)
        }
    }

    var hapticFeedbackEnabled: Bool {
        get {
            if let cached = _hapticFeedback { return cached }
            if UserDefaults.standard.object(forKey: kHapticFeedback) != nil {
                let value = UserDefaults.standard.bool(forKey: kHapticFeedback)
                _hapticFeedback = value
                return value
            }
            _hapticFeedback = true   // on by default
            return true
        }
        set {
            _hapticFeedback = newValue
            UserDefaults.standard.set(newValue, forKey: kHapticFeedback)
        }
    }

    private func migrateRulesIfNeeded(_ rules: [GestureRule]) -> [GestureRule] {
        let storedVersion = UserDefaults.standard.integer(forKey: kRulesVersion)
        guard storedVersion < currentRulesVersion else {
            return rules.map(normalizedRule)
        }

        let migrated = rules.map { rule in
            var rule = normalizedRule(rule)

            if rule.fingers == 3, rule.direction == .swipeDown, rule.action == .minimizeWindow {
                rule.action = .minimizeAllApps
            }

            if rule.fingers == 5, rule.direction == .swipeUp, rule.action == .toggleFullscreen {
                rule.action = .enterFullscreen
            }

            if rule.fingers == 5, rule.direction == .swipeDown, rule.action == .showDesktop {
                rule.action = .exitFullscreen
            }

            return rule
        }
        return migrated
    }

    private func normalizedRule(_ rule: GestureRule) -> GestureRule {
        var normalized = rule
        normalized.fingers = min(max(normalized.fingers, 2), 5)
        normalized.speed = normalized.speed == .any ? .normal : normalized.speed
        if normalized.direction == .click {
            normalized.speed = .normal
        }
        return normalized
    }

    private func canonicalizeRules(_ rules: [GestureRule]) -> [GestureRule] {
        var seen: Set<RuleIdentity> = []
        var dedupedReversed: [GestureRule] = []

        for rule in rules.reversed() {
            let normalized = normalizedRule(rule)
            let identity = RuleIdentity(
                fingers: normalized.fingers,
                direction: normalized.direction,
                speed: normalized.speed,
                appFilter: normalized.appFilter
            )
            guard seen.insert(identity).inserted else { continue }
            dedupedReversed.append(normalized)
        }

        return dedupedReversed.reversed()
    }

    private func persistRules(_ rules: [GestureRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: kRules)
        }
        UserDefaults.standard.set(currentRulesVersion, forKey: kRulesVersion)
    }

    private func normalizedTuning(_ tuning: GestureTuning) -> GestureTuning {
        var n = tuning
        n.initialThreshold = max(0.005, n.initialThreshold)
        n.appSwitcherStepThreshold = max(0.001, n.appSwitcherStepThreshold)
        n.appSwitcherDebounce = max(0.0, n.appSwitcherDebounce)
        // Enforce non-overlapping bands: slowVelocityThreshold < fastVelocityThreshold
        n.slowVelocityThreshold = max(0.001, min(n.slowVelocityThreshold, 0.020))
        n.fastVelocityThreshold = max(n.slowVelocityThreshold + 0.001, max(0.003, min(n.fastVelocityThreshold, 0.030)))
        n.speedSampleCount = max(2, min(n.speedSampleCount, 8))
        // Pinch veto
        n.candidateFrames = max(1, min(n.candidateFrames, 8))
        n.pinchSpreadThreshold = max(0.002, n.pinchSpreadThreshold)
        n.pinchFrameSpreadThreshold = max(0.001, n.pinchFrameSpreadThreshold)
        n.swipeCoherenceThreshold = max(0.0, min(n.swipeCoherenceThreshold, 0.95))
        // Direction detection
        n.swipeAngleTolerance = max(20, min(n.swipeAngleTolerance, 45))
        return n
    }

    /// Migrate from legacy V1 tuning. Since old params were velocity-based and new
    /// params are time-based, we only migrate the threshold values that didn't change
    /// semantically. Speed params get fresh defaults.
    private func migratedLegacyTuning() -> GestureTuning? {
        let defaults = UserDefaults.standard
        // Check for any legacy key
        guard defaults.object(forKey: kLegacyTuning) != nil
            || defaults.object(forKey: kLegacyInitialThreshold) != nil
            || defaults.object(forKey: kLegacyAppSwitcherStepThreshold) != nil else {
            return nil
        }

        var tuning = GestureTuning()

        if defaults.object(forKey: kLegacyInitialThreshold) != nil {
            tuning.initialThreshold = defaults.float(forKey: kLegacyInitialThreshold)
        }
        if defaults.object(forKey: kLegacyAppSwitcherStepThreshold) != nil {
            tuning.appSwitcherStepThreshold = defaults.float(forKey: kLegacyAppSwitcherStepThreshold)
        }
        // Speed params: use fresh defaults (velocity → time doesn't map meaningfully)

        return normalizedTuning(tuning)
    }

    static var defaultRules: [GestureRule] = [
        GestureRule(fingers: 3, direction: .click,      action: .quitApp),
        GestureRule(fingers: 3, direction: .swipeRight, action: .appSwitcherNext),
        GestureRule(fingers: 3, direction: .swipeLeft,  action: .appSwitcherPrev),
        GestureRule(fingers: 3, direction: .swipeUp,    action: .missionControl),
        GestureRule(fingers: 3, direction: .swipeDown,  action: .minimizeAllApps),
        GestureRule(fingers: 4, direction: .swipeUp,    action: .maximizeWindow),
        GestureRule(fingers: 4, direction: .swipeDown,  action: .restoreWindow),
        GestureRule(fingers: 4, direction: .swipeLeft,  action: .snapLeft),
        GestureRule(fingers: 4, direction: .swipeRight, action: .snapRight),
        GestureRule(fingers: 5, direction: .swipeUp,    action: .enterFullscreen),
        GestureRule(fingers: 5, direction: .swipeDown,  action: .exitFullscreen),
        GestureRule(fingers: 5, direction: .click,      action: .lockScreen),
    ]
}

enum AppLogger {
    static func debug(_ message: @autoclosure () -> String) {
        guard Settings.shared.debugLoggingEnabled else { return }
        print(message())
    }
}
