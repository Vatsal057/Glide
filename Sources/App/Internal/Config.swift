import Foundation

// ─────────────────────────────────────────────
// MARK: - GlideConfig (top-level model)
// ─────────────────────────────────────────────

/// Full serializable representation of Glide settings.
/// Mirrors the config.yaml schema:
///
///   touchpad:
///     speed: { swipe_threshold, fast_velocity_threshold, ... }
///     preferences: { window_targeting, haptic_feedback, ... }
///     tuning: { ... }
///     gestures:
///       - { type, direction, fingers, speed, action, app_filter, app_path, reciprocal }
///
struct GlideConfig {

    struct Speed {
        var swipeThreshold: Float = 0.014
        var fastVelocityThreshold: Float = 0.009
        var slowVelocityThreshold: Float = 0.005
        var speedSampleCount: Int = 4
    }

    struct Preferences {
        var windowTargeting: String = "Focused Window First"
        var hapticFeedback: Bool = true
        var debugLogging: Bool = false
        var launchAtLogin: Bool = false
    }

    struct AppSwitcher {
        var enabled: Bool = true
        var fingers: Int = 3
        var useMRUOrdering: Bool = true
        var skipWindowlessFinder: Bool = true
        var restoreMinimizedOnCommit: Bool = true
    }

    struct Tuning {
        var appSwitcherStepThreshold: Float = 0.003
        var appSwitcherDebounce: Double = 0.10
        var continuousStepThreshold: Float = 0.025
        var continuousDebounce: Double = 0.08
        var candidateFrames: Int = 3
        var pinchSpreadThreshold: Float = 0.015
        var pinchFrameSpreadThreshold: Float = 0.008
        var swipeCoherenceThreshold: Float = 0.30
        var swipeAngleTolerance: Float = 45.0
        var edgeMarginEnabled: Bool = true
        var edgeMarginLeft: Float = 0.05
        var edgeMarginRight: Float = 0.05
        var edgeMarginTop: Float = 0.05
        var edgeMarginBottom: Float = 0.05
    }

    struct Gesture {
        var type: String            // "swipe" | "click"
        var direction: String?      // "up" | "down" | "left" | "right" — nil for click
        var fingers: Int
        var speed: String?          // "slow" | "normal" | "fast" — nil for click
        var action: String
        var appFilter: String?
        var windowState: String?
        var modifierFilter: String?
        var appPath: String?
        var menuPath: [String]?
        var shortcutKeyCode: Int?
        var shortcutModifiers: [String]?
        var advancedKeyboard: [String]?
        var reciprocal: Bool
        var continuous: Bool = false
        var continuousNegativeAction: String?
        var continuousPositiveAction: String?
        var continuousEndAction: String?
        var continuousNegativeShortcutKeyCode: Int?
        var continuousNegativeShortcutModifiers: [String]?
        var continuousPositiveShortcutKeyCode: Int?
        var continuousPositiveShortcutModifiers: [String]?
        var continuousEndShortcutKeyCode: Int?
        var continuousEndShortcutModifiers: [String]?
        var continuousBeginKeyboard: [String]?
        var continuousNegativeKeyboard: [String]?
        var continuousPositiveKeyboard: [String]?
        var continuousEndKeyboard: [String]?
        var draft: Bool = false
    }

    var speed: Speed = Speed()
    var preferences: Preferences = Preferences()
    var appSwitcher: AppSwitcher = AppSwitcher()
    var tuning: Tuning = Tuning()
    var gestures: [Gesture] = []
}

// ─────────────────────────────────────────────
// MARK: - GlideConfig ↔ Settings bridge
// ─────────────────────────────────────────────

extension GlideConfig {

    // ── Build a GlideConfig from current in-memory Settings ──

    static func fromSettings() -> GlideConfig {
        let s = Settings.shared
        let t = s.tuning
        var cfg = GlideConfig()

        cfg.speed.swipeThreshold         = t.initialThreshold
        cfg.speed.fastVelocityThreshold  = t.fastVelocityThreshold
        cfg.speed.slowVelocityThreshold  = t.slowVelocityThreshold
        cfg.speed.speedSampleCount       = t.speedSampleCount

        cfg.preferences.windowTargeting  = s.windowTargetingMode.rawValue
        cfg.preferences.hapticFeedback   = s.hapticFeedbackEnabled
        cfg.preferences.debugLogging     = s.debugLoggingEnabled
        cfg.preferences.launchAtLogin    = s.launchAtLoginEnabled

        cfg.appSwitcher.enabled = s.appSwitcher.enabled
        cfg.appSwitcher.fingers = s.appSwitcher.fingers
        cfg.appSwitcher.useMRUOrdering = s.appSwitcher.useMRUOrdering
        cfg.appSwitcher.skipWindowlessFinder = s.appSwitcher.skipWindowlessFinder
        cfg.appSwitcher.restoreMinimizedOnCommit = s.appSwitcher.restoreMinimizedOnCommit

        cfg.tuning.appSwitcherStepThreshold  = t.appSwitcherStepThreshold
        cfg.tuning.appSwitcherDebounce       = t.appSwitcherDebounce
        cfg.tuning.continuousStepThreshold   = t.continuousStepThreshold
        cfg.tuning.continuousDebounce        = t.continuousDebounce
        cfg.tuning.candidateFrames           = t.candidateFrames
        cfg.tuning.pinchSpreadThreshold      = t.pinchSpreadThreshold
        cfg.tuning.pinchFrameSpreadThreshold = t.pinchFrameSpreadThreshold
        cfg.tuning.swipeCoherenceThreshold   = t.swipeCoherenceThreshold
        cfg.tuning.swipeAngleTolerance       = t.swipeAngleTolerance
        cfg.tuning.edgeMarginEnabled         = t.edgeMarginEnabled
        cfg.tuning.edgeMarginLeft            = t.edgeMargin.left
        cfg.tuning.edgeMarginRight           = t.edgeMargin.right
        cfg.tuning.edgeMarginTop             = t.edgeMargin.top
        cfg.tuning.edgeMarginBottom          = t.edgeMargin.bottom

        cfg.gestures = s.rules.map { rule in
            let isClick = rule.direction == .click
            let normalized = GestureRule.migratingLegacyAppFilter(rule)
            return GlideConfig.Gesture(
                type:        isClick ? "click" : "swipe",
                direction:   isClick ? nil     : yamlDirection(rule.direction),
                fingers:     rule.fingers,
                speed:       isClick ? nil     : rule.speed.rawValue.lowercased(),
                action:      rule.action.rawValue,
                appFilter:      normalized.appFilter,
                windowState:    normalized.windowStateFilter.yamlValue,
                modifierFilter: normalized.modifierFilter.yamlValue,
                appPath:        rule.appPath,
                menuPath:       rule.menuItemPath,
                shortcutKeyCode: rule.customShortcut.map { Int($0.keyCode) },
                shortcutModifiers: rule.customShortcut?.yamlModifiers,
                advancedKeyboard: rule.advancedKeyboard.map(\.token).nilIfEmpty,
                reciprocal:  rule.reciprocalEnabled,
                continuous:  rule.continuous,
                continuousNegativeAction: rule.continuousNegativeAction == .doNothing ? nil : rule.continuousNegativeAction.rawValue,
                continuousPositiveAction: rule.continuousPositiveAction == .doNothing ? nil : rule.continuousPositiveAction.rawValue,
                continuousEndAction:      rule.continuousEndAction == .doNothing ? nil : rule.continuousEndAction.rawValue,
                continuousNegativeShortcutKeyCode: rule.continuousNegativeAction == .customShortcut ? rule.continuousNegativeShortcut.map { Int($0.keyCode) } : nil,
                continuousNegativeShortcutModifiers: rule.continuousNegativeAction == .customShortcut ? rule.continuousNegativeShortcut?.yamlModifiers : nil,
                continuousPositiveShortcutKeyCode: rule.continuousPositiveAction == .customShortcut ? rule.continuousPositiveShortcut.map { Int($0.keyCode) } : nil,
                continuousPositiveShortcutModifiers: rule.continuousPositiveAction == .customShortcut ? rule.continuousPositiveShortcut?.yamlModifiers : nil,
                continuousEndShortcutKeyCode: rule.continuousEndAction == .customShortcut ? rule.continuousEndShortcut.map { Int($0.keyCode) } : nil,
                continuousEndShortcutModifiers: rule.continuousEndAction == .customShortcut ? rule.continuousEndShortcut?.yamlModifiers : nil,
                continuousBeginKeyboard: rule.continuousBeginKeyboard.map(\.token).nilIfEmpty,
                continuousNegativeKeyboard: rule.continuousNegativeAction == .advancedKeyboard ? rule.continuousNegativeKeyboard.map(\.token).nilIfEmpty : nil,
                continuousPositiveKeyboard: rule.continuousPositiveAction == .advancedKeyboard ? rule.continuousPositiveKeyboard.map(\.token).nilIfEmpty : nil,
                continuousEndKeyboard: rule.continuousEndAction == .advancedKeyboard ? rule.continuousEndKeyboard.map(\.token).nilIfEmpty : nil,
                draft:       rule.isDraft
            )
        }
        return cfg
    }

    // ── Convert to Settings-domain types (used by Settings.apply(_:)) ──

    func toAppSwitcher() -> AppSwitcherSettings {
        var s = AppSwitcherSettings()
        s.enabled = appSwitcher.enabled
        s.fingers = appSwitcher.fingers
        s.useMRUOrdering = appSwitcher.useMRUOrdering
        s.skipWindowlessFinder = appSwitcher.skipWindowlessFinder
        s.restoreMinimizedOnCommit = appSwitcher.restoreMinimizedOnCommit
        return AppSwitcherSettings.normalized(s)
    }

    func toTuning() -> GestureTuning {
        var t = GestureTuning()
        t.initialThreshold          = speed.swipeThreshold
        t.fastVelocityThreshold     = speed.fastVelocityThreshold
        t.slowVelocityThreshold     = speed.slowVelocityThreshold
        t.speedSampleCount          = speed.speedSampleCount
        t.appSwitcherStepThreshold  = tuning.appSwitcherStepThreshold
        t.appSwitcherDebounce       = tuning.appSwitcherDebounce
        t.continuousStepThreshold   = tuning.continuousStepThreshold
        t.continuousDebounce        = tuning.continuousDebounce
        t.candidateFrames           = tuning.candidateFrames
        t.pinchSpreadThreshold      = tuning.pinchSpreadThreshold
        t.pinchFrameSpreadThreshold = tuning.pinchFrameSpreadThreshold
        t.swipeCoherenceThreshold   = tuning.swipeCoherenceThreshold
        t.swipeAngleTolerance       = tuning.swipeAngleTolerance
        t.edgeMarginEnabled         = tuning.edgeMarginEnabled
        t.edgeMargin.left           = tuning.edgeMarginLeft
        t.edgeMargin.right          = tuning.edgeMarginRight
        t.edgeMargin.top            = tuning.edgeMarginTop
        t.edgeMargin.bottom         = tuning.edgeMarginBottom
        return t
    }

    func toRules() -> [GestureRule] {
        gestures.compactMap { g in
            guard !g.action.isEmpty, let action = GestureAction(rawValue: g.action) else { return nil }

            let direction: GestureDirection
            if g.type == "click" {
                direction = .click
            } else {
                guard let d = swiftDirection(g.direction) else { return nil }
                direction = d
            }

            let speed: GestureSpeed = {
                switch g.speed?.lowercased() {
                case "slow": return .slow
                case "fast": return .fast
                default:     return .normal
                }
            }()

            let migrated = GestureRule.migratingLegacyAppFilter(GestureRule(
                fingers:   g.fingers,
                direction: direction,
                speed:     speed,
                action:    action,
                appPath:   g.appPath,
                appFilter: g.appFilter,
                windowStateFilter: WindowStateFilter(yamlValue: g.windowState) ?? .any,
                modifierFilter:    ModifierFilter(yamlValue: g.modifierFilter) ?? .any,
                reciprocalEnabled: g.reciprocal,
                continuous:        g.continuous,
                continuousNegativeAction: g.continuousNegativeAction.flatMap(GestureAction.init(rawValue:)) ?? .doNothing,
                continuousPositiveAction: g.continuousPositiveAction.flatMap(GestureAction.init(rawValue:)) ?? .doNothing,
                continuousEndAction:      g.continuousEndAction.flatMap(GestureAction.init(rawValue:)) ?? .doNothing,
                advancedKeyboard:          (g.advancedKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousNegativeShortcut: KeyboardShortcut(yamlKeyCode: g.continuousNegativeShortcutKeyCode,
                                                             modifiers: g.continuousNegativeShortcutModifiers),
                continuousPositiveShortcut: KeyboardShortcut(yamlKeyCode: g.continuousPositiveShortcutKeyCode,
                                                             modifiers: g.continuousPositiveShortcutModifiers),
                continuousEndShortcut:      KeyboardShortcut(yamlKeyCode: g.continuousEndShortcutKeyCode,
                                                             modifiers: g.continuousEndShortcutModifiers),
                continuousBeginKeyboard:    (g.continuousBeginKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousNegativeKeyboard: (g.continuousNegativeKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousPositiveKeyboard: (g.continuousPositiveKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                continuousEndKeyboard:      (g.continuousEndKeyboard ?? []).compactMap(KeyboardInputStep.init(token:)),
                menuItemPath:      g.menuPath,
                customShortcut:    KeyboardShortcut(yamlKeyCode: g.shortcutKeyCode,
                                                     modifiers: g.shortcutModifiers),
                isDraft:           g.draft
            ))
            return migrated
        }
    }

    // ── Direction helpers ──

    private static func yamlDirection(_ d: GestureDirection) -> String {
        switch d {
        case .swipeLeftRight: return "left_right"
        case .swipeUpDown:    return "up_down"
        case .swipeLeft:  return "left"
        case .swipeRight: return "right"
        case .swipeUp:    return "up"
        case .swipeDown:  return "down"
        case .click:      return "none"
        }
    }

    private func swiftDirection(_ s: String?) -> GestureDirection? {
        switch s?.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "left_right", "leftright", "horizontal", "x": return .swipeLeftRight
        case "up_down", "updown", "vertical", "y":         return .swipeUpDown
        case "left":  return .swipeLeft
        case "right": return .swipeRight
        case "up":    return .swipeUp
        case "down":  return .swipeDown
        default:      return nil
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - YAML Serializer
// ─────────────────────────────────────────────

enum GlideConfigSerializer {

    static func serialize(_ config: GlideConfig) -> String {
        var lines: [String] = [
            "# Glide Configuration",
            "# Generated by Glide — import via Preferences › General › Import Config",
            "#",
            "touchpad:",
            "",
            "  # ── Speed & Velocity ──────────────────────────────",
            "  speed:",
            "    swipe_threshold: \(fmt(config.speed.swipeThreshold))",
            "    fast_velocity_threshold: \(fmt(config.speed.fastVelocityThreshold))",
            "    slow_velocity_threshold: \(fmt(config.speed.slowVelocityThreshold))",
            "    speed_sample_count: \(config.speed.speedSampleCount)",
            "",
            "  # ── Preferences ────────────────────────────────────",
            "  preferences:",
            "    window_targeting: \"\(config.preferences.windowTargeting)\"",
            "    haptic_feedback: \(config.preferences.hapticFeedback ? "true" : "false")",
            "    debug_logging: \(config.preferences.debugLogging ? "true" : "false")",
            "    launch_at_login: \(config.preferences.launchAtLogin ? "true" : "false")",
            "",
            "  # ── App Switcher (hold + swipe to browse, release to confirm) ──",
            "  app_switcher:",
            "    enabled: \(config.appSwitcher.enabled ? "true" : "false")",
            "    fingers: \(config.appSwitcher.fingers)",
            "    use_mru_ordering: \(config.appSwitcher.useMRUOrdering ? "true" : "false")",
            "    skip_windowless_finder: \(config.appSwitcher.skipWindowlessFinder ? "true" : "false")",
            "    restore_minimized_on_commit: \(config.appSwitcher.restoreMinimizedOnCommit ? "true" : "false")",
            "",
            "  # ── Tuning ─────────────────────────────────────────",
            "  tuning:",
            "    app_switcher_step_threshold: \(fmt(config.tuning.appSwitcherStepThreshold))",
            "    app_switcher_debounce: \(String(format: "%.2f", config.tuning.appSwitcherDebounce))",
            "    continuous_step_threshold: \(fmt(config.tuning.continuousStepThreshold))",
            "    continuous_debounce: \(String(format: "%.2f", config.tuning.continuousDebounce))",
            "    candidate_frames: \(config.tuning.candidateFrames)",
            "    pinch_spread_threshold: \(fmt(config.tuning.pinchSpreadThreshold))",
            "    pinch_frame_spread_threshold: \(fmt(config.tuning.pinchFrameSpreadThreshold))",
            "    swipe_coherence_threshold: \(fmt(config.tuning.swipeCoherenceThreshold))",
            "    swipe_angle_tolerance: \(String(format: "%.1f", config.tuning.swipeAngleTolerance))",
            "",
            "    edge_margin:",
            "      enabled: \(config.tuning.edgeMarginEnabled ? "true" : "false")",
            "      left: \(fmt(config.tuning.edgeMarginLeft))",
            "      right: \(fmt(config.tuning.edgeMarginRight))",
            "      top: \(fmt(config.tuning.edgeMarginTop))",
            "      bottom: \(fmt(config.tuning.edgeMarginBottom))",
            "",
            "  # ── Gestures ────────────────────────────────────────",
            "  gestures:",
        ]

        let grouped = Dictionary(grouping: config.gestures) { $0.fingers }
        for fingers in grouped.keys.sorted() {
            let bar = String(repeating: "#", count: 49)
            lines += [
                "",
                "    \(bar)",
                "    # 🔹 \("\(fingers)-FINGER GESTURES")",
                "    \(bar)",
            ]
            for g in grouped[fingers]! {
                lines += serializeGesture(g)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func serializeGesture(_ g: GlideConfig.Gesture) -> [String] {
        var lines: [String] = [""]
        let comment = "\(g.fingers)-finger \(g.type)\(g.direction.map { " \($0)" } ?? "")\(g.speed.map { " (\($0))" } ?? "") → \(g.action)"
        lines.append("    # \(comment)")
        lines.append("    - type: \(g.type)")
        if let d = g.direction { lines.append("      direction: \(d)") }
        lines.append("      fingers: \(g.fingers)")
        if let s = g.speed { lines.append("      speed: \(s)") }
        if g.draft { lines.append("      draft: true") }
        lines.append("      action: \"\(escape(g.action))\"")
        if let ws = g.windowState { lines.append("      window_state: \(ws)") }
        if let mf = g.modifierFilter { lines.append("      modifier_filter: \(mf)") }
        lines.append("      app_filter: \(g.appFilter.map { "\"\($0)\"" } ?? "null")")
        if g.type == "swipe" || g.appPath != nil {
            lines.append("      app_path: \(g.appPath.map { "\"\(escape($0))\"" } ?? "null")")
            lines.append("      reciprocal: \(g.reciprocal ? "true" : "false")")
            if g.type == "swipe" {
                lines.append("      continuous: \(g.continuous ? "true" : "false")")
                if let action = g.continuousNegativeAction {
                    lines.append("      continuous_update_negative_action: \"\(escape(action))\"")
                }
                if let action = g.continuousPositiveAction {
                    lines.append("      continuous_update_positive_action: \"\(escape(action))\"")
                }
                if let action = g.continuousEndAction {
                    lines.append("      continuous_end_action: \"\(escape(action))\"")
                }
                if g.continuousNegativeAction == GestureAction.advancedKeyboard.rawValue {
                    appendStringList(g.continuousNegativeKeyboard, key: "continuous_update_negative_keyboard", to: &lines)
                }
                if g.continuousPositiveAction == GestureAction.advancedKeyboard.rawValue {
                    appendStringList(g.continuousPositiveKeyboard, key: "continuous_update_positive_keyboard", to: &lines)
                }
                if g.continuousEndAction == GestureAction.advancedKeyboard.rawValue {
                    appendStringList(g.continuousEndKeyboard, key: "continuous_end_keyboard", to: &lines)
                }
            }
        }
        if g.action == GestureAction.customMenuItem.rawValue, let path = g.menuPath, !path.isEmpty {
            lines.append("      menu_path:")
            for segment in path {
                lines.append("        - \"\(escape(segment))\"")
            }
        }
        if g.action == GestureAction.customShortcut.rawValue, let code = g.shortcutKeyCode {
            lines.append("      shortcut_key_code: \(code)")
            if let mods = g.shortcutModifiers, !mods.isEmpty {
                lines.append("      shortcut_modifiers:")
                for mod in mods {
                    lines.append("        - \(mod)")
                }
            }
        }
        if g.action == GestureAction.advancedKeyboard.rawValue {
            appendStringList(g.advancedKeyboard, key: "advanced_keyboard", to: &lines)
        }
        if g.continuousNegativeAction == GestureAction.customShortcut.rawValue {
            appendShortcut(g.continuousNegativeShortcutKeyCode, modifiers: g.continuousNegativeShortcutModifiers,
                           keyPrefix: "continuous_update_negative", to: &lines)
        }
        if g.continuousPositiveAction == GestureAction.customShortcut.rawValue {
            appendShortcut(g.continuousPositiveShortcutKeyCode, modifiers: g.continuousPositiveShortcutModifiers,
                           keyPrefix: "continuous_update_positive", to: &lines)
        }
        if g.continuousEndAction == GestureAction.customShortcut.rawValue {
            appendShortcut(g.continuousEndShortcutKeyCode, modifiers: g.continuousEndShortcutModifiers,
                           keyPrefix: "continuous_end", to: &lines)
        }
        return lines
    }

    private static func fmt(_ v: Float) -> String { String(format: "%.3f", v) }

    private static func appendStringList(_ values: [String]?, key: String, to lines: inout [String]) {
        guard let values, !values.isEmpty else { return }
        lines.append("      \(key):")
        for value in values {
            lines.append("        - \"\(escape(value))\"")
        }
    }

    private static func appendShortcut(_ keyCode: Int?, modifiers: [String]?, keyPrefix: String, to lines: inout [String]) {
        guard let keyCode else { return }
        lines.append("      \(keyPrefix)_shortcut_key_code: \(keyCode)")
        if let modifiers, !modifiers.isEmpty {
            lines.append("      \(keyPrefix)_shortcut_modifiers:")
            for modifier in modifiers {
                lines.append("        - \(modifier)")
            }
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// ─────────────────────────────────────────────
// MARK: - YAML Parser
// ─────────────────────────────────────────────

enum GlideConfigParser {

    static func parse(yaml: String) -> GlideConfig? {
        let lines = yaml.components(separatedBy: "\n")
        var cfg = GlideConfig()
        var i = 0

        guard scanToKey("touchpad", in: lines, from: &i) else { return nil }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (indent, key, _) = tokenize(line)
            if indent == 0 && key != nil && key != "touchpad" { break }
            switch key {
            case "speed":       i += 1; parseSpeed(lines, from: &i, parentIndent: indent, into: &cfg.speed)
            case "preferences":  i += 1; parsePreferences(lines, from: &i, parentIndent: indent, into: &cfg.preferences)
            case "app_switcher": i += 1; parseAppSwitcher(lines, from: &i, parentIndent: indent, into: &cfg.appSwitcher)
            case "tuning":       i += 1; parseTuning(lines, from: &i, parentIndent: indent, into: &cfg.tuning)
            case "gestures":    i += 1; parseGestures(lines, from: &i, parentIndent: indent, into: &cfg.gestures); return cfg
            default:            i += 1
            }
        }
        return cfg
    }

    private static func parseSpeed(_ lines: [String], from i: inout Int, parentIndent: Int, into speed: inout GlideConfig.Speed) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "swipe_threshold":          speed.swipeThreshold         = floatVal(val) ?? speed.swipeThreshold
            case "fast_velocity_threshold":  speed.fastVelocityThreshold  = floatVal(val) ?? speed.fastVelocityThreshold
            case "slow_velocity_threshold":  speed.slowVelocityThreshold  = floatVal(val) ?? speed.slowVelocityThreshold
            case "speed_sample_count":       speed.speedSampleCount       = intVal(val)   ?? speed.speedSampleCount
            default: break
            }
            i += 1
        }
    }

    private static func parsePreferences(_ lines: [String], from i: inout Int, parentIndent: Int, into prefs: inout GlideConfig.Preferences) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "window_targeting": prefs.windowTargeting = stringVal(val) ?? prefs.windowTargeting
            case "haptic_feedback":  prefs.hapticFeedback  = boolVal(val)   ?? prefs.hapticFeedback
            case "debug_logging":    prefs.debugLogging    = boolVal(val)   ?? prefs.debugLogging
            case "launch_at_login":  prefs.launchAtLogin   = boolVal(val)   ?? prefs.launchAtLogin
            default: break
            }
            i += 1
        }
    }

    private static func parseAppSwitcher(_ lines: [String], from i: inout Int, parentIndent: Int, into switcher: inout GlideConfig.AppSwitcher) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "enabled": switcher.enabled = boolVal(val) ?? switcher.enabled
            case "fingers": switcher.fingers = intVal(val) ?? switcher.fingers
            case "use_mru_ordering": switcher.useMRUOrdering = boolVal(val) ?? switcher.useMRUOrdering
            case "skip_windowless_finder": switcher.skipWindowlessFinder = boolVal(val) ?? switcher.skipWindowlessFinder
            case "restore_minimized_on_commit": switcher.restoreMinimizedOnCommit = boolVal(val) ?? switcher.restoreMinimizedOnCommit
            default: break
            }
            i += 1
        }
    }

    private static func parseTuning(_ lines: [String], from i: inout Int, parentIndent: Int, into tuning: inout GlideConfig.Tuning) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "app_switcher_step_threshold":  tuning.appSwitcherStepThreshold  = floatVal(val)  ?? tuning.appSwitcherStepThreshold
            case "app_switcher_debounce":        tuning.appSwitcherDebounce       = doubleVal(val) ?? tuning.appSwitcherDebounce
            case "continuous_step_threshold":     tuning.continuousStepThreshold   = floatVal(val)  ?? tuning.continuousStepThreshold
            case "continuous_debounce":           tuning.continuousDebounce        = doubleVal(val) ?? tuning.continuousDebounce
            case "candidate_frames":             tuning.candidateFrames           = intVal(val)    ?? tuning.candidateFrames
            case "pinch_spread_threshold":       tuning.pinchSpreadThreshold      = floatVal(val)  ?? tuning.pinchSpreadThreshold
            case "pinch_frame_spread_threshold": tuning.pinchFrameSpreadThreshold = floatVal(val)  ?? tuning.pinchFrameSpreadThreshold
            case "swipe_coherence_threshold":    tuning.swipeCoherenceThreshold   = floatVal(val)  ?? tuning.swipeCoherenceThreshold
            case "swipe_angle_tolerance":        tuning.swipeAngleTolerance       = floatVal(val)  ?? tuning.swipeAngleTolerance
            case "edge_margin":
                let marginIndent = ind
                i += 1
                parseEdgeMargin(lines, from: &i, parentIndent: marginIndent, into: &tuning)
                continue
            default: break
            }
            i += 1
        }
    }

    private static func parseEdgeMargin(_ lines: [String], from i: inout Int, parentIndent: Int, into tuning: inout GlideConfig.Tuning) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let (ind, key, val) = tokenize(line)
            if ind <= parentIndent { return }
            switch key {
            case "enabled": tuning.edgeMarginEnabled = boolVal(val)  ?? tuning.edgeMarginEnabled
            case "left":    tuning.edgeMarginLeft    = floatVal(val) ?? tuning.edgeMarginLeft
            case "right":   tuning.edgeMarginRight   = floatVal(val) ?? tuning.edgeMarginRight
            case "top":     tuning.edgeMarginTop     = floatVal(val) ?? tuning.edgeMarginTop
            case "bottom":  tuning.edgeMarginBottom  = floatVal(val) ?? tuning.edgeMarginBottom
            default: break
            }
            i += 1
        }
    }

    private static func parseGestures(_ lines: [String], from i: inout Int, parentIndent: Int, into gestures: inout [GlideConfig.Gesture]) {
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            
            let ind = leadingSpaces(line)
            if ind <= parentIndent { return }
            
            if trimmed.hasPrefix("-") {
                let g = parseGestureBlock(lines, from: &i, blockIndent: ind)
                if !g.type.isEmpty && !g.action.isEmpty { gestures.append(g) }
                continue
            }
            i += 1
        }
    }

    private static func parseStringList(_ lines: [String], from i: inout Int, parentIndent: Int) -> [String]? {
        var items: [String] = []
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { i += 1; continue }
            let ind = leadingSpaces(lines[i])
            if ind <= parentIndent { break }
            if line.hasPrefix("-") {
                let item = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if let s = stringVal(String(item)) { items.append(s) }
                i += 1
                continue
            }
            break
        }
        return items.isEmpty ? nil : items
    }

    private static func parseMenuPathList(_ lines: [String], from i: inout Int, parentIndent: Int) -> [String]? {
        var path: [String] = []
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { i += 1; continue }
            let ind = leadingSpaces(lines[i])
            if ind <= parentIndent { break }
            if line.hasPrefix("-") {
                let item = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if let s = stringVal(String(item)) { path.append(s) }
                i += 1
                continue
            }
            break
        }
        return path.isEmpty ? nil : path
    }

    private static func parseGestureBlock(_ lines: [String], from i: inout Int, blockIndent: Int) -> GlideConfig.Gesture {
        var g = GlideConfig.Gesture(type: "", direction: nil, fingers: 3,
                                    speed: nil, action: "", appFilter: nil, windowState: nil,
                                    modifierFilter: nil, appPath: nil, menuPath: nil,
                                    shortcutKeyCode: nil, shortcutModifiers: nil,
                                    advancedKeyboard: nil,
                                    reciprocal: true, continuous: false,
                                    continuousNegativeAction: nil,
                                    continuousPositiveAction: nil,
                                    continuousEndAction: nil,
                                    continuousNegativeShortcutKeyCode: nil,
                                    continuousNegativeShortcutModifiers: nil,
                                    continuousPositiveShortcutKeyCode: nil,
                                    continuousPositiveShortcutModifiers: nil,
                                    continuousEndShortcutKeyCode: nil,
                                    continuousEndShortcutModifiers: nil,
                                    continuousBeginKeyboard: nil,
                                    continuousNegativeKeyboard: nil,
                                    continuousPositiveKeyboard: nil,
                                    continuousEndKeyboard: nil,
                                    draft: false)
        let firstLine = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
        if let colon = firstLine.firstIndex(of: ":") {
            let k = String(firstLine[..<colon]).trimmingCharacters(in: .whitespaces)
            let v = String(firstLine[firstLine.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if k == "type" { g.type = v }
        }
        i += 1
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            
            let ind = leadingSpaces(line)
            if ind <= blockIndent { return g }
            
            let (_, key, val) = tokenize(line)
            switch key {
            case "type":       g.type      = val ?? g.type
            case "direction":  g.direction = val
            case "fingers":    g.fingers   = intVal(val) ?? g.fingers
            case "speed":      g.speed     = val
            case "action":     g.action    = mapActionSynonym(stringVal(val) ?? g.action)
            case "app_filter":    g.appFilter    = nullableStringVal(val)
            case "window_state":    g.windowState    = nullableStringVal(val)
            case "modifier_filter": g.modifierFilter = nullableStringVal(val)
            case "app_path":        g.appPath        = nullableStringVal(val)
            case "menu_path":
                let menuIndent = ind
                i += 1
                g.menuPath = parseMenuPathList(lines, from: &i, parentIndent: menuIndent)
                continue
            case "shortcut_key_code": g.shortcutKeyCode = intVal(val)
            case "shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.shortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "advanced_keyboard":
                let listIndent = ind
                i += 1
                g.advancedKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "reciprocal": g.reciprocal = boolVal(val) ?? g.reciprocal
            case "continuous": g.continuous = boolVal(val) ?? g.continuous
            case "continuous_update_negative_action": g.continuousNegativeAction = stringVal(val).map(mapActionSynonym)
            case "continuous_update_positive_action": g.continuousPositiveAction = stringVal(val).map(mapActionSynonym)
            case "continuous_end_action":             g.continuousEndAction      = stringVal(val).map(mapActionSynonym)
            case "continuous_update_negative_shortcut_key_code": g.continuousNegativeShortcutKeyCode = intVal(val)
            case "continuous_update_positive_shortcut_key_code": g.continuousPositiveShortcutKeyCode = intVal(val)
            case "continuous_end_shortcut_key_code":             g.continuousEndShortcutKeyCode      = intVal(val)
            case "continuous_update_negative_shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.continuousNegativeShortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "continuous_update_positive_shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.continuousPositiveShortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "continuous_end_shortcut_modifiers":
                let modIndent = ind
                i += 1
                g.continuousEndShortcutModifiers = parseStringList(lines, from: &i, parentIndent: modIndent)
                continue
            case "continuous_begin_keyboard":
                let listIndent = ind
                i += 1
                g.continuousBeginKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "continuous_update_negative_keyboard":
                let listIndent = ind
                i += 1
                g.continuousNegativeKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "continuous_update_positive_keyboard":
                let listIndent = ind
                i += 1
                g.continuousPositiveKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "continuous_end_keyboard":
                let listIndent = ind
                i += 1
                g.continuousEndKeyboard = parseStringList(lines, from: &i, parentIndent: listIndent)
                continue
            case "draft":      g.draft      = boolVal(val) ?? g.draft
            default: break
            }
            i += 1
        }
        return g
    }

    // ── Low-level tokenizer ──

    private static func tokenize(_ raw: String) -> (Int, String?, String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return (0, nil, nil) }
        let indent = leadingSpaces(raw)
        guard let colon = trimmed.firstIndex(of: ":") else { return (indent, nil, nil) }
        let key  = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        let rest = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (indent, key, rest.isEmpty ? nil : rest)
    }

    private static func leadingSpaces(_ s: String) -> Int { s.prefix(while: { $0 == " " }).count }
    private static func indentOf(_ lines: [String], at i: Int) -> Int { i < lines.count ? leadingSpaces(lines[i]) : 0 }

    @discardableResult
    private static func scanToKey(_ key: String, in lines: [String], from i: inout Int) -> Bool {
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("\(key):") || t == key { return true }
            i += 1
        }
        return false
    }

    // ── Value converters ──

    private static func floatVal(_ s: String?) -> Float?    { s.flatMap { Float($0) } }
    private static func doubleVal(_ s: String?) -> Double?  { s.flatMap { Double($0) } }
    private static func intVal(_ s: String?) -> Int?        { s.flatMap { Int($0) } }

    private static func boolVal(_ s: String?) -> Bool? {
        switch s?.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    private static func stringVal(_ s: String?) -> String? {
        guard let s else { return nil }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return unescapeQuotedString(String(s.dropFirst().dropLast()))
        }
        return s
    }

    private static func unescapeQuotedString(_ s: String) -> String {
        var result = ""
        var escaping = false
        for ch in s {
            if escaping {
                result.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                result.append(ch)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    private static func nullableStringVal(_ s: String?) -> String? {
        guard let s, s.lowercased() != "null", s != "~" else { return nil }
        return stringVal(s)
    }

    private static func mapActionSynonym(_ s: String) -> String {
        switch s.lowercased() {
        case "launch app":           return "Open App…"
        case "open spotlight":       return "Spotlight"
        case "screenshot selection":       return "Screenshot (Area)"
        case "take screenshot":            return "Screenshot (Full)"
        case "screenshot clipboard":       return "Screenshot (Area → Clipboard)"
        case "screenshot full clipboard":  return "Screenshot (Full → Clipboard)"
        case "screenshot toolbar":         return "Screenshot Toolbar"
        default: return s
        }
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

// ─────────────────────────────────────────────
// MARK: - GlideConfigStore
// ─────────────────────────────────────────────
//
// Manages the live config file at:
//   ~/Library/Application Support/Glide/config.yaml
//
// • save()  — serializes current Settings to disk
// • load()  — reads file and applies it to Settings via Settings.apply(_:)
//
final class GlideConfigStore {
    static let shared = GlideConfigStore()
    private init() {}

    /// Coalesces rapid preference edits (e.g. slider drags) into a single disk write.
    private var pendingSave: DispatchWorkItem?
    private var isDirty = false
    private let saveDebounceInterval: TimeInterval = 0.4

    // MARK: Path

    var configURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Glide", isDirectory: true)
        return dir.appendingPathComponent("config.yaml")
    }

    var configPath: String { configURL.path }

    // MARK: Save

    /// Queues a debounced write. In-memory `Settings` are already updated; the engine sees changes immediately.
    func scheduleSave() {
        isDirty = true
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSave = nil
            _ = self.save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: work)
    }

    /// Writes immediately if a debounced save is still pending (prefs close, quit, sleep).
    func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard isDirty else { return }
        _ = save()
    }

    @discardableResult
    func save() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        isDirty = false

        let url = configURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let yaml = GlideConfigSerializer.serialize(GlideConfig.fromSettings())
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            AppLogger.debug("[Config] Saved → \(url.lastPathComponent)")
            return true
        } catch {
            print("[Config] Save failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Load

    @discardableResult
    func load() -> Bool {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            AppLogger.debug("[Config] No config file — using defaults")
            return false
        }
        guard let raw = try? String(contentsOf: configURL, encoding: .utf8),
              let cfg = GlideConfigParser.parse(yaml: raw) else {
            print("[Config] Failed to parse config")
            return false
        }
        Settings.shared.apply(cfg)
        AppLogger.debug("[Config] Loaded from \(configURL.lastPathComponent)")
        return true
    }

    // MARK: Export / Import

    @discardableResult
    func exportTo(_ destination: URL) -> Bool {
        guard save() else { return false }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: configURL, to: destination)
            return true
        } catch {
            print("[Config] Export failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func importFrom(_ source: URL) -> Bool {
        guard let raw = try? String(contentsOf: source, encoding: .utf8),
              let cfg = GlideConfigParser.parse(yaml: raw) else { return false }
        Settings.shared.apply(cfg)
        save()
        return true
    }
}
