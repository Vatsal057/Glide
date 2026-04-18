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
    case quitApp          = "Quit App Under Cursor"
    case forceQuitApp     = "Force Quit App Under Cursor"
    case quitFrontmost    = "Quit Frontmost App"
    case hideApp          = "Hide App Under Cursor"
    case hideOthers       = "Hide Other Apps"
    case openApp          = "Open App…"
    case appSwitcherNext  = "Next App (App Switcher)"
    case appSwitcherPrev  = "Previous App (App Switcher)"
    case switchAppNext    = "Activate Next App"
    case switchAppPrev    = "Activate Previous App"
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
    case snapLeft         = "Snap: Left Half"
    case snapRight        = "Snap: Right Half"
    case snapTopLeft      = "Snap: Top-Left"
    case snapTopRight     = "Snap: Top-Right"
    case snapBottomLeft   = "Snap: Bottom-Left"
    case snapBottomRight  = "Snap: Bottom-Right"
    case centerWindow     = "Center Window"
    case moveNextDisplay  = "Move to Next Display"
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
    case doNothing        = "Do Nothing"

    var inverseAction: GestureAction? {
        switch self {
        case .missionControl:    return .missionControl
        case .appExpose:         return .appExpose
        case .showDesktop:       return .showDesktop
        case .launchpad:         return .launchpad
        case .toggleFullscreen:  return .toggleFullscreen
        case .notifCenter:       return .notifCenter
        case .enterFullscreen:       return .exitFullscreen
        case .exitFullscreen:        return .enterFullscreen
        case .maximizeWindow:        return .restoreWindow
        case .restoreWindow:         return .maximizeWindow
        case .minimizeWindow:        return .restoreWindow
        case .minimizeAllApps:       return .restoreMinimizedApps
        case .restoreMinimizedApps:  return .minimizeAllApps
        case .snapLeft, .snapRight,
             .snapTopLeft, .snapTopRight,
             .snapBottomLeft, .snapBottomRight,
             .centerWindow:      return .restoreWindow
        case .switchAppNext:     return .switchAppPrev
        case .switchAppPrev:     return .switchAppNext
        default:                 return nil
        }
    }

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
    var appPath:   String?
    var appFilter: String?
    var reciprocalEnabled: Bool     = true

    init(fingers: Int, direction: GestureDirection, speed: GestureSpeed = .normal,
         action: GestureAction, appPath: String? = nil, appFilter: String? = nil,
         reciprocalEnabled: Bool = true) {
        self.fingers           = fingers
        self.direction         = direction
        self.speed             = speed
        self.action            = action
        self.appPath           = appPath
        self.appFilter         = appFilter
        self.reciprocalEnabled = reciprocalEnabled
    }

    // Robust decoding — tolerates unknown future enum cases
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decodeIfPresent(UUID.self,          forKey: .id))        ?? UUID()
        fingers   = (try? c.decode(Int.self,                    forKey: .fingers))   ?? 3
        direction = (try? c.decode(GestureDirection.self,       forKey: .direction)) ?? .click
        speed     = (try? c.decodeIfPresent(GestureSpeed.self,  forKey: .speed))     ?? .normal
        action    = (try? c.decode(GestureAction.self,          forKey: .action))    ?? .doNothing
        appPath   = try? c.decodeIfPresent(String.self,         forKey: .appPath)
        appFilter = try? c.decodeIfPresent(String.self,         forKey: .appFilter)
        reciprocalEnabled = (try? c.decodeIfPresent(Bool.self,  forKey: .reciprocalEnabled)) ?? true
    }
}

// ─────────────────────────────────────────────
// MARK: - EdgeMargin / GestureTuning
// ─────────────────────────────────────────────

struct EdgeMargin: Codable, Equatable {
    var left:   Float = 0.05
    var right:  Float = 0.05
    var top:    Float = 0.05
    var bottom: Float = 0.05

    static let range: ClosedRange<Float> = 0.0...0.20
}

struct GestureTuning: Codable, Equatable {
    var initialThreshold:           Float        = 0.018
    var appSwitcherStepThreshold:   Float        = 0.003
    var appSwitcherDebounce:        TimeInterval = 0.10
    var fastVelocityThreshold:      Float        = 0.008
    var slowVelocityThreshold:      Float        = 0.003
    var speedSampleCount:           Int          = 3
    var candidateFrames:            Int          = 3
    var pinchSpreadThreshold:       Float        = 0.015
    var pinchFrameSpreadThreshold:  Float        = 0.008
    var swipeCoherenceThreshold:    Float        = 0.30
    var swipeAngleTolerance:        Float        = 45
    var edgeMarginEnabled:          Bool         = true
    var edgeMargin:                 EdgeMargin   = EdgeMargin()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        initialThreshold          = try c.decodeIfPresent(Float.self,        forKey: .initialThreshold)          ?? 0.018
        appSwitcherStepThreshold  = try c.decodeIfPresent(Float.self,        forKey: .appSwitcherStepThreshold)  ?? 0.003
        appSwitcherDebounce       = try c.decodeIfPresent(TimeInterval.self, forKey: .appSwitcherDebounce)       ?? 0.10
        fastVelocityThreshold     = try c.decodeIfPresent(Float.self,        forKey: .fastVelocityThreshold)     ?? 0.008
        slowVelocityThreshold     = try c.decodeIfPresent(Float.self,        forKey: .slowVelocityThreshold)     ?? 0.003
        speedSampleCount          = try c.decodeIfPresent(Int.self,          forKey: .speedSampleCount)          ?? 3
        candidateFrames           = try c.decodeIfPresent(Int.self,          forKey: .candidateFrames)           ?? 3
        pinchSpreadThreshold      = try c.decodeIfPresent(Float.self,        forKey: .pinchSpreadThreshold)      ?? 0.015
        pinchFrameSpreadThreshold = try c.decodeIfPresent(Float.self,        forKey: .pinchFrameSpreadThreshold) ?? 0.008
        swipeCoherenceThreshold   = try c.decodeIfPresent(Float.self,        forKey: .swipeCoherenceThreshold)   ?? 0.30
        swipeAngleTolerance       = try c.decodeIfPresent(Float.self,        forKey: .swipeAngleTolerance)       ?? 45
        edgeMarginEnabled         = try c.decodeIfPresent(Bool.self,         forKey: .edgeMarginEnabled)         ?? true
        edgeMargin                = try c.decodeIfPresent(EdgeMargin.self,   forKey: .edgeMargin)                ?? EdgeMargin()
    }
}

// ─────────────────────────────────────────────
// MARK: - Settings
// ─────────────────────────────────────────────
//
// Pure in-memory store. All persistence is handled by GlideConfigStore (YAML).
// Public setters trigger an immediate YAML save. Use apply(_:) during config
// load to batch-set all values without triggering per-field saves.

final class Settings {
    static let shared = Settings()

    private init() {
        _rules = Self.canonicalizeRules(Self.defaultRules)
    }

    // MARK: Backing stores

    private var _rules:           [GestureRule]
    private var _tuning:          GestureTuning       = GestureTuning()
    private var _windowTargeting: WindowTargetingMode = .focusedThenCursor
    private var _hapticFeedback:  Bool                = true
    private var _debugLogging:    Bool                = false
    private var _launchAtLogin:   Bool                = false

    // MARK: Public interface

    var rules: [GestureRule] {
        get { _rules }
        set { _rules = Self.canonicalizeRules(newValue); GlideConfigStore.shared.save() }
    }

    var tuning: GestureTuning {
        get { _tuning }
        set { _tuning = Self.normalizedTuning(newValue); GlideConfigStore.shared.save() }
    }

    var windowTargetingMode: WindowTargetingMode {
        get { _windowTargeting }
        set { _windowTargeting = newValue; GlideConfigStore.shared.save() }
    }

    var hapticFeedbackEnabled: Bool {
        get { _hapticFeedback }
        set { _hapticFeedback = newValue; GlideConfigStore.shared.save() }
    }

    var debugLoggingEnabled: Bool {
        get { _debugLogging }
        set { _debugLogging = newValue; GlideConfigStore.shared.save() }
    }

    var launchAtLoginEnabled: Bool {
        get { _launchAtLogin }
        set { _launchAtLogin = newValue; GlideConfigStore.shared.save() }
    }

    func resetTuning() { tuning = GestureTuning() }

    // MARK: Batch load — bypasses per-field saves (called by GlideConfigStore.load)

    func apply(_ config: GlideConfig) {
        _rules           = Self.canonicalizeRules(config.toRules())
        _tuning          = Self.normalizedTuning(config.toTuning())
        _windowTargeting = WindowTargetingMode(rawValue: config.preferences.windowTargeting) ?? .focusedThenCursor
        _hapticFeedback  = config.preferences.hapticFeedback
        _debugLogging    = config.preferences.debugLogging
        _launchAtLogin   = config.preferences.launchAtLogin
    }

    // MARK: Rule deduplication

    private struct RuleIdentity: Hashable {
        let fingers: Int; let direction: GestureDirection
        let speed: GestureSpeed; let appFilter: String?
    }

    private static func canonicalizeRules(_ rules: [GestureRule]) -> [GestureRule] {
        var seen: Set<RuleIdentity> = []
        var result: [GestureRule] = []
        for rule in rules.reversed() {
            let r = normalizedRule(rule)
            let id = RuleIdentity(fingers: r.fingers, direction: r.direction,
                                  speed: r.speed, appFilter: r.appFilter)
            if seen.insert(id).inserted { result.append(r) }
        }
        return result.reversed()
    }

    private static func normalizedRule(_ rule: GestureRule) -> GestureRule {
        var r = rule
        r.fingers = min(max(r.fingers, 2), 5)
        r.speed   = (r.speed == .any || r.direction == .click) ? .normal : r.speed
        return r
    }

    // Single authoritative tuning normalizer — also called by PreferencesStore
    static func normalizedTuning(_ t: GestureTuning) -> GestureTuning {
        var n = t
        n.initialThreshold         = max(0.005, n.initialThreshold)
        n.appSwitcherStepThreshold = max(0.001, n.appSwitcherStepThreshold)
        n.appSwitcherDebounce      = max(0.0,   n.appSwitcherDebounce)
        n.slowVelocityThreshold    = max(0.001, min(n.slowVelocityThreshold, 0.020))
        n.fastVelocityThreshold    = max(n.slowVelocityThreshold + 0.001,
                                         max(0.003, min(n.fastVelocityThreshold, 0.030)))
        n.speedSampleCount         = max(2, min(n.speedSampleCount, 8))
        n.candidateFrames          = max(1, min(n.candidateFrames, 8))
        n.pinchSpreadThreshold     = max(0.002, n.pinchSpreadThreshold)
        n.pinchFrameSpreadThreshold = max(0.001, n.pinchFrameSpreadThreshold)
        n.swipeCoherenceThreshold  = max(0.0, min(n.swipeCoherenceThreshold, 0.95))
        n.swipeAngleTolerance      = max(20, min(n.swipeAngleTolerance, 45))
        let clamp = { (v: Float) in max(EdgeMargin.range.lowerBound,
                                        min(v, EdgeMargin.range.upperBound)) }
        n.edgeMargin.left   = clamp(n.edgeMargin.left)
        n.edgeMargin.right  = clamp(n.edgeMargin.right)
        n.edgeMargin.top    = clamp(n.edgeMargin.top)
        n.edgeMargin.bottom = clamp(n.edgeMargin.bottom)
        return n
    }

    // MARK: Defaults

    static let defaultRules: [GestureRule] = [
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

// ─────────────────────────────────────────────
// MARK: - AppLogger
// ─────────────────────────────────────────────

enum AppLogger {
    static func debug(_ message: @autoclosure () -> String) {
        guard Settings.shared.debugLoggingEnabled else { return }
        print(message())
    }
}
