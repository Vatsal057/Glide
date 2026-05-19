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

/// Restricts a gesture rule to the frontmost window's layout state.
/// Modifier keys held when the gesture begins (same finger count placed on the trackpad).
enum ModifierFilter: String, Codable, CaseIterable {
    case any           = "Any"
    case shiftHeld     = "⇧ Shift Held"
    case shiftNotHeld  = "⇧ Shift Not Held"
    case controlHeld   = "⌃ Control Held"
    case controlNotHeld = "⌃ Control Not Held"
    case optionHeld    = "⌥ Option Held"
    case optionNotHeld = "⌥ Option Not Held"
    case commandHeld   = "⌘ Command Held"
    case commandNotHeld = "⌘ Command Not Held"
    case noModifiers   = "No Modifier Keys"

    init?(yamlValue: String?) {
        guard let yamlValue else { return nil }
        let key = yamlValue.lowercased().replacingOccurrences(of: " ", with: "_")
        switch key {
        case "any", "none":                    self = .any
        case "shift", "shift_held":            self = .shiftHeld
        case "shift_not_held", "no_shift":     self = .shiftNotHeld
        case "control", "control_held":        self = .controlHeld
        case "control_not_held", "no_control": self = .controlNotHeld
        case "option", "option_held", "alt":    self = .optionHeld
        case "option_not_held", "no_option":   self = .optionNotHeld
        case "command", "command_held":        self = .commandHeld
        case "command_not_held", "no_command": self = .commandNotHeld
        case "no_modifiers":                   self = .noModifiers
        default:                               return nil
        }
    }

    var yamlValue: String? {
        switch self {
        case .any:            return nil
        case .shiftHeld:      return "shift_held"
        case .shiftNotHeld:   return "shift_not_held"
        case .controlHeld:    return "control_held"
        case .controlNotHeld: return "control_not_held"
        case .optionHeld:     return "option_held"
        case .optionNotHeld:  return "option_not_held"
        case .commandHeld:    return "command_held"
        case .commandNotHeld: return "command_not_held"
        case .noModifiers:    return "no_modifiers"
        }
    }
}

/// Snapshot of modifier keys at gesture start.
struct CapturedModifiers: Equatable {
    let shift: Bool
    let control: Bool
    let option: Bool
    let command: Bool

    init(_ flags: NSEvent.ModifierFlags) {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        shift   = f.contains(.shift)
        control = f.contains(.control)
        option  = f.contains(.option)
        command = f.contains(.command)
    }

    func matches(_ filter: ModifierFilter) -> Bool {
        switch filter {
        case .any:            return true
        case .shiftHeld:      return shift
        case .shiftNotHeld:   return !shift
        case .controlHeld:    return control
        case .controlNotHeld: return !control
        case .optionHeld:     return option
        case .optionNotHeld:  return !option
        case .commandHeld:    return command
        case .commandNotHeld: return !command
        case .noModifiers:    return !shift && !control && !option && !command
        }
    }
}

enum WindowStateFilter: String, Codable, CaseIterable {
    case any            = "Any"
    case fullscreen     = "Fullscreen"
    case notFullscreen  = "Not Fullscreen"
    case maximized      = "Maximized"
    case notMaximized   = "Not Maximized"

    /// Legacy `app_filter` values in config.yaml.
    init?(legacyAppFilter value: String) {
        switch value.uppercased() {
        case "FULLSCREEN":     self = .fullscreen
        case "NOT_FULLSCREEN": self = .notFullscreen
        case "MAXIMIZED":      self = .maximized
        case "NOT_MAXIMIZED":  self = .notMaximized
        default:                return nil
        }
    }

    init?(yamlValue: String?) {
        guard let yamlValue else { return nil }
        if let legacy = WindowStateFilter(legacyAppFilter: yamlValue) {
            self = legacy
            return
        }
        switch yamlValue.lowercased().replacingOccurrences(of: "_", with: "") {
        case "fullscreen":     self = .fullscreen
        case "notfullscreen":  self = .notFullscreen
        case "maximized":      self = .maximized
        case "notmaximized":   self = .notMaximized
        default:                return nil
        }
    }

    var yamlValue: String? {
        switch self {
        case .any:            return nil
        case .fullscreen:     return "fullscreen"
        case .notFullscreen:  return "not_fullscreen"
        case .maximized:      return "maximized"
        case .notMaximized:   return "not_maximized"
        }
    }
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
    case screenshotArea            = "Screenshot (Area)"
    case screenshotFull            = "Screenshot (Full)"
    case screenshotAreaClipboard   = "Screenshot (Area → Clipboard)"
    case screenshotFullClipboard   = "Screenshot (Full → Clipboard)"
    case screenshotToolbar         = "Screenshot Toolbar"
    case copy                      = "Copy"
    case paste                     = "Paste"
    case cut                       = "Cut"
    case undo                      = "Undo"
    case redo                      = "Redo"
    case selectAll                 = "Select All"
    case find                      = "Find"
    case emojiPicker               = "Emoji & Symbols"
    case reloadPage                = "Reload Page"
    case newTab                    = "New Tab"
    case volumeUp                  = "Volume Up"
    case volumeDown                = "Volume Down"
    case mute                      = "Mute"
    case playPause                 = "Play / Pause"
    case nextTrack                 = "Next Track"
    case previousTrack             = "Previous Track"
    case brightnessUp              = "Brightness Up"
    case brightnessDown            = "Brightness Down"
    case emptyTrash                = "Empty Trash"
    case openFinder                = "Open Finder"
    case openDownloads             = "Open Downloads"
    case doNothing        = "Do Nothing"

    /// Grouped for the preferences action picker.
    static let catalog: [(category: String, actions: [GestureAction])] = [
        ("Apps", [.quitApp, .forceQuitApp, .quitFrontmost, .hideApp, .hideOthers, .openApp,
                  .appSwitcherNext, .appSwitcherPrev, .switchAppNext, .switchAppPrev]),
        ("Windows", [.minimizeWindow, .minimizeAllApps, .restoreMinimizedApps, .maximizeWindow,
                     .restoreWindow, .closeWindow, .enterFullscreen, .exitFullscreen, .toggleFullscreen,
                     .cycleWindows, .snapLeft, .snapRight, .snapTopLeft, .snapTopRight,
                     .snapBottomLeft, .snapBottomRight, .centerWindow, .moveNextDisplay]),
        ("Screenshots", [.screenshotArea, .screenshotFull, .screenshotAreaClipboard,
                         .screenshotFullClipboard, .screenshotToolbar]),
        ("Editing", [.copy, .paste, .cut, .undo, .redo, .selectAll, .find, .emojiPicker, .reloadPage, .newTab]),
        ("Media & Display", [.volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .previousTrack,
                             .brightnessUp, .brightnessDown]),
        ("System", [.missionControl, .appExpose, .showDesktop, .launchpad, .spotlight, .notifCenter,
                    .lockScreen, .sleep, .emptyTrash, .openFinder, .openDownloads]),
        ("Other", [.doNothing]),
    ]

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

/// Identifies rules that compete for the same gesture slot (latest in the list wins).
struct GestureMatchSignature: Hashable {
    let fingers: Int
    let direction: GestureDirection
    let speed: GestureSpeed
    let appFilter: String?
    let windowStateFilter: WindowStateFilter
    let modifierFilter: ModifierFilter
}

struct GestureRule: Codable, Identifiable, Equatable {
    var id        = UUID()
    var fingers:   Int              = 3
    var direction: GestureDirection = .click
    var speed:     GestureSpeed     = .normal
    var action:    GestureAction    = .doNothing
    var appPath:   String?
    /// Bundle ID (e.g. `com.apple.Safari`) — not window-state keywords.
    var appFilter: String?
    var windowStateFilter: WindowStateFilter = .any
    var modifierFilter: ModifierFilter = .any
    var reciprocalEnabled: Bool     = true
    /// New rules start as drafts until configured in the editor.
    var isDraft: Bool               = false

    var matchSignature: GestureMatchSignature {
        GestureMatchSignature(
            fingers: fingers,
            direction: direction,
            speed: (speed == .any || direction == .click) ? .normal : speed,
            appFilter: appFilter,
            windowStateFilter: windowStateFilter,
            modifierFilter: modifierFilter
        )
    }

    /// Rules the gesture engine will consider.
    var isActive: Bool { !isDraft && action != .doNothing }

    static func newDraft() -> GestureRule {
        var rule = GestureRule(fingers: 3, direction: .click, speed: .normal, action: .doNothing)
        rule.isDraft = true
        return rule
    }

    init(fingers: Int, direction: GestureDirection, speed: GestureSpeed = .normal,
         action: GestureAction, appPath: String? = nil, appFilter: String? = nil,
         windowStateFilter: WindowStateFilter = .any,
         modifierFilter: ModifierFilter = .any,
         reciprocalEnabled: Bool = true, isDraft: Bool = false) {
        self.fingers             = fingers
        self.direction           = direction
        self.speed               = speed
        self.action              = action
        self.appPath             = appPath
        self.appFilter           = appFilter
        self.windowStateFilter   = windowStateFilter
        self.modifierFilter      = modifierFilter
        self.reciprocalEnabled   = reciprocalEnabled
        self.isDraft             = isDraft
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
        windowStateFilter = (try? c.decodeIfPresent(WindowStateFilter.self, forKey: .windowStateFilter)) ?? .any
        modifierFilter    = (try? c.decodeIfPresent(ModifierFilter.self,    forKey: .modifierFilter))    ?? .any
        reciprocalEnabled = (try? c.decodeIfPresent(Bool.self,  forKey: .reciprocalEnabled)) ?? true
        isDraft           = (try? c.decodeIfPresent(Bool.self,  forKey: .isDraft)) ?? false
        self = Self.migratingLegacyAppFilter(self)
    }

    /// Moves window-state keywords out of `appFilter` (legacy config.yaml).
    static func migratingLegacyAppFilter(_ rule: GestureRule) -> GestureRule {
        var r = rule
        guard let filter = r.appFilter else { return r }
        if let state = WindowStateFilter(legacyAppFilter: filter) {
            if r.windowStateFilter == .any { r.windowStateFilter = state }
            r.appFilter = nil
        }
        return r
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
    var slowVelocityThreshold:      Float        = 0.004
    var speedSampleCount:           Int          = 5
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
        slowVelocityThreshold     = try c.decodeIfPresent(Float.self,        forKey: .slowVelocityThreshold)     ?? 0.004
        speedSampleCount          = try c.decodeIfPresent(Int.self,          forKey: .speedSampleCount)          ?? 5
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
        _rules = Self.normalizeRules(Self.defaultRules)
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
        set { _rules = Self.normalizeRules(newValue); GlideConfigStore.shared.scheduleSave() }
    }

    var tuning: GestureTuning {
        get { _tuning }
        set { _tuning = Self.normalizedTuning(newValue); GlideConfigStore.shared.scheduleSave() }
    }

    var windowTargetingMode: WindowTargetingMode {
        get { _windowTargeting }
        set { _windowTargeting = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    var hapticFeedbackEnabled: Bool {
        get { _hapticFeedback }
        set { _hapticFeedback = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    var debugLoggingEnabled: Bool {
        get { _debugLogging }
        set { _debugLogging = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    var launchAtLoginEnabled: Bool {
        get { _launchAtLogin }
        set { _launchAtLogin = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    func resetTuning() { tuning = GestureTuning() }

    // MARK: Batch load — bypasses per-field saves (called by GlideConfigStore.load)

    func apply(_ config: GlideConfig) {
        _rules           = Self.normalizeRules(config.toRules())
        _tuning          = Self.normalizedTuning(config.toTuning())
        _windowTargeting = WindowTargetingMode(rawValue: config.preferences.windowTargeting) ?? .focusedThenCursor
        _hapticFeedback  = config.preferences.hapticFeedback
        _debugLogging    = config.preferences.debugLogging
        _launchAtLogin   = config.preferences.launchAtLogin
    }

    // MARK: Rule normalization (duplicates are allowed — latest match wins at runtime)

    private static func normalizeRules(_ rules: [GestureRule]) -> [GestureRule] {
        rules.map { normalizedRule($0) }
    }

    private static func normalizedRule(_ rule: GestureRule) -> GestureRule {
        var r = GestureRule.migratingLegacyAppFilter(rule)
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
