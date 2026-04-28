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
        var swipeThreshold: Float = 0.018
        var fastVelocityThreshold: Float = 0.008
        var slowVelocityThreshold: Float = 0.003
        var speedSampleCount: Int = 3
    }

    struct Preferences {
        var windowTargeting: String = "Focused Window First"
        var hapticFeedback: Bool = true
        var debugLogging: Bool = false
        var launchAtLogin: Bool = false
    }

    struct Tuning {
        var appSwitcherStepThreshold: Float = 0.003
        var appSwitcherDebounce: Double = 0.10
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
        var appPath: String?
        var reciprocal: Bool
    }

    var speed: Speed = Speed()
    var preferences: Preferences = Preferences()
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

        cfg.tuning.appSwitcherStepThreshold  = t.appSwitcherStepThreshold
        cfg.tuning.appSwitcherDebounce       = t.appSwitcherDebounce
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
            return GlideConfig.Gesture(
                type:       isClick ? "click" : "swipe",
                direction:  isClick ? nil     : yamlDirection(rule.direction),
                fingers:    rule.fingers,
                speed:      isClick ? nil     : rule.speed.rawValue.lowercased(),
                action:     rule.action.rawValue,
                appFilter:  rule.appFilter,
                appPath:    rule.appPath,
                reciprocal: rule.reciprocalEnabled
            )
        }
        return cfg
    }

    // ── Convert to Settings-domain types (used by Settings.apply(_:)) ──

    func toTuning() -> GestureTuning {
        var t = GestureTuning()
        t.initialThreshold          = speed.swipeThreshold
        t.fastVelocityThreshold     = speed.fastVelocityThreshold
        t.slowVelocityThreshold     = speed.slowVelocityThreshold
        t.speedSampleCount          = speed.speedSampleCount
        t.appSwitcherStepThreshold  = tuning.appSwitcherStepThreshold
        t.appSwitcherDebounce       = tuning.appSwitcherDebounce
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

            return GestureRule(
                fingers:           g.fingers,
                direction:         direction,
                speed:             speed,
                action:            action,
                appPath:           g.appPath,
                appFilter:         g.appFilter,
                reciprocalEnabled: g.reciprocal
            )
        }
    }

    // ── Direction helpers ──

    private static func yamlDirection(_ d: GestureDirection) -> String {
        switch d {
        case .swipeLeft:  return "left"
        case .swipeRight: return "right"
        case .swipeUp:    return "up"
        case .swipeDown:  return "down"
        case .click:      return "none"
        }
    }

    private func swiftDirection(_ s: String?) -> GestureDirection? {
        switch s?.lowercased() {
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
            "  # ── Tuning ─────────────────────────────────────────",
            "  tuning:",
            "    app_switcher_step_threshold: \(fmt(config.tuning.appSwitcherStepThreshold))",
            "    app_switcher_debounce: \(String(format: "%.2f", config.tuning.appSwitcherDebounce))",
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
        lines.append("      action: \"\(escape(g.action))\"")
        lines.append("      app_filter: \(g.appFilter.map { "\"\($0)\"" } ?? "null")")
        if g.type == "swipe" || g.appPath != nil {
            lines.append("      app_path: \(g.appPath.map { "\"\(escape($0))\"" } ?? "null")")
            lines.append("      reciprocal: \(g.reciprocal ? "true" : "false")")
        }
        return lines
    }

    private static func fmt(_ v: Float) -> String { String(format: "%.3f", v) }

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
            let (indent, key, _) = tokenize(lines[i])
            if indent == 0 && key != nil && key != "touchpad" { break }
            switch key {
            case "speed":       i += 1; parseSpeed(lines, from: &i, into: &cfg.speed)
            case "preferences": i += 1; parsePreferences(lines, from: &i, into: &cfg.preferences)
            case "tuning":      i += 1; parseTuning(lines, from: &i, into: &cfg.tuning)
            case "gestures":    i += 1; parseGestures(lines, from: &i, into: &cfg.gestures); return cfg
            default:            i += 1
            }
        }
        return cfg
    }

    private static func parseSpeed(_ lines: [String], from i: inout Int, into speed: inout GlideConfig.Speed) {
        let base = indentOf(lines, at: i)
        while i < lines.count {
            let (ind, key, val) = tokenize(lines[i])
            if ind < base { return }
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

    private static func parsePreferences(_ lines: [String], from i: inout Int, into prefs: inout GlideConfig.Preferences) {
        let base = indentOf(lines, at: i)
        while i < lines.count {
            let (ind, key, val) = tokenize(lines[i])
            if ind < base { return }
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

    private static func parseTuning(_ lines: [String], from i: inout Int, into tuning: inout GlideConfig.Tuning) {
        let base = indentOf(lines, at: i)
        while i < lines.count {
            let (ind, key, val) = tokenize(lines[i])
            if ind < base { return }
            switch key {
            case "app_switcher_step_threshold":  tuning.appSwitcherStepThreshold  = floatVal(val)  ?? tuning.appSwitcherStepThreshold
            case "app_switcher_debounce":        tuning.appSwitcherDebounce       = doubleVal(val) ?? tuning.appSwitcherDebounce
            case "candidate_frames":             tuning.candidateFrames           = intVal(val)    ?? tuning.candidateFrames
            case "pinch_spread_threshold":       tuning.pinchSpreadThreshold      = floatVal(val)  ?? tuning.pinchSpreadThreshold
            case "pinch_frame_spread_threshold": tuning.pinchFrameSpreadThreshold = floatVal(val)  ?? tuning.pinchFrameSpreadThreshold
            case "swipe_coherence_threshold":    tuning.swipeCoherenceThreshold   = floatVal(val)  ?? tuning.swipeCoherenceThreshold
            case "swipe_angle_tolerance":        tuning.swipeAngleTolerance       = floatVal(val)  ?? tuning.swipeAngleTolerance
            case "edge_margin":
                i += 1
                parseEdgeMargin(lines, from: &i, into: &tuning)
                continue
            default: break
            }
            i += 1
        }
    }

    private static func parseEdgeMargin(_ lines: [String], from i: inout Int, into tuning: inout GlideConfig.Tuning) {
        let base = indentOf(lines, at: i)
        while i < lines.count {
            let (ind, key, val) = tokenize(lines[i])
            if ind < base { return }
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

    private static func parseGestures(_ lines: [String], from i: inout Int, into gestures: inout [GlideConfig.Gesture]) {
        let base = indentOf(lines, at: i)
        while i < lines.count {
            let line = lines[i]
            let (ind, key, _) = tokenize(line)
            if ind < base && !line.trimmingCharacters(in: .whitespaces).hasPrefix("-") && key != nil { return }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                let g = parseGestureBlock(lines, from: &i)
                if !g.type.isEmpty && !g.action.isEmpty { gestures.append(g) }
                continue
            }
            i += 1
        }
    }

    private static func parseGestureBlock(_ lines: [String], from i: inout Int) -> GlideConfig.Gesture {
        var g = GlideConfig.Gesture(type: "", direction: nil, fingers: 3,
                                    speed: nil, action: "", appFilter: nil, appPath: nil, reciprocal: true)
        let firstLine = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
        if let colon = firstLine.firstIndex(of: ":") {
            let k = String(firstLine[..<colon]).trimmingCharacters(in: .whitespaces)
            let v = String(firstLine[firstLine.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if k == "type" { g.type = v }
        }
        let blockIndent = leadingSpaces(lines[i])
        i += 1
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
            let ind = leadingSpaces(line)
            if trimmed.hasPrefix("-") && ind <= blockIndent { return g }
            if ind <= blockIndent { return g }
            let (_, key, val) = tokenize(line)
            switch key {
            case "type":       g.type      = val ?? g.type
            case "direction":  g.direction = val
            case "fingers":    g.fingers   = intVal(val) ?? g.fingers
            case "speed":      g.speed     = val
            case "action":     g.action    = mapActionSynonym(stringVal(val) ?? g.action)
            case "app_filter": g.appFilter = nullableStringVal(val)
            case "app_path":   g.appPath   = nullableStringVal(val)
            case "reciprocal": g.reciprocal = boolVal(val) ?? g.reciprocal
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
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func nullableStringVal(_ s: String?) -> String? {
        guard let s, s.lowercased() != "null", s != "~" else { return nil }
        return stringVal(s)
    }

    private static func mapActionSynonym(_ s: String) -> String {
        switch s.lowercased() {
        case "launch app":           return "Open App…"
        case "open spotlight":       return "Spotlight"
        case "screenshot selection": return "Screenshot (Area)"
        case "take screenshot":      return "Screenshot (Full)"
        default: return s
        }
    }
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

    @discardableResult
    func save() -> Bool {
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
