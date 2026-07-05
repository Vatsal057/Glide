import Cocoa

// ─────────────────────────────────────────────
// MARK: - Haptic engine
// ─────────────────────────────────────────────

enum Haptic {

    /// Rule-aware entry point: per-gesture override wins, else the pattern
    /// assigned to the action's category.
    static func forRule(_ rule: GestureRule) {
        if let pattern = rule.hapticPattern {
            HapticEngine.shared.play(pattern)
        } else {
            forAction(rule.action)
        }
    }

    static func forAction(_ action: GestureAction) {
        switch action {
        case .doNothing:
            return
        case .quitApp, .forceQuitApp, .quitFrontmost, .closeWindow, .emptyTrash:
            HapticEngine.shared.play(event: .destructiveAction)
        case .minimizeWindow, .minimizeAllApps, .restoreMinimizedApps,
             .maximizeWindow, .restoreWindow,
             .enterFullscreen, .exitFullscreen, .toggleFullscreen,
             .snapLeft, .snapRight, .snapTopLeft, .snapTopRight,
             .snapBottomLeft, .snapBottomRight, .centerWindow, .moveNextDisplay:
            HapticEngine.shared.play(event: .windowAction)
        default:
            HapticEngine.shared.play(event: .otherAction)
        }
    }

    static func switcherStep()   { HapticEngine.shared.play(event: .switcherStep) }
    static func switcherOpen()   { HapticEngine.shared.play(event: .switcherOpen) }
    static func switcherCommit() { HapticEngine.shared.play(event: .switcherCommit) }
    static func reciprocal()     { HapticEngine.shared.play(event: .reciprocal) }
}
import Foundation

// ─────────────────────────────────────────────
// MARK: - AppLogger
// ─────────────────────────────────────────────

enum AppLogger {
    static func debug(_ message: @autoclosure () -> String) {
        guard Settings.shared.debugLoggingEnabled else { return }
        print(message())
    }
}
