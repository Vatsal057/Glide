import Cocoa

// ─────────────────────────────────────────────
// MARK: - Haptic engine
// ─────────────────────────────────────────────

enum Haptic {

    static func forAction(_ action: GestureAction) {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch action {
        case .quitApp, .forceQuitApp, .quitFrontmost, .closeWindow, .sleep, .lockScreen, .openApp:
            pattern = .generic
        case .minimizeWindow, .minimizeAllApps, .restoreMinimizedApps,
             .maximizeWindow, .restoreWindow,
             .enterFullscreen, .exitFullscreen, .toggleFullscreen,
             .snapLeft, .snapRight, .snapTopLeft, .snapTopRight,
             .snapBottomLeft, .snapBottomRight, .centerWindow, .moveNextDisplay:
            pattern = .levelChange
        case .doNothing:
            return
        default:
            pattern = .alignment
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    static func switcherStep()   { fire(.alignment) }
    static func switcherOpen()   { fire(.generic) }
    static func switcherCommit() { fire(.generic) }
    static func reciprocal()     { fire(.levelChange) }
    static func click()          { fire(.levelChange) }

    private static func fire(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
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
