import Cocoa

final class GestureRuleResolver {
    
    static func bestRule(
        fingers: Int,
        direction: GestureDirection,
        speed: GestureSpeed = .normal,
        modifiers: CapturedModifiers
    ) -> GestureRule? {
        let matching = self.matchingRules(fingers: fingers, direction: direction, modifiers: modifiers)
        return bestRuleMatch(in: matching, speed: speed)
    }

    static func matchingRules(
        fingers: Int,
        direction: GestureDirection,
        modifiers: CapturedModifiers
    ) -> [GestureRule] {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isFullscreen = WindowTargeting.shared.isFrontmostWindowFullscreen()
        let isMaximized  = WindowTargeting.shared.isFrontmostWindowMaximized()

        return Settings.shared.rules.filter { rule in
            rule.isActive
                && !rule.isKeyboardBinding
                && rule.fingers == fingers
                && ruleDirection(rule.direction, matchesActual: direction)
                && matchesWindowState(rule, isFullscreen: isFullscreen, isMaximized: isMaximized)
                && matchesAppFilter(rule, bundleID: bid)
                && modifiers.matches(rule.modifierFilter)
        }
    }

    /// Evaluates window-state and app-filter conditions without requiring a gesture
    /// context. Used by keyboard-triggered rules, which skip gesture matching.
    static func passesContextFilters(_ rule: GestureRule) -> Bool {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isFullscreen = WindowTargeting.shared.isFrontmostWindowFullscreen()
        let isMaximized  = WindowTargeting.shared.isFrontmostWindowMaximized()
        return matchesWindowState(rule, isFullscreen: isFullscreen, isMaximized: isMaximized)
            && matchesAppFilter(rule, bundleID: bid)
    }

    private static func matchesWindowState(_ rule: GestureRule, isFullscreen: Bool, isMaximized: Bool) -> Bool {
        switch rule.windowStateFilter {
        case .any:            return true
        case .fullscreen:     return isFullscreen
        case .notFullscreen:  return !isFullscreen
        case .maximized:      return isMaximized
        case .notMaximized:   return !isMaximized
        }
    }

    private static func matchesAppFilter(_ rule: GestureRule, bundleID: String?) -> Bool {
        guard let filter = rule.appFilter, !filter.isEmpty else { return true }
        return filter == bundleID
    }

    /// Resolves a force-click at a given centroid. A rule bound to the corner the
    /// centroid falls in wins; otherwise the position-blind (`.any`) rule handles
    /// the center and any corner without its own rule. Returns nil when neither
    /// exists — the caller then treats the press as a plain click.
    static func forceClickRule(fingers: Int, cx: Float, cy: Float, margin: Float,
                               modifiers: CapturedModifiers) -> GestureRule? {
        let matching = matchingRules(fingers: fingers, direction: .forceClick, modifiers: modifiers)
        if let corner = TrackpadZone.at(cx: cx, cy: cy, margin: margin),
           let zoned = matching.last(where: { $0.zone == corner }) {
            return zoned
        }
        return matching.last(where: { $0.zone == .any })
    }

    static func hasHoldRule(fingers: Int) -> Bool {
        Settings.shared.rules.contains {
            $0.isActive && $0.fingers == fingers && $0.direction == .tapHold
        }
    }

    static func hasAnySwipeRule(fingers: Int) -> Bool {
        if Settings.shared.appSwitcher.enabled, fingers == Settings.shared.appSwitcher.fingers {
            return true
        }
        let swipeDirs: [GestureDirection] = [.swipeLeftRight, .swipeUpDown, .swipeLeft, .swipeRight, .swipeUp, .swipeDown]
        return Settings.shared.rules.contains {
            $0.isActive && $0.fingers == fingers && swipeDirs.contains($0.direction)
        }
    }

    private static func ruleDirection(_ ruleDirection: GestureDirection, matchesActual actual: GestureDirection) -> Bool {
        switch ruleDirection {
        case .swipeLeftRight:
            return actual == .swipeLeft || actual == .swipeRight
        case .swipeUpDown:
            return actual == .swipeUp || actual == .swipeDown
        default:
            return ruleDirection == actual
        }
    }

    private static func bestRuleMatch(in rules: [GestureRule], speed: GestureSpeed) -> GestureRule? {
        let normalized = normalizedSpeed(speed)
        if let exact = rules.last(where: { normalizedSpeed($0.speed) == normalized }) {
            return exact
        }
        let configuredSpeeds = Set(rules.map { normalizedSpeed($0.speed) })
        if configuredSpeeds.count > 1 { return nil }
        guard speed != .normal else { return nil }
        return rules.last(where: { normalizedSpeed($0.speed) == .normal })
    }

    private static func normalizedSpeed(_ speed: GestureSpeed) -> GestureSpeed {
        speed == .any ? .normal : speed
    }

    static func appSwitcherAction(fingers: Int, direction: GestureDirection,
                                   modifiers: CapturedModifiers) -> GestureAction? {
        let cfg = Settings.shared.appSwitcher
        guard cfg.enabled, fingers == cfg.fingers else { return nil }
        guard modifiers.matches(.noModifiers) else { return nil }
        switch direction {
        case .swipeRight: return .appSwitcherNext
        case .swipeLeft:  return .appSwitcherPrev
        default:          return nil
        }
    }
}
