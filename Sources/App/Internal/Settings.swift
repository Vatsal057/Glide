import Cocoa

// ─────────────────────────────────────────────
// MARK: - Enums
// ─────────────────────────────────────────────

enum GestureDirection: String, Codable, CaseIterable {
    case click           = "Click"
    case forceClick      = "Force Click"
    case tapHold         = "Tap & Hold"
    case swipeLeftRight  = "Left / Right"
    case swipeUpDown     = "Up / Down"
    case swipeLeft       = "Swipe Left"
    case swipeRight      = "Swipe Right"
    case swipeUp         = "Swipe Up"
    case swipeDown       = "Swipe Down"

    /// True for tap-style gestures (normal click, force click, tap & hold) that
    /// have no axis, speed, reciprocal or continuous behaviour.
    var isClickLike: Bool { self == .click || self == .forceClick || self == .tapHold }

    /// Directions with a movement axis — the only ones with speed tiers.
    var hasSpeed: Bool { !isClickLike }
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

    /// True when the rule only fires if a specific modifier is held (not .any / .noModifiers / *NotHeld).
    var requiresModifierHeld: Bool {
        switch self {
        case .shiftHeld, .controlHeld, .optionHeld, .commandHeld: return true
        default: return false
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
    case customMenuItem            = "Menu Item…"
    case customShortcut            = "Keyboard Shortcut…"
    case advancedKeyboard          = "Advanced Keyboard…"
    case runShortcut               = "Run Shortcut…"
    case runShellCommand           = "Shell Command…"
    case runAppleScript            = "AppleScript…"
    case playPause                 = "Play / Pause"
    case nextTrack                 = "Next Track"
    case previousTrack             = "Previous Track"
    case volumeUp                  = "Volume Up"
    case volumeDown                = "Volume Down"
    case muteToggle                = "Mute / Unmute"
    case brightnessUp              = "Brightness Up"
    case brightnessDown            = "Brightness Down"
    case emptyTrash                = "Empty Trash"
    case openFinder                = "Open Finder"
    case openDownloads             = "Open Downloads"
    case doNothing        = "Do Nothing"

    /// Grouped for the preferences action picker.
    static let catalog: [(category: String, actions: [GestureAction])] = [
        ("Apps", [.quitApp, .forceQuitApp, .quitFrontmost, .hideApp, .hideOthers, .openApp,
                  .switchAppNext, .switchAppPrev]),
        ("Windows", [.minimizeWindow, .minimizeAllApps, .restoreMinimizedApps, .maximizeWindow,
                     .restoreWindow, .closeWindow, .enterFullscreen, .exitFullscreen, .toggleFullscreen,
                     .cycleWindows, .snapLeft, .snapRight, .snapTopLeft, .snapTopRight,
                     .snapBottomLeft, .snapBottomRight, .centerWindow, .moveNextDisplay]),
        ("Screenshots", [.screenshotArea, .screenshotFull, .screenshotAreaClipboard,
                         .screenshotFullClipboard, .screenshotToolbar]),
        ("Media", [.playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown,
                   .muteToggle, .brightnessUp, .brightnessDown]),
        ("Custom", [.customMenuItem, .customShortcut, .advancedKeyboard,
                    .runShortcut, .runShellCommand, .runAppleScript]),
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
        case .volumeUp:          return .volumeDown
        case .volumeDown:        return .volumeUp
        case .brightnessUp:      return .brightnessDown
        case .brightnessDown:    return .brightnessUp
        case .nextTrack:         return .previousTrack
        case .previousTrack:     return .nextTrack
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
    let zone: TrackpadZone
    let speed: GestureSpeed
    let appFilter: String?
    let windowStateFilter: WindowStateFilter
    let modifierFilter: ModifierFilter
}

struct GestureRule: Codable, Identifiable, Equatable {
    var id        = UUID()
    /// Optional user-given label ("Zoom out in Photos"). Empty/nil → auto label.
    var name:      String?
    var fingers:   Int              = 3
    var direction: GestureDirection = .click
    /// Trackpad corner a force-click must land in. Only meaningful when
    /// `direction == .forceClick`; `.any` for every other gesture.
    var zone:      TrackpadZone     = .any
    var speed:     GestureSpeed     = .normal
    var action:    GestureAction    = .doNothing
    var appPath:   String?
    /// Bundle ID (e.g. `com.apple.Safari`) — not window-state keywords.
    var appFilter: String?
    var windowStateFilter: WindowStateFilter = .any
    var modifierFilter: ModifierFilter = .any
    var reciprocalEnabled: Bool     = true
    var reciprocalAction: GestureAction?
    /// Runs a begin/update/end lifecycle while fingers remain down and keep moving.
    var continuous: Bool            = false
    var continuousNegativeAction: GestureAction = .doNothing
    var continuousPositiveAction: GestureAction = .doNothing
    var continuousEndAction:      GestureAction = .doNothing
    var advancedKeyboard:          [KeyboardInputStep] = []
    var continuousNegativeShortcut: KeyboardShortcut?
    var continuousPositiveShortcut: KeyboardShortcut?
    var continuousEndShortcut:      KeyboardShortcut?
    var continuousBeginKeyboard:    [KeyboardInputStep] = []
    var continuousNegativeKeyboard: [KeyboardInputStep] = []
    var continuousPositiveKeyboard: [KeyboardInputStep] = []
    var continuousEndKeyboard:      [KeyboardInputStep] = []
    /// Menu path for `.customMenuItem`, e.g. `["File", "New Tab"]`.
    var menuItemPath: [String]?
    /// Key combo for `.customShortcut`.
    var customShortcut: KeyboardShortcut?
    /// Shortcuts.app shortcut name for `.runShortcut`.
    var shortcutName: String?
    /// Script text for `.runShellCommand` / `.runAppleScript`.
    var script: String?
    /// Per-gesture haptic override. nil → automatic (pattern assigned to the
    /// action's category in Preferences › General › Haptics).
    var hapticPattern: HapticPattern?
    /// New rules start as drafts until configured in the editor.
    var isDraft: Bool               = false
    /// Marks this rule as triggered by a global keyboard shortcut instead of a
    /// trackpad gesture. When true, the gesture fields (fingers/direction/speed)
    /// are ignored and `triggerShortcut` fires the action from anywhere.
    var isKeyboardBinding: Bool     = false
    /// Global hotkey that fires this rule's action (only when `isKeyboardBinding`).
    var triggerShortcut: KeyboardShortcut?

    var menuItemLabel: String? {
        guard action == .customMenuItem, let menuItemPath, !menuItemPath.isEmpty else { return nil }
        return menuItemPath.joined(separator: " › ")
    }

    /// Custom name if set, otherwise a label derived from the action.
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if action == .customShortcut, let s = customShortcut, s.isValid {
            return "Shortcut: \(s.displayString)"
        }
        if action == .advancedKeyboard, !advancedKeyboard.isEmpty {
            return "Advanced Keyboard"
        }
        return menuItemLabel ?? action.rawValue
    }

    /// True when the trigger combo can be registered as a global hotkey.
    var triggerIsRegisterable: Bool {
        guard let sc = triggerShortcut else { return false }
        return HotkeyTrigger.isRegisterable(keyCode: Int(sc.keyCode), command: sc.command,
                                            shift: sc.shift, control: sc.control, option: sc.option)
    }

    var isActive: Bool {
        if isDraft { return false }
        if isKeyboardBinding && !triggerIsRegisterable { return false }
        if continuous {
            return Self.actionIsConfigured(action, shortcut: customShortcut, keyboard: advancedKeyboard)
                || Self.actionIsConfigured(continuousNegativeAction, shortcut: continuousNegativeShortcut, keyboard: continuousNegativeKeyboard)
                || Self.actionIsConfigured(continuousPositiveAction, shortcut: continuousPositiveShortcut, keyboard: continuousPositiveKeyboard)
                || Self.actionIsConfigured(continuousEndAction, shortcut: continuousEndShortcut, keyboard: continuousEndKeyboard)
        }
        if action == .doNothing { return false }
        if action == .customMenuItem {
            return menuItemPath != nil && (menuItemPath?.count ?? 0) >= 2
        }
        if action == .customShortcut {
            return customShortcut?.isValid == true
        }
        if action == .advancedKeyboard {
            return !advancedKeyboard.isEmpty
        }
        if action == .openApp { return appPath != nil && !(appPath?.isEmpty ?? true) }
        if action == .runShortcut {
            return !(shortcutName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        if action == .runShellCommand || action == .runAppleScript {
            return !(script ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var supportsContinuousGestures: Bool {
        direction == .swipeLeftRight || direction == .swipeUpDown
    }

    private static func actionIsConfigured(_ action: GestureAction, shortcut: KeyboardShortcut?, keyboard: [KeyboardInputStep]) -> Bool {
        switch action {
        case .doNothing:
            return false
        case .customShortcut:
            return shortcut?.isValid == true
        case .advancedKeyboard:
            return !keyboard.isEmpty
        default:
            return true
        }
    }

    var matchSignature: GestureMatchSignature {
        GestureMatchSignature(
            fingers: fingers,
            direction: direction,
            zone: direction == .forceClick ? zone : .any,
            speed: (speed == .any || !direction.hasSpeed) ? .normal : speed,
            appFilter: appFilter,
            windowStateFilter: windowStateFilter,
            modifierFilter: modifierFilter
        )
    }

    static func newDraft() -> GestureRule {
        var rule = GestureRule(fingers: 3, direction: .click, speed: .normal, action: .doNothing)
        rule.isDraft = true
        return rule
    }

    static func newKeyboardDraft() -> GestureRule {
        var rule = GestureRule(fingers: 3, direction: .click, speed: .normal, action: .doNothing)
        rule.isKeyboardBinding = true
        rule.isDraft = true
        return rule
    }

    init(name: String? = nil,
         fingers: Int, direction: GestureDirection, speed: GestureSpeed = .normal,
         action: GestureAction, appPath: String? = nil, appFilter: String? = nil,
         windowStateFilter: WindowStateFilter = .any,
         modifierFilter: ModifierFilter = .any,
         reciprocalEnabled: Bool = true, reciprocalAction: GestureAction? = nil,
         continuous: Bool = false,
         continuousNegativeAction: GestureAction = .doNothing,
         continuousPositiveAction: GestureAction = .doNothing,
         continuousEndAction: GestureAction = .doNothing,
         advancedKeyboard: [KeyboardInputStep] = [],
         continuousNegativeShortcut: KeyboardShortcut? = nil,
         continuousPositiveShortcut: KeyboardShortcut? = nil,
         continuousEndShortcut: KeyboardShortcut? = nil,
         continuousBeginKeyboard: [KeyboardInputStep] = [],
         continuousNegativeKeyboard: [KeyboardInputStep] = [],
         continuousPositiveKeyboard: [KeyboardInputStep] = [],
         continuousEndKeyboard: [KeyboardInputStep] = [],
         menuItemPath: [String]? = nil, customShortcut: KeyboardShortcut? = nil,
         shortcutName: String? = nil, script: String? = nil,
         isDraft: Bool = false,
         isKeyboardBinding: Bool = false, triggerShortcut: KeyboardShortcut? = nil) {
        self.name                = name
        self.fingers             = fingers
        self.direction           = direction
        self.speed               = speed
        self.action              = action
        self.appPath             = appPath
        self.appFilter           = appFilter
        self.windowStateFilter   = windowStateFilter
        self.modifierFilter      = modifierFilter
        self.reciprocalEnabled   = reciprocalEnabled
        self.reciprocalAction    = reciprocalAction
        self.continuous          = continuous
        self.continuousNegativeAction = continuousNegativeAction
        self.continuousPositiveAction = continuousPositiveAction
        self.continuousEndAction      = continuousEndAction
        self.advancedKeyboard = advancedKeyboard
        self.continuousNegativeShortcut = continuousNegativeShortcut
        self.continuousPositiveShortcut = continuousPositiveShortcut
        self.continuousEndShortcut = continuousEndShortcut
        self.continuousBeginKeyboard = continuousBeginKeyboard
        self.continuousNegativeKeyboard = continuousNegativeKeyboard
        self.continuousPositiveKeyboard = continuousPositiveKeyboard
        self.continuousEndKeyboard = continuousEndKeyboard
        self.menuItemPath        = menuItemPath
        self.customShortcut      = customShortcut
        self.shortcutName        = shortcutName
        self.script              = script
        self.isDraft             = isDraft
        self.isKeyboardBinding   = isKeyboardBinding
        self.triggerShortcut     = triggerShortcut
    }

    // Robust decoding — tolerates unknown future enum cases
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decodeIfPresent(UUID.self,          forKey: .id))        ?? UUID()
        name      = try? c.decodeIfPresent(String.self,         forKey: .name)
        fingers   = (try? c.decode(Int.self,                    forKey: .fingers))   ?? 3
        direction = (try? c.decode(GestureDirection.self,       forKey: .direction)) ?? .click
        speed     = (try? c.decodeIfPresent(GestureSpeed.self,  forKey: .speed))     ?? .normal
        action    = (try? c.decode(GestureAction.self,          forKey: .action))    ?? .doNothing
        appPath   = try? c.decodeIfPresent(String.self,         forKey: .appPath)
        appFilter = try? c.decodeIfPresent(String.self,         forKey: .appFilter)
        windowStateFilter = (try? c.decodeIfPresent(WindowStateFilter.self, forKey: .windowStateFilter)) ?? .any
        modifierFilter    = (try? c.decodeIfPresent(ModifierFilter.self,    forKey: .modifierFilter))    ?? .any
        reciprocalEnabled = (try? c.decodeIfPresent(Bool.self,  forKey: .reciprocalEnabled)) ?? true
        reciprocalAction  = try? c.decodeIfPresent(GestureAction.self, forKey: .reciprocalAction)
        continuous        = (try? c.decodeIfPresent(Bool.self, forKey: .continuous)) ?? false
        continuousNegativeAction = (try? c.decodeIfPresent(GestureAction.self, forKey: .continuousNegativeAction)) ?? .doNothing
        continuousPositiveAction = (try? c.decodeIfPresent(GestureAction.self, forKey: .continuousPositiveAction)) ?? .doNothing
        continuousEndAction      = (try? c.decodeIfPresent(GestureAction.self, forKey: .continuousEndAction)) ?? .doNothing
        advancedKeyboard         = (try? c.decodeIfPresent([KeyboardInputStep].self, forKey: .advancedKeyboard)) ?? []
        continuousNegativeShortcut = try? c.decodeIfPresent(KeyboardShortcut.self, forKey: .continuousNegativeShortcut)
        continuousPositiveShortcut = try? c.decodeIfPresent(KeyboardShortcut.self, forKey: .continuousPositiveShortcut)
        continuousEndShortcut      = try? c.decodeIfPresent(KeyboardShortcut.self, forKey: .continuousEndShortcut)
        continuousBeginKeyboard    = (try? c.decodeIfPresent([KeyboardInputStep].self, forKey: .continuousBeginKeyboard)) ?? []
        continuousNegativeKeyboard = (try? c.decodeIfPresent([KeyboardInputStep].self, forKey: .continuousNegativeKeyboard)) ?? []
        continuousPositiveKeyboard = (try? c.decodeIfPresent([KeyboardInputStep].self, forKey: .continuousPositiveKeyboard)) ?? []
        continuousEndKeyboard      = (try? c.decodeIfPresent([KeyboardInputStep].self, forKey: .continuousEndKeyboard)) ?? []
        menuItemPath      = try? c.decodeIfPresent([String].self, forKey: .menuItemPath)
        customShortcut    = try? c.decodeIfPresent(KeyboardShortcut.self, forKey: .customShortcut)
        shortcutName      = try? c.decodeIfPresent(String.self, forKey: .shortcutName)
        script            = try? c.decodeIfPresent(String.self, forKey: .script)
        isDraft           = (try? c.decodeIfPresent(Bool.self,  forKey: .isDraft)) ?? false
        isKeyboardBinding = (try? c.decodeIfPresent(Bool.self,  forKey: .isKeyboardBinding)) ?? false
        triggerShortcut   = try? c.decodeIfPresent(KeyboardShortcut.self, forKey: .triggerShortcut)
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

/// Hold-to-browse app switcher (Cmd+Tab overlay). Separate from the gesture rule list.
struct AppSwitcherSettings: Codable, Equatable {
    var enabled: Bool = true
    /// Always 3 — horizontal swipes with three fingers are reserved for the switcher.
    var fingers: Int = 3
    /// Skip Finder in the switcher when it has no open windows.
    var skipWindowlessFinder: Bool = true
    /// Unminimize windows of the selected app when you release the gesture.
    var restoreMinimizedOnCommit: Bool = true

    static func normalized(_ s: AppSwitcherSettings) -> AppSwitcherSettings {
        var n = s
        n.fingers = 3
        return n
    }
}

/// Which speed classifier decides slow/normal/fast.
enum SpeedLogic: String, Codable, CaseIterable {
    /// Average speed (distance ÷ time) at trigger distance. Deterministic, two thresholds.
    case simple
    /// Multi-signal: peak/median velocity, acceleration, hold windows. Original feel.
    case classic
}

struct GestureTuning: Codable, Equatable {
    var initialThreshold:           Float        = 0.014
    var appSwitcherStepThreshold:   Float        = 0.003
    var appSwitcherDebounce:        TimeInterval = 0.10
    var continuousStepThreshold:    Float        = 0.025
    var continuousDebounce:         TimeInterval = 0.08
    var fastVelocityThreshold:      Float        = 0.009
    var slowVelocityThreshold:      Float        = 0.005
    var speedLogic:                 SpeedLogic   = .simple
    var candidateFrames:            Int          = 3
    var pinchSpreadThreshold:       Float        = 0.015
    var pinchFrameSpreadThreshold:  Float        = 0.008
    var swipeCoherenceThreshold:    Float        = 0.30
    var swipeAngleTolerance:        Float        = 45
    /// Motionless contact time (seconds) before a Tap & Hold gesture fires.
    var tapHoldDuration:            TimeInterval = 0.5
    /// Each corner's reach (normalized) for zoned force-clicks. 0.35 → outer 35%
    /// on each axis counts as that corner; the middle stays position-blind.
    var forceClickCornerMargin:     Float        = 0.35
    var edgeMarginEnabled:          Bool         = true
    var edgeMargin:                 EdgeMargin   = EdgeMargin()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        initialThreshold          = try c.decodeIfPresent(Float.self,        forKey: .initialThreshold)          ?? 0.014
        appSwitcherStepThreshold  = try c.decodeIfPresent(Float.self,        forKey: .appSwitcherStepThreshold)  ?? 0.003
        appSwitcherDebounce       = try c.decodeIfPresent(TimeInterval.self, forKey: .appSwitcherDebounce)       ?? 0.10
        continuousStepThreshold   = try c.decodeIfPresent(Float.self,        forKey: .continuousStepThreshold)   ?? 0.025
        continuousDebounce        = try c.decodeIfPresent(TimeInterval.self, forKey: .continuousDebounce)        ?? 0.08
        fastVelocityThreshold     = try c.decodeIfPresent(Float.self,        forKey: .fastVelocityThreshold)     ?? 0.009
        slowVelocityThreshold     = try c.decodeIfPresent(Float.self,        forKey: .slowVelocityThreshold)     ?? 0.005
        speedLogic                = (try? c.decodeIfPresent(SpeedLogic.self, forKey: .speedLogic))
                                    .flatMap { $0 }                                                              ?? .simple
        candidateFrames           = try c.decodeIfPresent(Int.self,          forKey: .candidateFrames)           ?? 3
        pinchSpreadThreshold      = try c.decodeIfPresent(Float.self,        forKey: .pinchSpreadThreshold)      ?? 0.015
        pinchFrameSpreadThreshold = try c.decodeIfPresent(Float.self,        forKey: .pinchFrameSpreadThreshold) ?? 0.008
        swipeCoherenceThreshold   = try c.decodeIfPresent(Float.self,        forKey: .swipeCoherenceThreshold)   ?? 0.30
        swipeAngleTolerance       = try c.decodeIfPresent(Float.self,        forKey: .swipeAngleTolerance)       ?? 45
        tapHoldDuration           = try c.decodeIfPresent(TimeInterval.self, forKey: .tapHoldDuration)           ?? 0.5
        forceClickCornerMargin    = try c.decodeIfPresent(Float.self,        forKey: .forceClickCornerMargin)    ?? 0.35
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
        _rules = Self.normalizeRules(Self.defaultRules, appSwitcher: _appSwitcher)
    }

    // MARK: Backing stores

    private var _rules:           [GestureRule]
    private var _appSwitcher:     AppSwitcherSettings = AppSwitcherSettings()
    /// Guards `_tuning` — the only setting read off the main thread (the MT
    /// callback reads edge margins every frame).
    private let tuningLock = NSLock()
    private var _tuning:          GestureTuning       = GestureTuning()
    private var _windowTargeting: WindowTargetingMode = .focusedThenCursor
    private var _hapticFeedback:  Bool                = true
    private var _hapticAssignments: [HapticEvent: HapticPattern] = HapticEvent.defaultAssignments
    private var _debugLogging:    Bool                = false
    private var _launchAtLogin:   Bool                = false
    private var _autoDisableNativeGestures: Bool      = false

    // MARK: Public interface

    var rules: [GestureRule] {
        get { _rules }
        set { _rules = Self.normalizeRules(newValue, appSwitcher: _appSwitcher); GlideConfigStore.shared.scheduleSave() }
    }

    var appSwitcher: AppSwitcherSettings {
        get { _appSwitcher }
        set { _appSwitcher = AppSwitcherSettings.normalized(newValue); GlideConfigStore.shared.scheduleSave() }
    }

    var tuning: GestureTuning {
        get { tuningLock.lock(); defer { tuningLock.unlock() }; return _tuning }
        set {
            let normalized = Self.normalizedTuning(newValue)
            tuningLock.lock(); _tuning = normalized; tuningLock.unlock()
            GlideConfigStore.shared.scheduleSave()
        }
    }

    var windowTargetingMode: WindowTargetingMode {
        get { _windowTargeting }
        set { _windowTargeting = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    var hapticFeedbackEnabled: Bool {
        get { _hapticFeedback }
        set { _hapticFeedback = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    var hapticAssignments: [HapticEvent: HapticPattern] {
        get { _hapticAssignments }
        set { _hapticAssignments = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    func hapticPattern(for event: HapticEvent) -> HapticPattern {
        _hapticAssignments[event] ?? event.defaultPattern
    }

    var debugLoggingEnabled: Bool {
        get { _debugLogging }
        set { _debugLogging = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    var launchAtLoginEnabled: Bool {
        get { _launchAtLogin }
        set { _launchAtLogin = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    var autoDisableNativeGestures: Bool {
        get { _autoDisableNativeGestures }
        set { _autoDisableNativeGestures = newValue; GlideConfigStore.shared.scheduleSave() }
    }

    func resetTuning() { tuning = GestureTuning() }

    // MARK: Batch load — bypasses per-field saves (called by GlideConfigStore.load)

    func apply(_ config: GlideConfig) {
        var switcher = config.toAppSwitcher()
        var loadedRules = config.toRules()
        Self.migrateLegacyAppSwitcherRules(into: &switcher, rules: &loadedRules)
        _appSwitcher     = AppSwitcherSettings.normalized(switcher)
        _rules           = Self.normalizeRules(loadedRules, appSwitcher: _appSwitcher)
        let normalizedTuning = Self.normalizedTuning(config.toTuning())
        tuningLock.lock(); _tuning = normalizedTuning; tuningLock.unlock()
        _windowTargeting = WindowTargetingMode(rawValue: config.preferences.windowTargeting) ?? .focusedThenCursor
        _hapticFeedback  = config.preferences.hapticFeedback
        _hapticAssignments = HapticEvent.defaultAssignments.merging(
            config.haptics.compactMap { key, value -> (HapticEvent, HapticPattern)? in
                guard let event = HapticEvent(rawValue: key), let pattern = HapticPattern(rawValue: value) else { return nil }
                return (event, pattern)
            },
            uniquingKeysWith: { _, loaded in loaded }
        )
        _debugLogging    = config.preferences.debugLogging
        _launchAtLogin   = config.preferences.launchAtLogin
        _autoDisableNativeGestures = config.preferences.autoDisableNativeGestures
    }

    // MARK: App Switcher ↔ gesture rules

    static func isAppSwitcherAction(_ action: GestureAction) -> Bool {
        action == .appSwitcherNext || action == .appSwitcherPrev
    }

    /// Pulls legacy app-switcher gesture rules into `AppSwitcherSettings` and removes them from the list.
    static func migrateLegacyAppSwitcherRules(into switcher: inout AppSwitcherSettings, rules: inout [GestureRule]) {
        guard rules.contains(where: { isAppSwitcherAction($0.action) }) else { return }
        if !switcher.enabled { switcher.enabled = true }
        rules.removeAll { isAppSwitcherAction($0.action) }
    }

    /// Removes horizontal swipe rules that would conflict with the reserved app-switcher slot.
    /// Removes horizontal swipe rules that would conflict with app switcher (plain swipes only).
    static func stripReservedHorizontalSwipes(from rules: inout [GestureRule], fingerCount: Int) {
        rules.removeAll {
            $0.fingers == fingerCount &&
            ($0.direction == .swipeLeft || $0.direction == .swipeRight || $0.direction == .swipeLeftRight) &&
            !$0.modifierFilter.requiresModifierHeld
        }
    }

    // MARK: Rule normalization (duplicates are allowed — latest match wins at runtime)

    private static func normalizeRules(_ rules: [GestureRule], appSwitcher: AppSwitcherSettings) -> [GestureRule] {
        var copy = rules
        copy.removeAll { isAppSwitcherAction($0.action) }
        if appSwitcher.enabled {
            stripReservedHorizontalSwipes(from: &copy, fingerCount: appSwitcher.fingers)
        }
        return copy.map { normalizedRule($0) }
    }

    static func normalizedRule(_ rule: GestureRule) -> GestureRule {
        var r = GestureRule.migratingLegacyAppFilter(rule)
        r.fingers = min(max(r.fingers, 2), 5)
        r.speed   = (r.speed == .any || !r.direction.hasSpeed) ? .normal : r.speed
        if r.direction.isClickLike {
            r.reciprocalEnabled = false
            r.continuous = false
            r.continuousNegativeAction = .doNothing
            r.continuousPositiveAction = .doNothing
            r.continuousEndAction = .doNothing
            r.continuousNegativeShortcut = nil
            r.continuousPositiveShortcut = nil
            r.continuousEndShortcut = nil
            r.continuousBeginKeyboard = []
            r.continuousNegativeKeyboard = []
            r.continuousPositiveKeyboard = []
            r.continuousEndKeyboard = []
        }
        if !r.supportsContinuousGestures {
            r.continuous = false
            r.continuousNegativeAction = .doNothing
            r.continuousPositiveAction = .doNothing
            r.continuousEndAction = .doNothing
            r.continuousNegativeShortcut = nil
            r.continuousPositiveShortcut = nil
            r.continuousEndShortcut = nil
            r.continuousBeginKeyboard = []
            r.continuousNegativeKeyboard = []
            r.continuousPositiveKeyboard = []
            r.continuousEndKeyboard = []
        }
        if r.continuous {
            r.reciprocalEnabled = false
            r.reciprocalAction = nil
            if r.action == .doNothing, !r.continuousBeginKeyboard.isEmpty {
                r.action = .advancedKeyboard
                r.advancedKeyboard = r.continuousBeginKeyboard
                r.continuousBeginKeyboard = []
            }
        }
        return r
    }

    // Single authoritative tuning normalizer — also called by PreferencesStore
    static func normalizedTuning(_ t: GestureTuning) -> GestureTuning {
        var n = t
        n.initialThreshold         = max(0.005, n.initialThreshold)
        n.appSwitcherStepThreshold = max(0.001, n.appSwitcherStepThreshold)
        n.appSwitcherDebounce      = max(0.0,   n.appSwitcherDebounce)
        n.continuousStepThreshold  = max(0.005, min(n.continuousStepThreshold, 0.12))
        n.continuousDebounce       = max(0.0, min(n.continuousDebounce, 0.5))
        n.slowVelocityThreshold    = max(0.001, min(n.slowVelocityThreshold, 0.020))
        n.fastVelocityThreshold    = max(n.slowVelocityThreshold + 0.001,
                                         max(0.003, min(n.fastVelocityThreshold, 0.030)))
        n.candidateFrames          = max(1, min(n.candidateFrames, 8))
        n.pinchSpreadThreshold     = max(0.002, n.pinchSpreadThreshold)
        n.pinchFrameSpreadThreshold = max(0.001, n.pinchFrameSpreadThreshold)
        n.swipeCoherenceThreshold  = max(0.0, min(n.swipeCoherenceThreshold, 0.95))
        n.swipeAngleTolerance      = max(20, min(n.swipeAngleTolerance, 45))
        n.tapHoldDuration          = max(0.3, min(n.tapHoldDuration, 3.0))
        n.forceClickCornerMargin   = max(0.15, min(n.forceClickCornerMargin, 0.45))
        let clamp = { (v: Float) in max(EdgeMargin.range.lowerBound,
                                        min(v, EdgeMargin.range.upperBound)) }
        n.edgeMargin.left   = clamp(n.edgeMargin.left)
        n.edgeMargin.right  = clamp(n.edgeMargin.right)
        n.edgeMargin.top    = clamp(n.edgeMargin.top)
        n.edgeMargin.bottom = clamp(n.edgeMargin.bottom)
        return n
    }

    // MARK: Defaults

    static let defaultAppSwitcher = AppSwitcherSettings(enabled: true, fingers: 3)

    static let defaultRules: [GestureRule] = [
        GestureRule(fingers: 3, direction: .click,      action: .quitApp),
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


import Cocoa
import CoreGraphics

/// User-defined key combination for `.customShortcut` gesture actions.
struct KeyboardShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var command: Bool = false
    var shift: Bool = false
    var control: Bool = false
    var option: Bool = false

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift   { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        if option  { flags.insert(.maskAlternate) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option  { parts.append("⌥") }
        if shift   { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(KeyCodeLabels.name(for: keyCode))
        return parts.joined()
    }

    // keyCode 0 is the A key — "not set" is modeled by a nil KeyboardShortcut,
    // so every constructed shortcut is valid.
    var isValid: Bool { true }

    init(keyCode: UInt16, command: Bool = false, shift: Bool = false,
         control: Bool = false, option: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.control = control
        self.option = option
    }

    init?(yamlKeyCode: Int?, modifiers: [String]?) {
        guard let yamlKeyCode, yamlKeyCode >= 0 else { return nil }
        keyCode = UInt16(yamlKeyCode)
        command = false; shift = false; control = false; option = false
        for mod in modifiers ?? [] {
            switch mod.lowercased() {
            case "command", "cmd":  command = true
            case "shift":           shift = true
            case "control", "ctrl": control = true
            case "option", "alt":   option = true
            default: break
            }
        }
    }

    var yamlModifiers: [String] {
        var mods: [String] = []
        if command { mods.append("command") }
        if shift   { mods.append("shift") }
        if control { mods.append("control") }
        if option  { mods.append("option") }
        return mods
    }
}

enum KeyCodeLabels {
    static func name(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x24: return "Return"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x32: return "`"
        case 0x33: return "Delete"
        case 0x35: return "Esc"
        case 0x36, 0x37: return "⌘"
        case 0x38: return "⇧"
        case 0x39: return "Caps Lock"
        case 0x3A: return "⌥"
        case 0x3B: return "⌃"
        // Codes below follow HIToolbox Events.h (kVK_*).
        case 0x3C: return "Right ⇧"
        case 0x3D: return "Right ⌥"
        case 0x3E: return "Right ⌃"
        case 0x3F: return "Fn"
        case 0x40: return "F17"
        case 0x41: return "Keypad ."
        case 0x43: return "Keypad *"
        case 0x45: return "Keypad +"
        case 0x47: return "Keypad Clear"
        case 0x48: return "Volume Up"
        case 0x49: return "Volume Down"
        case 0x4A: return "Mute"
        case 0x4B: return "Keypad /"
        case 0x4C: return "Keypad ⏎"
        case 0x4E: return "Keypad -"
        case 0x4F: return "F18"
        case 0x50: return "F19"
        case 0x51: return "Keypad ="
        case 0x52: return "Keypad 0"
        case 0x53: return "Keypad 1"
        case 0x54: return "Keypad 2"
        case 0x55: return "Keypad 3"
        case 0x56: return "Keypad 4"
        case 0x57: return "Keypad 5"
        case 0x58: return "Keypad 6"
        case 0x59: return "Keypad 7"
        case 0x5A: return "F20"
        case 0x5B: return "Keypad 8"
        case 0x5C: return "Keypad 9"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x63: return "F3"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x67: return "F11"
        case 0x69: return "F13"
        case 0x6A: return "F16"
        case 0x6B: return "F14"
        case 0x6D: return "F10"
        case 0x6F: return "F12"
        case 0x71: return "F15"
        case 0x72: return "Help"
        case 0x73: return "Home"
        case 0x74: return "Page Up"
        case 0x75: return "Forward Delete"
        case 0x76: return "F4"
        case 0x77: return "End"
        case 0x78: return "F2"
        case 0x79: return "Page Down"
        case 0x7A: return "F1"
        case 0x7B: return "Left"
        case 0x7C: return "Right"
        case 0x7D: return "Down"
        case 0x7E: return "Up"
        default:   return "Key \(keyCode)"
        }
    }

    static func keyCode(forToken token: String) -> UInt16? {
        switch token.lowercased().replacingOccurrences(of: "_", with: "") {
        case "tab": return 0x30
        case "space": return 0x31
        case "return", "enter": return 0x24
        case "esc", "escape": return 0x35
        case "delete", "backspace": return 0x33
        case "left", "leftarrow": return 0x7B
        case "right", "rightarrow": return 0x7C
        case "down", "downarrow": return 0x7D
        case "up", "uparrow": return 0x7E
        case "leftalt", "rightalt", "alt", "option", "leftoption": return 0x3A
        case "leftshift", "rightshift", "shift": return 0x38
        case "leftcmd", "cmd", "command", "leftcommand": return 0x37
        case "rightcmd", "rightcommand": return 0x36
        case "leftctrl", "rightctrl", "ctrl", "control", "leftcontrol", "rightcontrol": return 0x3B
        default:
            if token.lowercased().hasPrefix("key"),
               let value = UInt16(token.dropFirst(3)) {
                return value
            }
            return nil
        }
    }

    static func tokenName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x24: return "return"
        case 0x35: return "escape"
        case 0x33: return "delete"
        case 0x7B: return "left"
        case 0x7C: return "right"
        case 0x7D: return "down"
        case 0x7E: return "up"
        case 0x3A: return "leftalt"
        case 0x38: return "leftshift"
        case 0x37: return "leftcmd"
        case 0x36: return "rightcmd"
        case 0x3B: return "leftctrl"
        default: return "key\(keyCode)"
        }
    }
}

enum KeyboardInputEvent: String, Codable, CaseIterable {
    case tap = "tap"
    case hold = "hold"
    case release = "release"

    var label: String {
        switch self {
        case .tap: return "Tap"
        case .hold: return "Hold"
        case .release: return "Release"
        }
    }
}

struct KeyboardInputStep: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var event: KeyboardInputEvent = .tap
    var keyCode: UInt16 = 0x30
    var command: Bool = false
    var shift: Bool = false
    var control: Bool = false
    var option: Bool = false

    private enum CodingKeys: String, CodingKey {
        case event, keyCode, command, shift, control, option
    }

    var modifierFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        return flags
    }

    var displayString: String {
        let prefix: String
        switch event {
        case .tap: prefix = "Tap "
        case .hold: prefix = "Hold "
        case .release: prefix = "Release "
        }
        var mods: [String] = []
        if control { mods.append("⌃") }
        if option { mods.append("⌥") }
        if shift { mods.append("⇧") }
        if command { mods.append("⌘") }
        return prefix + mods.joined() + KeyCodeLabels.name(for: keyCode)
    }

    init(event: KeyboardInputEvent = .tap, keyCode: UInt16 = 0x30,
         command: Bool = false, shift: Bool = false, control: Bool = false, option: Bool = false) {
        self.event = event
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.control = control
        self.option = option
    }

    init?(token: String) {
        var raw = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }

        if raw.hasPrefix("+") {
            event = .hold
            raw.removeFirst()
        } else if raw.hasPrefix("-") {
            event = .release
            raw.removeFirst()
        } else {
            event = .tap
        }

        var command = false, shift = false, control = false, option = false
        let parts = raw.components(separatedBy: "+").filter { !$0.isEmpty }
        guard let keyToken = parts.last, let keyCode = KeyCodeLabels.keyCode(forToken: keyToken) else { return nil }
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command", "leftcmd": command = true
            case "shift", "leftshift": shift = true
            case "ctrl", "control", "leftctrl": control = true
            case "alt", "option", "leftalt": option = true
            default: break
            }
        }
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.control = control
        self.option = option
    }

    var token: String {
        let key = KeyCodeLabels.tokenName(for: keyCode)
        switch event {
        case .hold:
            return "+\(key)"
        case .release:
            return "-\(key)"
        case .tap:
            var parts: [String] = []
            if command { parts.append("leftcmd") }
            if shift { parts.append("leftshift") }
            if control { parts.append("leftctrl") }
            if option { parts.append("leftalt") }
            parts.append(key)
            return parts.joined(separator: "+")
        }
    }
}
