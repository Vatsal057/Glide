import Cocoa
import CoreGraphics

// MARK: - Native App Switcher Invoker

class NativeAppSwitcher {
    private static let keyboardEventSource  = CGEventSource(stateID: .hidSystemState)
    private static let tabKey: CGKeyCode         = 0x30
    private static let leftCommandKey: CGKeyCode = 0x37
    private static let shiftKey: CGKeyCode       = 0x38
    private static let optionKey: CGKeyCode      = 0x3A

    static func selectInAppSwitcher() {
        postKeyEvent(key: optionKey,      down: true,  flags: [.maskAlternate])
        postKeyEvent(key: leftCommandKey, down: false, flags: [.maskCommand, .maskAlternate])
        postKeyEvent(key: optionKey,      down: false, flags: [])
    }

    static func cmdTab() {
        postKeyEvent(key: tabKey, down: true,  flags: .maskCommand)
        postKeyEvent(key: tabKey, down: false, flags: .maskCommand)
    }

    static func cmdShiftTab() {
        postKeyEvent(key: shiftKey, down: true,  flags: [.maskCommand])
        postKeyEvent(key: tabKey,   down: true,  flags: [.maskCommand, .maskShift])
        postKeyEvent(key: tabKey,   down: false, flags: [.maskCommand, .maskShift])
        postKeyEvent(key: shiftKey, down: false, flags: [.maskCommand])
    }

    private static func postKeyEvent(key: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: keyboardEventSource,
                                  virtualKey: key, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

// MARK: - Gesture State

enum GestureState {
    case idle
    // startTime is captured when tracking begins so we can measure swipe velocity
    case tracking(initialX: Float, initialY: Float, numFingers: Int32, startTime: TimeInterval)
    case swipingHorizontal(referenceX: Float)
    case swipingVertical
}

// MARK: - Gesture Engine

class GestureEngine {
    static let shared = GestureEngine()

    var state: GestureState = .idle

    var isSwiping: Bool {
        switch state {
        case .swipingHorizontal, .swipingVertical: return true
        default: return false
        }
    }

    // Movement thresholds (normalised trackpad coordinates, 0–1)
    private let initialSwipeThreshold:    Float = 0.025
    private let swipeThreshold:           Float = 0.005
    private let verticalTriggerThreshold: Float = 0.035

    // Velocity thresholds (normalised units per second)
    // below slowCutoff  → .slow
    // above fastCutoff  → .fast
    // in between        → .normal
    private let slowCutoff: Float = 0.20
    private let fastCutoff: Float = 0.45

    private let debounceInterval: TimeInterval = 0.20

    private var lastEventTime: TimeInterval = 0
    private var currentIndex:  Int    = 0
    private var appCount:      Int    = 0
    private var missionControlIsOpen: Bool   = false
    private var lastMinimizedPID:     pid_t? = nil

    // MARK: Rule lookup

    /// Returns the best-matching rule for a swipe of measured speed.
    ///
    /// Fallback chain:
    ///   1. Exact speed match          — honours the user's specific slow/fast binding
    ///   2. .normal speed match        — a single "normal" rule still fires for any speed
    ///   3. Any rule for this combo    — last resort so nothing silently disappears
    ///
    /// This means existing single-speed rules keep working exactly as before,
    /// and adding a second rule at a different speed creates the differentiated behaviour.
    private func bestRule(fingers: Int, direction: GestureDirection, speed: GestureSpeed) -> GestureRule? {
        let candidates = Settings.shared.rules.filter {
            $0.fingers == fingers && $0.direction == direction
        }
        return candidates.first { $0.speed == speed }
            ?? candidates.first { $0.speed == .normal }
            ?? candidates.first
    }

    /// Convenience overload for callers that don't have a speed context
    /// (idle-state existence checks, click handling).
    private func anyRule(fingers: Int, direction: GestureDirection) -> GestureRule? {
        Settings.shared.rules.first { $0.fingers == fingers && $0.direction == direction }
    }

    // MARK: Velocity classification

    private func classifySpeed(displacement: Float, elapsed: TimeInterval) -> GestureSpeed {
        guard elapsed > 0 else { return .normal }
        let velocity = displacement / Float(elapsed)
        if velocity < slowCutoff { return .slow }
        if velocity > fastCutoff { return .fast }
        return .normal
    }

    // MARK: Action execution

    func executeAction(_ action: GestureAction, isHorizontal: Bool = false) {
        switch action {
        case .quitApp, .doNothing, .appSwitcher:
            break   // handled by click path or the continuous app-switcher loop
        case .missionControl:
            WindowInteractions.performMissionControl()
            missionControlIsOpen = true
        case .minimizeWindow:
            lastMinimizedPID = WindowInteractions.minimizeWindowUnderCursor()
        case .maximizeWindow:
            WindowInteractions.performZoomOnWindowUnderCursor(maximize: true)
        case .restoreWindow:
            WindowInteractions.performZoomOnWindowUnderCursor(maximize: false)
        case .enterFullscreen:
            WindowInteractions.setFullscreenWindowUnderCursor(enabled: true)
        case .exitFullscreen:
            WindowInteractions.setFullscreenWindowUnderCursor(enabled: false)
        }
    }

    // MARK: Touch update (called on main thread)

    func onTouchesUpdate(numFingers: Int32, touchVectors: [(Float, Float)]) {
        if numFingers >= 3, touchVectors.count == Int(numFingers) {
            var sumX: Float = 0, sumY: Float = 0
            for v in touchVectors { sumX += v.0; sumY += v.1 }
            let avgX = sumX / Float(numFingers)
            let avgY = sumY / Float(numFingers)

            switch state {

            // ── Idle: decide whether to start tracking ──────────────────────
            case .idle:
                let hasH = anyRule(fingers: Int(numFingers), direction: .swipeHorizontal) != nil
                let hasU = anyRule(fingers: Int(numFingers), direction: .swipeUp)         != nil
                let hasD = anyRule(fingers: Int(numFingers), direction: .swipeDown)       != nil

                if hasH || hasU || hasD {
                    state = .tracking(
                        initialX: avgX, initialY: avgY,
                        numFingers: numFingers,
                        startTime: Date().timeIntervalSince1970
                    )
                }

            // ── Tracking: wait for displacement to cross a threshold ─────────
            case .tracking(let initialX, let initialY, let recognizedFingers, let startTime):
                guard numFingers == recognizedFingers else { state = .idle; return }

                let deltaX  = avgX - initialX
                let deltaY  = avgY - initialY
                let elapsed = Date().timeIntervalSince1970 - startTime

                // Horizontal — only enter this branch if a horizontal rule exists for
                // this finger count.  Without the guard, a slow wobble in X on a
                // 4-finger swipe-up would enter the horizontal block, find no rule,
                // do nothing, and then never reach the vertical check (else-if).
                let horizontalRule = anyRule(fingers: Int(recognizedFingers), direction: .swipeHorizontal)
                if abs(deltaX) > initialSwipeThreshold, horizontalRule != nil {
                    let speed = classifySpeed(displacement: abs(deltaX), elapsed: elapsed)
                    let rule  = bestRule(fingers: Int(recognizedFingers),
                                        direction: .swipeHorizontal, speed: speed)!

                    if rule.action == .appSwitcher {
                        appCount     = NSWorkspace.shared.runningApplications
                            .filter { $0.activationPolicy == .regular }.count
                        currentIndex = 0
                        let now      = Date().timeIntervalSince1970
                        if deltaX > 0, currentIndex < appCount - 1 {
                            currentIndex += 1; NativeAppSwitcher.cmdTab(); lastEventTime = now
                        } else if deltaX < 0, currentIndex > 0 {
                            currentIndex -= 1; NativeAppSwitcher.cmdShiftTab(); lastEventTime = now
                        }
                        state = .swipingHorizontal(referenceX: avgX)
                    } else {
                        let now = Date().timeIntervalSince1970
                        state   = .swipingVertical
                        if now - lastEventTime >= 0.3 {
                            executeAction(rule.action, isHorizontal: true)
                            lastEventTime = now
                        }
                    }
                }
                // Vertical
                else if abs(deltaY) > verticalTriggerThreshold {
                    let speed = classifySpeed(displacement: abs(deltaY), elapsed: elapsed)

                    if deltaY > 0 { // swipe UP
                        if let rule = bestRule(fingers: Int(recognizedFingers),
                                               direction: .swipeUp, speed: speed) {
                            if Settings.shared.enableContextAwareness,
                               let pid = lastMinimizedPID,
                               rule.action == .missionControl {
                                WindowInteractions.restoreMinimizedApp(pid: pid)
                                lastMinimizedPID = nil
                            } else {
                                executeAction(rule.action)
                            }
                            state = .swipingVertical
                        }
                    } else { // swipe DOWN
                        if let rule = bestRule(fingers: Int(recognizedFingers),
                                               direction: .swipeDown, speed: speed) {
                            if Settings.shared.enableContextAwareness,
                               missionControlIsOpen,
                               rule.action == .minimizeWindow {
                                WindowInteractions.performMissionControl()
                                missionControlIsOpen = false
                            } else {
                                executeAction(rule.action)
                            }
                            state = .swipingVertical
                        }
                    }
                }

            // ── Swiping horizontal: keep scrolling through app switcher ──────
            case .swipingHorizontal(let referenceX):
                guard numFingers == 3 else {
                    NativeAppSwitcher.selectInAppSwitcher()
                    state = .idle; return
                }
                let now   = Date().timeIntervalSince1970
                let delta = avgX - referenceX
                if abs(delta) > swipeThreshold, now - lastEventTime >= debounceInterval {
                    if delta > 0, currentIndex < appCount - 1 {
                        currentIndex += 1; NativeAppSwitcher.cmdTab(); lastEventTime = now
                    } else if delta < 0, currentIndex > 0 {
                        currentIndex -= 1; NativeAppSwitcher.cmdShiftTab(); lastEventTime = now
                    }
                    state = .swipingHorizontal(referenceX: avgX)
                }

            // ── Swiping vertical: action already fired, wait for lift ────────
            case .swipingVertical:
                break
            }

        } else {
            if case .swipingHorizontal = state { NativeAppSwitcher.selectInAppSwitcher() }
            state         = .idle
            currentIndex  = 0
            lastEventTime = 0
        }
    }
}
