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
    private(set) var isRunning = false
    
    var lastStepTime: TimeInterval = 0
    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)
    var peakResetWorkItem: DispatchWorkItem?

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

        MultitouchBridge.shared.stop()
        inputManager.teardownTaps()
        inputManager.removeMonitors()

        TouchTracker.resetGlobalMTState()
        phase = .idle
        reciprocalToken = nil
        lastStepTime = 0
        isRunning = false
        AppSwitcherState.shared.stopMRUTracking()
        updateObservableState()
        AppLogger.debug("[Engine] Stopped")
    }

    // MARK: - Touch update

    func onTouches(_ frame: TouchFrameData) {
        inputManager.setSuppressionActive(frame.count >= 3)
        currentFingerCount = Int(frame.count)

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

    // MARK: - Actions

    func processClick(fingerCount n: Int) {
        if case .switchingApps = phase { return }
        guard TouchTracker.areClickTouchesSimultaneous() else { return }

        let modifiers = captureModifiers()
        guard let rule = GestureRuleResolver.bestRule(fingers: n, direction: .click, modifiers: modifiers) else { return }

        AppLogger.debug("[Engine] Click — \(n) fingers → \(rule.action.rawValue)")
        clearReciprocalToken()
        phase = .fired

        if rule.action == .quitApp {
            ActionExecutor.shared.quitAppAtCursor(NSEvent.mouseLocation)
        } else {
            ActionExecutor.shared.execute(rule.action, appPath: rule.appPath,
                                          menuItemPath: rule.menuItemPath, menuTargetBundleID: rule.appFilter,
                                          customShortcut: rule.customShortcut,
                                          advancedKeyboard: rule.advancedKeyboard)
        }
        updateObservableState()
    }

    func handleExternalInteraction() {
        guard TouchTracker.glideActiveTouches < 3 else { return }
        if case .fired = phase { return }
        if case .switchingApps = phase { return }
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
                if WindowTargeting.shared.windows(for: apps[idx].processIdentifier).isEmpty {
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
                self.restoreMinimizedWindows()
            }
        }
    }

    private func restoreMinimizedWindows() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        for window in windows {
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let isMinimized = minimizedRef as? Bool, isMinimized {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
        }
    }

    // MARK: - Reciprocal & Continuous

    func executeGestureRuleAction(_ rule: GestureRule) {
        Haptic.forAction(rule.action)
        ActionExecutor.shared.execute(rule.action, appPath: rule.appPath,
                                      menuItemPath: rule.menuItemPath, menuTargetBundleID: rule.appFilter,
                                      customShortcut: rule.customShortcut,
                                      advancedKeyboard: rule.advancedKeyboard)
    }

    func executeSwipeRule(_ rule: GestureRule, fingers: Int, direction: GestureDirection) {
        executeGestureRuleAction(rule)
        if rule.reciprocalEnabled {
            reciprocalToken = makeReciprocalToken(rule: rule, direction: direction)
        } else {
            clearReciprocalToken()
        }
        updateObservableState()
    }

    func consumeReciprocalToken(fingers: Int, direction: GestureDirection, now: TimeInterval) -> Bool {
        guard let token = reciprocalToken, now <= token.expiresAt, token.fingers == fingers, token.direction == direction else {
            clearReciprocalToken(); return false
        }
        clearReciprocalToken()
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
