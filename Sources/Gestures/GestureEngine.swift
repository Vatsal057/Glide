import Cocoa
import CoreGraphics
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: - GestureEngine
// ─────────────────────────────────────────────

final class GestureEngine {

    // MARK: - Components
    private(set) var inputManager: GestureInputManager!
    private(set) var processor: GestureProcessor!
    
    // MARK: - State
    private(set) var phase: GesturePhase = .idle
    private var reciprocalToken: ReciprocalToken?
    /// Direction + finger count of the most recently fired swipe rule.
    /// Used to detect back-to-back same-direction gestures (toggles) so we don't
    /// leave a stale reciprocal token pointing the other way.
    private var lastFiredSwipe: (fingers: Int, direction: GestureDirection)?
    private(set) var isRunning = false
    
    var lastStepTime: TimeInterval = 0
    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)

    /// macOS accessibility zoom is "double-tap three fingers, then drag". A brief,
    /// motionless 3-finger tap followed by an immediate 3-finger re-touch is that
    /// zoom drag — the whole second touch session must not trigger any gesture.
    private var touchSessionStart: (time: TimeInterval, cx: Float, cy: Float)?
    private var touchSessionMovement: Float = 0
    private var lastThreeFingerTapEnd: TimeInterval = 0
    private var isSystemZoomSession = false
    /// Longest contact still considered a "tap" (system double-tap taps are ~0.1s).
    private let tapMaxDuration: TimeInterval = 0.25
    /// Max centroid travel (normalized) for a contact to count as a tap.
    private let tapMaxMovement: Float = 0.025
    /// Max gap between tap release and the zoom drag's re-touch.
    private let doubleTapWindow: TimeInterval = 0.4

    /// A normal click deferred until we know whether it's actually a force click.
    /// Resolved by either a mouse-up (→ normal click) or a deep press (→ force click).
    private var pendingClick: (rule: GestureRule, fingers: Int)?
    /// Safety net that flushes a pending click if a mouse-up event is ever missed.
    private var pendingClickTimeout: DispatchWorkItem?
    /// Upper bound before a deferred click is force-flushed as a normal click.
    private let pendingClickSafetyTimeout: TimeInterval = 0.7

    /// Pending Tap & Hold — fires when fingers rest motionless past tapHoldDuration.
    private var holdWorkItem: DispatchWorkItem?
    private var holdArmedFingerCount = 0

    // MARK: - Observable state
    private(set) var currentPhaseName: String = "Idle"
    private(set) var currentFingerCount: Int = 0
    private(set) var isReciprocalActive: Bool = false
    private(set) var currentCentroidX: Float = 0.5
    private(set) var currentCentroidY: Float = 0.5

    var onStateChange: (() -> Void)?

    private init() {}
    
    static let shared: GestureEngine = {
        let instance = GestureEngine()
        instance.inputManager = GestureInputManager(engine: instance)
        instance.processor = GestureProcessor(engine: instance)
        return instance
    }()

    // MARK: - Lifecycle

    func start() {
        guard AXIsProcessTrusted() else { print("[Engine] Not trusted"); return }
        guard !isRunning else { return }

        TouchTracker.resetGlobalMTState()
        phase = .idle
        reciprocalToken = nil
        lastFiredSwipe = nil
        pendingClickTimeout?.cancel(); pendingClickTimeout = nil; pendingClick = nil
        cancelHoldTimer()
        touchSessionStart = nil; touchSessionMovement = 0
        lastThreeFingerTapEnd = 0; isSystemZoomSession = false

        inputManager.setupTaps()
        MultitouchBridge.shared.start(callback: glideMTCallback)
        inputManager.installMonitors()
        AppSwitcherState.shared.startMRUTracking()
        
        isRunning = true
        updateObservableState()
        AppLogger.debug("[Engine] Started")
    }

    func stop() {
        guard isRunning else { return }

        finishIfNeeded()
        MultitouchBridge.shared.stop()
        inputManager.teardownTaps()
        inputManager.removeMonitors()

        TouchTracker.resetGlobalMTState()
        reciprocalToken = nil
        lastStepTime = 0
        pendingClickTimeout?.cancel(); pendingClickTimeout = nil; pendingClick = nil
        cancelHoldTimer()
        isRunning = false
        AppSwitcherState.shared.stopMRUTracking()
        updateObservableState()
        AppLogger.debug("[Engine] Stopped")
    }

    // MARK: - Touch update

    func onTouches(_ frame: TouchFrameData) {
        let now = ProcessInfo.processInfo.systemUptime

        if frame.count >= 3 {
            if touchSessionStart == nil {
                touchSessionStart = (time: now, cx: frame.cx, cy: frame.cy)
                touchSessionMovement = 0
                // Re-touch right after a 3-finger tap → system zoom drag.
                isSystemZoomSession = now - lastThreeFingerTapEnd < doubleTapWindow
                if isSystemZoomSession { phase = .ignored }
            } else if let start = touchSessionStart {
                let dx = frame.cx - start.cx, dy = frame.cy - start.cy
                touchSessionMovement = max(touchSessionMovement, (dx * dx + dy * dy).squareRoot())
            }
        } else if let start = touchSessionStart {
            // Session ended — was it a tap (short + motionless)?
            let wasTap = now - start.time < tapMaxDuration && touchSessionMovement < tapMaxMovement
            lastThreeFingerTapEnd = wasTap ? now : 0
            touchSessionStart = nil
            isSystemZoomSession = false
        }

        // Leave events untouched while a contact could still be a zoom double-tap
        // (short + motionless) and during the zoom drag itself — suppressing the
        // taps starves the system recognizer and native zoom never triggers.
        let couldBeTap: Bool = {
            guard let start = touchSessionStart else { return false }
            return now - start.time < tapMaxDuration && touchSessionMovement < tapMaxMovement
        }()
        // Tap stays active whenever 3+ fingers are down EXCEPT during the native
        // zoom drag, where every event must reach the system. In the initial
        // tap-detection window we keep the tap on but pass gesture-class events
        // (tapWindowActive) so the zoom double-tap is still recognized — while
        // scroll stays suppressed, so a swipe can't scrub video at gesture onset.
        inputManager.tapWindowActive = couldBeTap
        inputManager.setSuppressionActive(frame.count >= 3 && !isSystemZoomSession)
        currentFingerCount = Int(frame.count)

        // Tap & Hold: (re)arm whenever the resting finger count changes, cancel on lift.
        if frame.count >= 3 {
            if Int(frame.count) != holdArmedFingerCount { armHoldTimer(fingerCount: Int(frame.count)) }
        } else {
            cancelHoldTimer()
        }

        if frame.count < 3 {
            TouchTracker.glideClickFingerCount = 0
            finishIfNeeded()
            updateObservableState()
            return
        }

        currentCentroidX = frame.cx
        currentCentroidY = frame.cy

        if TouchTracker.glideClickFingerCount >= 3 { return }

        if let nextPhase = processor.handleTouches(frame, phase: phase, tuning: Settings.shared.tuning) {
            phase = nextPhase
            updateObservableState()
        }
    }

    // MARK: - Tap & Hold

    private func armHoldTimer(fingerCount n: Int) {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        holdArmedFingerCount = n
        guard GestureRuleResolver.hasHoldRule(fingers: n) else { return }
        let work = DispatchWorkItem { [weak self] in self?.fireHoldIfStillValid(fingerCount: n) }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Settings.shared.tuning.tapHoldDuration, execute: work)
    }

    private func cancelHoldTimer() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        holdArmedFingerCount = 0
    }

    private func fireHoldIfStillValid(fingerCount n: Int) {
        holdWorkItem = nil
        guard isRunning,
              TouchTracker.glideActiveTouches == Int32(n),
              TouchTracker.glideClickFingerCount == 0,
              NSEvent.pressedMouseButtons & 1 == 0,   // physical press → click/force-click path
              !isSystemZoomSession,
              touchSessionMovement < tapMaxMovement else { return }
        switch phase {
        case .fired, .switchingApps, .continuousSwipe: return
        default: break
        }
        guard let rule = GestureRuleResolver.bestRule(fingers: n, direction: .tapHold,
                                                      modifiers: captureModifiers()) else { return }
        Haptic.forRule(rule)   // the instant the hold is recognized
        fireClickRule(rule, label: "Hold", fingerCount: n)
    }

    // MARK: - Actions

    func processClick(fingerCount n: Int) {
        if case .switchingApps = phase { return }
        guard TouchTracker.areClickTouchesSimultaneous() else { return }

        let modifiers = captureModifiers()
        guard let rule = GestureRuleResolver.bestRule(fingers: n, direction: .click, modifiers: modifiers) else { return }

        // A Force Touch trackpad emits this normal click (stage 1) *before* the deep
        // press (stage 2). If a force-click rule is also configured for this finger
        // count, we can't yet tell whether this is a normal or force click. Defer it
        // and resolve on whichever happens first:
        //   • mouse-up  → it was a normal click  (flushPendingClick)
        //   • deep press → it was a force click  (processForceClick cancels this)
        // With no force rule, fire instantly (no added latency).
        let hasForceRule = GestureRuleResolver.bestRule(fingers: n, direction: .forceClick, modifiers: modifiers) != nil
        // Haptic at the moment the click is recognized (mouse-down), even when the
        // action itself is deferred until force-click resolution — feedback should
        // track the gesture, not the outcome.
        Haptic.forRule(rule)
        if hasForceRule {
            pendingClickTimeout?.cancel()
            pendingClick = (rule: rule, fingers: n)
            armPendingClickSafetyTimeout()
        } else {
            fireClickRule(rule, label: "Click", fingerCount: n)
        }
    }

    /// Safety net for a missed mouse-up. While the left button is still physically
    /// held, resolving now would fire a click mid-hold (the user may still be heading
    /// for a force click) — so keep re-arming until the button is actually released.
    private func armPendingClickSafetyTimeout() {
        pendingClickTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingClick != nil else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.armPendingClickSafetyTimeout()
            } else {
                self.flushPendingClick()
            }
        }
        pendingClickTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + pendingClickSafetyTimeout, execute: timeout)
    }

    /// Called when a left mouse-up is observed. If a click is pending (no deep press
    /// arrived before release), it was a normal click — fire it now.
    func flushPendingClick() {
        pendingClickTimeout?.cancel()
        pendingClickTimeout = nil
        guard let pc = pendingClick else { return }
        pendingClick = nil
        fireClickRule(pc.rule, label: "Click", fingerCount: pc.fingers)
    }

    func processForceClick(fingerCount n: Int) {
        if case .switchingApps = phase { return }
        guard TouchTracker.areClickTouchesSimultaneous() else { return }

        // The deep press supersedes any pending normal click — discard it.
        pendingClickTimeout?.cancel()
        pendingClickTimeout = nil
        pendingClick = nil

        let modifiers = captureModifiers()
        guard let rule = GestureRuleResolver.bestRule(fingers: n, direction: .forceClick, modifiers: modifiers) else { return }
        Haptic.forRule(rule)   // at the deep press itself
        fireClickRule(rule, label: "Force Click", fingerCount: n)
    }

    private func fireClickRule(_ rule: GestureRule, label: String, fingerCount n: Int) {
        AppLogger.debug("[Engine] \(label) — \(n) fingers → \(rule.action.rawValue)")
        clearReciprocalToken()
        phase = .fired

        if rule.action == .quitApp {
            WindowTargeting.shared.quitAppAtCursor(NSEvent.mouseLocation)
        } else {
            ActionExecutor.shared.execute(rule.action, appPath: rule.appPath,
                                          menuItemPath: rule.menuItemPath, menuTargetBundleID: rule.appFilter,
                                          customShortcut: rule.customShortcut,
                                          advancedKeyboard: rule.advancedKeyboard,
                                          shortcutName: rule.shortcutName, script: rule.script)
        }
        updateObservableState()
    }

    func handleExternalInteraction() {
        guard TouchTracker.glideActiveTouches < 3 else { return }
        if case .fired = phase { return }
        if case .switchingApps = phase { return }
        // Don't clear the reciprocal token while idle — mouse movement between
        // two gestures is normal and would otherwise kill a pending reciprocal.
        // The token already has a TTL (1.5s) so it expires on its own.
        if case .idle = phase { return }
        clearReciprocalToken()
    }

    private func finishIfNeeded() {
        if case .switchingApps(let data) = phase { commitAppSwitcher(data: data) }
        if case .continuousSwipe(let data) = phase { executeContinuousEndAction(for: data) }
        phase = .idle
        lastStepTime = 0
    }

    // MARK: - App Switcher logic

    func beginAppSwitcher(for action: GestureAction, refX: Float, fingerCount: Int) -> SwitcherData? {
        let apps = AppSwitcherState.shared.getOrderedApps()
        guard apps.count > 1 else { return nil }

        clearReciprocalToken()
        sendKeyEvent(0x37, down: true, flags: .maskCommand) // kCmd
        Haptic.switcherOpen()

        var currentIndex = 0
        if action == .appSwitcherNext {
            sendCmdTab()
            currentIndex = 1
        } else {
            sendCmdShiftTab()
            currentIndex = apps.count - 1
        }

        var finderIndex: Int? = nil
        if Settings.shared.appSwitcher.skipWindowlessFinder {
            if let idx = apps.firstIndex(where: { $0.bundleIdentifier == "com.apple.finder" }) {
                if !WindowTargeting.shared.finderHasAnyWindow() {
                    finderIndex = idx
                }
            }
        }

        if let fi = finderIndex, currentIndex == fi {
            if action == .appSwitcherNext {
                sendCmdTab()
                currentIndex += 1
            } else {
                sendCmdShiftTab()
                currentIndex -= 1
            }
        }

        let effectiveMin = (finderIndex == 0) ? 1 : 0
        let effectiveMax = (finderIndex == apps.count - 1) ? apps.count - 2 : apps.count - 1

        lastStepTime = ProcessInfo.processInfo.systemUptime
        return SwitcherData(refX: refX, index: currentIndex, fingerCount: fingerCount, apps: apps,
                           finderIndex: finderIndex, effectiveMin: effectiveMin, effectiveMax: effectiveMax)
    }

    private func commitAppSwitcher(data: SwitcherData) {
        Haptic.switcherCommit()
        sendKeyEvent(0x3A, down: true,  flags: [.maskAlternate]) // kOpt
        sendKeyEvent(0x37, down: false, flags: [.maskCommand, .maskAlternate]) // kCmd
        sendKeyEvent(0x3A, down: false, flags: []) // kOpt
        
        if Settings.shared.appSwitcher.restoreMinimizedOnCommit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let front = NSWorkspace.shared.frontmostApplication else { return }
                WindowTargeting.shared.unminimizeWindows(of: front.processIdentifier)
            }
        }
    }

    // MARK: - Reciprocal & Continuous

    func executeGestureRuleAction(_ rule: GestureRule) {
        Haptic.forRule(rule)
        ActionExecutor.shared.execute(rule.action, appPath: rule.appPath,
                                      menuItemPath: rule.menuItemPath, menuTargetBundleID: rule.appFilter,
                                      customShortcut: rule.customShortcut,
                                      advancedKeyboard: rule.advancedKeyboard,
                                      shortcutName: rule.shortcutName, script: rule.script)
    }

    func executeSwipeRule(_ rule: GestureRule, fingers: Int, direction: GestureDirection) {
        executeGestureRuleAction(rule)

        // Track what just fired so we can detect back-to-back same-direction toggles.
        let previousFired = lastFiredSwipe
        lastFiredSwipe = (fingers: fingers, direction: direction)

        if rule.reciprocalEnabled {
            // If the user just fired the same direction twice in a row (e.g. swipe-up
            // to open Mission Control, then swipe-up again to close it), that second
            // gesture consumed the toggle — don't leave a token pointing the other way
            // or the very next gesture in that direction gets hijacked.
            let isToggle = previousFired?.fingers == fingers && previousFired?.direction == direction
            if isToggle {
                clearReciprocalToken()
                // Toggle pair consumed (open → close). The next same-direction swipe
                // re-opens, so it must arm a fresh token — reset tracking to alternate.
                lastFiredSwipe = nil
            } else {
                reciprocalToken = makeReciprocalToken(rule: rule, direction: direction)
            }
        } else {
            clearReciprocalToken()
        }
        updateObservableState()
    }

    func consumeReciprocalToken(fingers: Int, direction: GestureDirection, now: TimeInterval) -> Bool {
        guard let token = reciprocalToken,
              now <= token.expiresAt,
              token.fingers == fingers,
              token.direction == direction else {
            // Don't clear the token on a miss — it may still be valid for the next gesture.
            // It will expire on its own via the TTL, or get replaced when a new rule fires.
            return false
        }
        clearReciprocalToken()
        lastFiredSwipe = nil   // reciprocal consumed — reset toggle tracking
        Haptic.reciprocal()
        ActionExecutor.shared.execute(token.inverseAction)
        return true
    }

    private func makeReciprocalToken(rule: GestureRule, direction: GestureDirection) -> ReciprocalToken? {
        let rev: GestureDirection
        switch direction {
        case .swipeLeft: rev = .swipeRight; case .swipeRight: rev = .swipeLeft
        case .swipeUp:   rev = .swipeDown;  case .swipeDown:  rev = .swipeUp
        default: return nil
        }
        let inverse = rule.reciprocalAction ?? rule.action.inverseAction ?? .doNothing
        return ReciprocalToken(inverseAction: inverse,
                               fingers: rule.fingers, direction: rev, sourceRuleID: rule.id,
                               expiresAt: ProcessInfo.processInfo.systemUptime + 1.5)
    }

    func clearReciprocalToken() { reciprocalToken = nil; isReciprocalActive = false }

    func executeContinuousAction(_ action: GestureAction, shortcut: KeyboardShortcut? = nil, keyboard: [KeyboardInputStep] = []) {
        Haptic.forAction(action)
        ActionExecutor.shared.execute(action, customShortcut: shortcut, advancedKeyboard: keyboard)
    }

    func executeContinuousEndAction(for data: SwipeTrackData) {
        guard let rule = data.continuousRule else { return }
        executeContinuousAction(rule.continuousEndAction, shortcut: rule.continuousEndShortcut, keyboard: rule.continuousEndKeyboard)
    }

    func continuousUpdateAction(for dir: GestureDirection, in rule: GestureRule) -> GestureAction {
        (dir == .swipeLeft || dir == .swipeDown) ? rule.continuousNegativeAction : rule.continuousPositiveAction
    }
    func continuousUpdateKeyboard(for dir: GestureDirection, in rule: GestureRule) -> [KeyboardInputStep] {
        (dir == .swipeLeft || dir == .swipeDown) ? rule.continuousNegativeKeyboard : rule.continuousPositiveKeyboard
    }
    func continuousUpdateShortcut(for dir: GestureDirection, in rule: GestureRule) -> KeyboardShortcut? {
        (dir == .swipeLeft || dir == .swipeDown) ? rule.continuousNegativeShortcut : rule.continuousPositiveShortcut
    }

    // MARK: - Helpers

    func captureModifiers() -> CapturedModifiers { CapturedModifiers(NSEvent.modifierFlags) }

    private func updateObservableState() {
        switch phase {
        case .idle: currentPhaseName = "Idle"; case .candidate: currentPhaseName = "Candidate"
        case .lockedSwipe: currentPhaseName = "Locked (Swipe)"; case .ignored: currentPhaseName = "Ignored"
        case .fired: currentPhaseName = "Fired"; case .continuousSwipe: currentPhaseName = "Continuous"
        case .switchingApps: currentPhaseName = "App Switcher"
        }
        isReciprocalActive = (reciprocalToken != nil)
        onStateChange?()
    }

    func sendCmdTab() { sendKeyEvent(0x30, down: true, flags: .maskCommand); sendKeyEvent(0x30, down: false, flags: .maskCommand) }
    func sendCmdShiftTab() {
        sendKeyEvent(0x38, down: true,  flags: [.maskCommand, .maskShift])
        sendKeyEvent(0x30, down: true,  flags: [.maskCommand, .maskShift])
        sendKeyEvent(0x30, down: false, flags: [.maskCommand, .maskShift])
        sendKeyEvent(0x38, down: false, flags: .maskCommand)
    }

    private func sendKeyEvent(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState)
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { return }
        e.flags = flags; e.post(tap: .cghidEventTap)
    }
}
