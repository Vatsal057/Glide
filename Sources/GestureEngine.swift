import Cocoa
import CoreGraphics
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: - Haptic engine
// ─────────────────────────────────────────────

private enum Haptic {

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
    static func click()          { fire(.generic) }

    private static func fire(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

// ─────────────────────────────────────────────
// MARK: - Touch frame data
// ─────────────────────────────────────────────

struct TouchFrameData {
    let count: Int32
    let cx: Float
    let cy: Float
    let spread: Float
    let coherence: Float
}

// ─────────────────────────────────────────────
// MARK: - Gesture classification
// ─────────────────────────────────────────────

private enum GestureKind { case unknown, swipe, pinch }

// ─────────────────────────────────────────────
// MARK: - GestureEngine
// ─────────────────────────────────────────────

final class GestureEngine {

    static let shared = GestureEngine()
    private init() {}

    // MARK: - Session state machine

    private struct CandidateData {
        let startX: Float; let startY: Float
        let fingers: Int; let startTime: TimeInterval
        let initialSpread: Float
        let modifiersAtStart: CapturedModifiers
        var frameCount: Int
        var cumulativeSpreadDelta: Float
        var prevSpread: Float
        var minCoherence: Float
        var prevCx: Float; var prevCy: Float
        var velocitySamples: [Float]
        var gestureKind: GestureKind = .unknown
        var classificationFrameDelay: Int = 0
    }

    private struct SwipeTrackData {
        let startX: Float; let startY: Float
        var lastX: Float; var lastY: Float
        let fingers: Int; let startTime: TimeInterval
        let modifiersAtStart: CapturedModifiers
        var velocitySamples: [Float]
        var recentDeltas: [(dx: Float, dy: Float)]
        let initialSpread: Float
        var prevSpread: Float
        var cumulativeSpreadDelta: Float
    }

    private struct SwitcherData {
        var refX: Float; var index: Int
        let apps: [NSRunningApplication]
        let finderIndex: Int?   // position of windowless Finder, nil if Finder has windows
        let effectiveMin: Int   // left boundary (tightened if Finder is at left edge)
        let effectiveMax: Int   // right boundary (tightened if Finder is at right edge)
    }

    private enum GesturePhase {
        case idle
        case candidate(CandidateData)
        case lockedSwipe(SwipeTrackData)
        case ignored
        case fired
        case switchingApps(SwitcherData)
    }

    // MARK: - Reciprocal token

    private struct ReciprocalToken {
        let inverseAction: GestureAction
        let fingers: Int
        let direction: GestureDirection
    }

    // MARK: - State

    private var phase: GesturePhase = .idle
    private var reciprocalToken: ReciprocalToken?
    private var isRunning = false

    /// Tracks app activation order (most-recently-used first).
    /// Updated via NSWorkspace.didActivateApplicationNotification so the
    /// switcher's app array matches the actual Cmd+Tab MRU ordering.
    private var mruAppOrder: [pid_t] = []
    private var mruObserver: Any?

    /// Single periodic timer — checks both MT bridge liveness and CGEvent tap health.
    private var healthTimer: Timer?

    private var suppressionTap: CFMachPort?
    private var suppressionSource: CFRunLoopSource?
    private(set) var suppressionEnabled = false

    /// Listen-only tap for click detection — created once and kept alive across stop/start cycles.
    /// `.listenOnly` taps are never disabled by macOS timeout; no health check needed.
    private var clickObservationTap: CFMachPort?
    private var clickObservationSource: CFRunLoopSource?
    private var clickTapInstalled = false

    /// Dedup guard — prevents both the NSEvent monitor and the CGEvent tap
    /// from processing the same click.
    private var lastClickProcessedTime: TimeInterval = 0

    private var interactionMonitors: [Any] = []
    
    private var lastClickEventTime: TimeInterval = 0
    
    private var pressureMonitor: Any?
    private var lastForceClickTime: TimeInterval = 0
    private let forceCooldown: TimeInterval = 0.4

    private var lastStepTime: TimeInterval = 0
    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)

    /// Work item that resets the peak finger count after a short delay, keeping
    /// the peak alive long enough for the click handler to read it.
    var peakResetWorkItem: DispatchWorkItem?

    private let kCmd:   CGKeyCode = 0x37
    private let kShift: CGKeyCode = 0x38
    private let kTab:   CGKeyCode = 0x30
    private let kOpt:   CGKeyCode = 0x3A

    // MARK: - Observable state

    private(set) var currentPhaseName: String = "Idle"
    private(set) var currentFingerCount: Int = 0
    private(set) var isReciprocalActive: Bool = false
    private(set) var currentCentroidX: Float = 0.5
    private(set) var currentCentroidY: Float = 0.5

    var onStateChange: (() -> Void)?

    private var tuning: GestureTuning { Settings.shared.tuning }

    // MARK: - Lifecycle

    func start() {
        guard AXIsProcessTrusted() else { print("[Engine] Not trusted"); return }
        guard !isRunning else { return }

        resetGlobalMTState()
        phase = .idle
        reciprocalToken = nil
        lastClickProcessedTime = 0

        setupSuppressionTap()
        setupClickObservationTap()    // persistent — created at most once
        MultitouchBridge.shared.start(callback: glideMTCallback)
        installInteractionMonitors()
        startHealthTimer()
        startMRUTracking()
        isRunning = true
        updateObservableState()
        AppLogger.debug("[Engine] Started")
    }

    func stop() {
        guard isRunning else { return }

        healthTimer?.invalidate()
        healthTimer = nil

        MultitouchBridge.shared.stop()
        teardownSuppressionTap()

        interactionMonitors.forEach { NSEvent.removeMonitor($0) }
        interactionMonitors.removeAll()

        resetGlobalMTState()
        phase = .idle
        reciprocalToken = nil
        lastStepTime = 0
        suppressionEnabled = false
        isRunning = false
        updateObservableState()
        AppLogger.debug("[Engine] Stopped")
    }

    private func resetGlobalMTState() {
        // Clear device-keyed state under lock so stale pre-sleep device
        // pointers don't corrupt sessionPeakActiveTouches on the next wake.
        // Without this, a prior peak of 4 would permanently block 3-finger
        // clicks because count (3) != peak (4) after every sleep/wake cycle.
        countsLock.lock()
        deviceFingerCounts.removeAll(keepingCapacity: true)
        sessionPeakActiveTouches = 0
        countsLock.unlock()

        glideActiveTouches = 0
        glideClickFingerCount = 0
        glidePeakFingerCount = 0
        glideLastMTTimestamp = 0
        glideLastDispatchedCount = 0
        glideFingerFirstSeen.removeAll(keepingCapacity: true)
        glideOldestFingerAge = 0
        glideNewestFingerAge = 0
    }

    // MARK: - Health timer (MT watchdog + tap health, combined)

    private func startHealthTimer() {
        healthTimer?.invalidate()
        glideLastMTTimestamp = ProcessInfo.processInfo.systemUptime
        lastClickEventTime = ProcessInfo.processInfo.systemUptime

        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.checkMTHealth()
            self.checkTapHealth()
        }
        timer.tolerance = 2.0
        healthTimer = timer
    }

    /// Restarts the MT bridge if no callback has fired in the last 8 seconds.
    private func checkMTHealth() {
        let lastMT = glideLastMTTimestamp
        let now = ProcessInfo.processInfo.systemUptime
        guard lastMT > 0, now - lastMT > 8.0 else { return }
        AppLogger.debug("[Engine] MT watchdog: no callback for \(now - lastMT)s — restarting")
        MultitouchBridge.shared.stop()
        MultitouchBridge.shared.start(callback: glideMTCallback)
        glideLastMTTimestamp = now
    }

    /// Re-enables or recreates CGEvent taps if macOS has disabled/invalidated them.
    private func checkTapHealth() {
        // Suppression tap
        if let tap = suppressionTap {
            if !CFMachPortIsValid(tap) {
                AppLogger.debug("[Engine] Tap health: suppression port invalid — recreating")
                teardownSuppressionTap()
                setupSuppressionTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) && suppressionEnabled {
                AppLogger.debug("[Engine] Tap health: suppression disabled — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            setupSuppressionTap()
        }

        // Click observation tap (listenOnly)
        let now = ProcessInfo.processInfo.systemUptime
        if let tap = clickObservationTap {
            let stale = now - lastClickEventTime > 10.0 // 10s without a tap (aggressive but safe for listen-only)
            
            if !CFMachPortIsValid(tap) {
                AppLogger.debug("[Engine] Tap health: click port invalid — recreating")
                teardownClickObservationTap()
                setupClickObservationTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) {
                AppLogger.debug("[Engine] Tap health: click disabled — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            } else if stale && glideActiveTouches >= 3 {
                // If fingers are on pad but tap hasn't fired in 10s, it's likely a zombie
                AppLogger.debug("[Engine] Tap health: click tap stale with active touches — rebuilding")
                teardownClickObservationTap()
                setupClickObservationTap()
            }
        } else {
            setupClickObservationTap()
        }
    }

    // MARK: - Suppression tap

    private func setupSuppressionTap() {
        let mask = UInt64(NSEvent.EventTypeMask.gesture.rawValue)
                 | UInt64(1 << CGEventType.scrollWheel.rawValue)
                 | UInt64(1 << CGEventType.leftMouseDown.rawValue)

        suppressionTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // Only re-enable if the tap is *supposed* to be active (≥3 fingers on pad).
                    // macOS can fire tapDisabledByTimeout even for an intentionally-disabled tap;
                    // blindly re-enabling it leaves the tap intercepting scroll/gesture events
                    // during normal cursor movement, causing 2–3 % idle CPU usage.
                    if GestureEngine.shared.suppressionEnabled,
                       let tap = GestureEngine.shared.suppressionTap {
                        AppLogger.debug("[Engine] Suppression tap timed out — re-enabling (active)")
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                if type == .leftMouseDown {
                    if glideActiveTouches >= 3 { glideClickFingerCount = glideActiveTouches }
                    return Unmanaged.passUnretained(cgEvent)
                }
                if glideActiveTouches >= 3 { return nil }
                return Unmanaged.passUnretained(cgEvent)
            },
            userInfo: nil)

        if let tap = suppressionTap {
            suppressionSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), suppressionSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
            AppLogger.debug("[Engine] Suppression tap created")
        } else {
            print("[Engine] Could not create suppression tap")
        }
    }

    private func setSuppressionActive(_ active: Bool) {
        guard active != suppressionEnabled, let tap = suppressionTap else { return }
        suppressionEnabled = active
        CGEvent.tapEnable(tap: tap, enable: active)
    }

    private func teardownSuppressionTap() {
        if let tap = suppressionTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = suppressionSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        suppressionTap    = nil
        suppressionSource = nil
        suppressionEnabled = false
    }

    // MARK: - Click observation tap (listenOnly — persists across stop/start)

    private func setupClickObservationTap() {
        guard !clickTapInstalled else { return }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        clickObservationTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                GestureEngine.shared.lastClickEventTime = ProcessInfo.processInfo.systemUptime

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = GestureEngine.shared.clickObservationTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }

                let count = getThreeFingerCount()
                let peak = getSessionPeakActiveTouches()
                AppLogger.debug("🖱️ leftMouseDown (fingers detected: \(count), peak: \(peak))")

                if count >= 3 && count == peak {
                    AppLogger.debug("✅ Click match! Triggering action...")
                    DispatchQueue.main.async { GestureEngine.shared.processClick(fingerCount: count) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil)

        if let tap = clickObservationTap {
            clickObservationSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), clickObservationSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            clickTapInstalled = true
            AppLogger.debug("[Engine] Click observation tap created")
        } else {
            print("[Engine] Could not create click observation tap")
        }
    }

    private func teardownClickObservationTap() {
        if let tap = clickObservationTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = clickObservationSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        clickObservationTap    = nil
        clickObservationSource = nil
        clickTapInstalled      = false
    }

    func forceReinitializeInputPipeline() {
        AppLogger.debug("[Engine] Force reinitializing input pipeline")
        teardownClickObservationTap()
        stop()
        start()
    }

    // MARK: - Interaction monitors

    private func installInteractionMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.handleExternalInteraction()
        }) { interactionMonitors.append(m) }

        startForceClickDetection()

        AppLogger.debug("[Engine] Installed \(interactionMonitors.count) interaction monitors")
    }

    private func startForceClickDetection() {
        let pressureMask = NSEvent.EventTypeMask(rawValue: 1 << NSEvent.EventType.pressure.rawValue)
        pressureMonitor = NSEvent.addGlobalMonitorForEvents(matching: pressureMask) { [weak self] event in
            guard let self = self, self.isRunning else { return }
            let count = getThreeFingerCount()
            let peak = getSessionPeakActiveTouches()
            guard count >= 3 && count == peak, event.stage >= 2 else { return }

            let now = Date().timeIntervalSinceReferenceDate
            guard now - self.lastForceClickTime > self.forceCooldown else { return }
            self.lastForceClickTime = now

            AppLogger.debug("✅ Force click (stage=\(event.stage))")
            DispatchQueue.main.async { self.processClick(fingerCount: count) }
        }
        if let pm = pressureMonitor { interactionMonitors.append(pm) }
    }

    func processClick(fingerCount n: Int, isForce: Bool = false) {
        if case .switchingApps = phase { return }

        // ── Strict simultaneous-touch guard ────────────────────────────────────
        // Replaced by exact Archive logic (no age-spread validation).
        // ───────────────────────────────────────────────────────────────────────

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastClickProcessedTime > 0.1 else { return }
        lastClickProcessedTime = now
        glideClickFingerCount = 0

        let modifiers = captureModifiers()
        guard let rule = bestRule(fingers: n, direction: .click, modifiers: modifiers) else { return }

        AppLogger.debug("[Engine] Click — \(n) fingers \(modifierDebugLabel(modifiers)) → \(rule.action.rawValue)")
        clearReciprocalToken()
        phase = .fired
        Haptic.click()

        if rule.action == .quitApp {
            let loc = NSEvent.mouseLocation
            DispatchQueue.main.async { ActionExecutor.shared.quitAppAtCursor(loc) }
        } else {
            DispatchQueue.main.async { ActionExecutor.shared.execute(rule.action, appPath: rule.appPath) }
        }
        updateObservableState()
    }

    private func handleExternalInteraction() {
        guard glideActiveTouches < 3 else { return }
        if case .fired = phase { return }
        if case .switchingApps = phase { return }
        clearReciprocalToken()
    }

    // MARK: - Touch update (main entry point)

    func onTouches(_ frame: TouchFrameData) {
        setSuppressionActive(frame.count >= 3)

        let n = Int(frame.count)
        currentFingerCount = n

        if n < 3 {
            glideClickFingerCount = 0
            finishIfNeeded()
            updateObservableState()
            return
        }

        currentCentroidX = frame.cx
        currentCentroidY = frame.cy

        if glideClickFingerCount >= 3 { return }

        let now = ProcessInfo.processInfo.systemUptime

        switch phase {

        case .idle:
            guard hasAnySwipeRule(fingers: n) else { return }
            if tuning.edgeMarginEnabled {
                let m = tuning.edgeMargin
                if frame.cx < m.left || frame.cx > (1.0 - m.right)
                || frame.cy < m.bottom || frame.cy > (1.0 - m.top) { return }
            }
            phase = .candidate(CandidateData(
                startX: frame.cx, startY: frame.cy,
                fingers: n, startTime: now,
                initialSpread: frame.spread,
                modifiersAtStart: captureModifiers(),
                frameCount: 1, cumulativeSpreadDelta: 0,
                prevSpread: frame.spread, minCoherence: frame.coherence,
                prevCx: frame.cx, prevCy: frame.cy,
                velocitySamples: []
            ))

        case .candidate(var data):
            if n > data.fingers {
                guard hasAnySwipeRule(fingers: n) else { phase = .ignored; updateObservableState(); return }
                phase = .candidate(CandidateData(
                    startX: frame.cx, startY: frame.cy,
                    fingers: n, startTime: now,
                    initialSpread: frame.spread,
                    modifiersAtStart: captureModifiers(),
                    frameCount: 1, cumulativeSpreadDelta: 0,
                    prevSpread: frame.spread, minCoherence: frame.coherence,
                    prevCx: frame.cx, prevCy: frame.cy,
                    velocitySamples: []
                ))
                AppLogger.debug("[Engine] Candidate restarted — \(n) fingers")
                return
            }
            if n < data.fingers { phase = .ignored; updateObservableState(); return }

            data.frameCount += 1

            let frameDx = frame.cx - data.prevCx
            let frameDy = frame.cy - data.prevCy
            let movedFromStart = ((frame.cx - data.startX) * (frame.cx - data.startX)
                                + (frame.cy - data.startY) * (frame.cy - data.startY)).squareRoot()
            // Ignore placement frames — only sample once the centroid is actually moving.
            if movedFromStart >= max(0.002, tuning.initialThreshold * 0.12) {
                appendVelocitySample((frameDx * frameDx + frameDy * frameDy).squareRoot(), to: &data.velocitySamples)
            }
            data.prevCx = frame.cx; data.prevCy = frame.cy

            let frameDelta = abs(frame.spread - data.prevSpread)
            data.cumulativeSpreadDelta += frameDelta
            data.prevSpread = frame.spread
            if frame.coherence < data.minCoherence { data.minCoherence = frame.coherence }

            if frameDelta > tuning.pinchFrameSpreadThreshold * 1.5 {
                phase = .ignored; updateObservableState(); return
            }

            let centroidMovement = ((frame.cx - data.startX) * (frame.cx - data.startX)
                                  + (frame.cy - data.startY) * (frame.cy - data.startY)).squareRoot()
            let totalSpreadChange = abs(frame.spread - data.initialSpread)

            if totalSpreadChange > 0.002 && totalSpreadChange > centroidMovement * 0.8 && data.frameCount >= 2 {
                phase = .ignored; updateObservableState(); return
            }

            let minFrames = max(Int(tuning.candidateFrames), 3)
            guard data.frameCount >= minFrames else { phase = .candidate(data); return }

            if data.gestureKind == .unknown {
                data.classificationFrameDelay += 1
                if data.classificationFrameDelay >= 2 {
                    data.gestureKind = totalSpreadChange > centroidMovement * 0.8 ? .pinch : .swipe
                    AppLogger.debug("[Engine] Classified as \(data.gestureKind)")
                }
            }

            if data.gestureKind == .pinch { phase = .ignored; updateObservableState(); return }

            if totalSpreadChange > 0.002 && totalSpreadChange > centroidMovement * 0.5 {
                phase = .ignored; updateObservableState(); return
            }
            if data.cumulativeSpreadDelta > tuning.pinchSpreadThreshold {
                phase = .ignored; updateObservableState(); return
            }
            if data.minCoherence < tuning.swipeCoherenceThreshold {
                phase = .ignored; updateObservableState(); return
            }

            let spreadIsSmall    = data.cumulativeSpreadDelta < tuning.pinchSpreadThreshold
            let centroidDominates = centroidMovement > totalSpreadChange
            let coherenceOK      = data.minCoherence >= tuning.swipeCoherenceThreshold

            if spreadIsSmall && centroidDominates && coherenceOK && data.gestureKind != .pinch {
                data.gestureKind = .swipe
                let swipeData = SwipeTrackData(
                    startX: data.startX, startY: data.startY,
                    lastX: frame.cx, lastY: frame.cy,
                    fingers: data.fingers, startTime: data.startTime,
                    modifiersAtStart: data.modifiersAtStart,
                    velocitySamples: data.velocitySamples,
                    recentDeltas: [],
                    initialSpread: data.initialSpread,
                    prevSpread: frame.spread,
                    cumulativeSpreadDelta: data.cumulativeSpreadDelta
                )
                phase = .lockedSwipe(swipeData)
                AppLogger.debug("[Engine] Locked as swipe — \(n) fingers")
                updateObservableState()
                processSwipeFrame(frame, data: swipeData, now: now)
            } else if data.frameCount >= minFrames + 5 {
                phase = .ignored; updateObservableState()
            } else {
                phase = .candidate(data)
            }

        case .lockedSwipe(let data):
            guard n == data.fingers else { finishIfNeeded(); return }
            processSwipeFrame(frame, data: data, now: now)

        case .switchingApps(var data):
            guard n == 3 else { commitAppSwitcher(data: data); return }
            let delta = frame.cx - data.refX
            if abs(delta) > tuning.appSwitcherStepThreshold,
               now - lastStepTime >= tuning.appSwitcherDebounce {
                // Forward step
                if delta > 0, data.index < data.effectiveMax {
                    Haptic.switcherStep(); sendCmdTab()
                    lastStepTime = now; data.refX = frame.cx
                    data.index += 1
                    // If we landed on Finder in the middle, skip one more
                    if let fi = data.finderIndex, data.index == fi,
                       data.index < data.effectiveMax {
                        sendCmdTab()
                        data.index += 1
                    }
                    phase = .switchingApps(data)
                // Backward step
                } else if delta < 0, data.index > data.effectiveMin {
                    Haptic.switcherStep(); sendCmdShiftTab()
                    lastStepTime = now; data.refX = frame.cx
                    data.index -= 1
                    // If we landed on Finder in the middle, skip one more
                    if let fi = data.finderIndex, data.index == fi,
                       data.index > data.effectiveMin {
                        sendCmdShiftTab()
                        data.index -= 1
                    }
                    phase = .switchingApps(data)
                }
            }

        case .ignored, .fired:
            break
        }
    }

    // MARK: - Swipe frame processing

    private func processSwipeFrame(_ frame: TouchFrameData, data: SwipeTrackData, now: TimeInterval) {
        var updated = data

        let frameDx = frame.cx - data.lastX
        let frameDy = frame.cy - data.lastY
        let frameDist = (frameDx * frameDx + frameDy * frameDy).squareRoot()
        updated.lastX = frame.cx; updated.lastY = frame.cy

        let swipeSpreadDelta = abs(frame.spread - updated.prevSpread)
        updated.cumulativeSpreadDelta += swipeSpreadDelta
        updated.prevSpread = frame.spread

        let swipeSpreadChange    = abs(frame.spread - updated.initialSpread)
        let swipeCentroidMovement = ((frame.cx - updated.startX) * (frame.cx - updated.startX)
                                   + (frame.cy - updated.startY) * (frame.cy - updated.startY)).squareRoot()

        if swipeSpreadChange > 0.003 && swipeSpreadChange > swipeCentroidMovement * 0.8 {
            phase = .ignored
            AppLogger.debug("[Engine] Swipe aborted — spread grew mid-swipe")
            updateObservableState(); return
        }

        appendVelocitySample(frameDist, to: &updated.velocitySamples)

        updated.recentDeltas.insert((dx: frameDx, dy: frameDy), at: 0)

        var totalDx: Float = 0, totalDy: Float = 0
        var thresholdIndex: Int?
        for (i, d) in updated.recentDeltas.enumerated() {
            totalDx += d.dx; totalDy += d.dy
            if (totalDx * totalDx + totalDy * totalDy).squareRoot() >= tuning.initialThreshold {
                thresholdIndex = i; break
            }
        }

        guard let cutoff = thresholdIndex else { phase = .lockedSwipe(updated); return }

        if cutoff + 1 < updated.recentDeltas.count {
            updated.recentDeltas.removeSubrange((cutoff + 1)...)
        }

        let angleDeg = atan2(totalDy, totalDx) * (180.0 / .pi)
        let angle360 = angleDeg < 0 ? angleDeg + 360 : angleDeg

        guard let direction = directionFromAngle(angle360) else {
            phase = .lockedSwipe(updated); return
        }

        if consumeReciprocalToken(fingers: data.fingers, direction: direction) {
            phase = .fired; updateObservableState(); return
        }

        let elapsed = max(now - updated.startTime, 0.001)
        let speed = classifySpeed(
            velocitySamples: updated.velocitySamples,
            totalDisplacement: swipeCentroidMovement,
            elapsedSeconds: elapsed
        )

        // Pre-fire safety gate
        let gateSpreadOK = abs(frame.spread - updated.initialSpread) < tuning.pinchSpreadThreshold * 0.8
        let gateCoherenceOK = frame.coherence > 0.8
        guard gateSpreadOK && gateCoherenceOK else {
            phase = .ignored
            AppLogger.debug("[Engine] Swipe blocked by safety gate")
            updateObservableState(); return
        }

        if let rule = bestRule(fingers: data.fingers, direction: direction, speed: speed,
                               modifiers: updated.modifiersAtStart) {
            AppLogger.debug("[Engine] Swipe \(direction.rawValue) — \(data.fingers)F \(speed.rawValue) \(modifierDebugLabel(updated.modifiersAtStart)) (Δ=\(String(format: "%.3f", swipeCentroidMovement)) t=\(String(format: "%.2f", elapsed))s) → \(rule.action.rawValue)")
            if rule.action == .appSwitcherNext || rule.action == .appSwitcherPrev {
                if !beginAppSwitcher(for: rule.action, refX: frame.cx) { phase = .fired }
            } else {
                executeSwipeRule(rule, fingers: data.fingers, direction: direction)
                phase = .fired
            }
        } else {
            AppLogger.debug("[Engine] Swipe \(direction.rawValue) — \(data.fingers)F \(speed.rawValue): no matching rule")
            phase = .fired
        }
        updateObservableState()
    }

    // MARK: - Direction from angle

    private func directionFromAngle(_ angle: Float) -> GestureDirection? {
        let tol = tuning.swipeAngleTolerance
        if angle >= (360 - tol) || angle < tol          { return .swipeRight }
        if angle >= (90 - tol)  && angle < (90 + tol)   { return .swipeUp }
        if angle >= (180 - tol) && angle < (180 + tol)  { return .swipeLeft }
        if angle >= (270 - tol) && angle < (270 + tol)  { return .swipeDown }
        return nil
    }

    // MARK: - Finish / reset

    private func finishIfNeeded() {
        if case .switchingApps(let data) = phase { commitAppSwitcher(data: data) }
        phase = .idle
        lastStepTime = 0
    }

    private func commitAppSwitcher(data: SwitcherData) {
        _ = data
        Haptic.switcherCommit()
        selectInAppSwitcher()
        AppLogger.debug("[Engine] App-switcher committed")

        // After the app activates, restore any minimized windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            GestureEngine.restoreMinimizedWindows()
        }
    }

    /// Uses the Accessibility API to unminimize all minimized windows
    /// of the currently frontmost application.
    private static func restoreMinimizedWindows() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        var restoredCount = 0
        for window in windows {
            var minimizedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                  let isMinimized = minimizedRef as? Bool, isMinimized else { continue }

            let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            if result == .success { restoredCount += 1 }
        }

        if restoredCount > 0 {
            AppLogger.debug("[Engine] Restored \(restoredCount) minimized window(s)")
        }
    }

    private func selectInAppSwitcher() {
        sendKeyEvent(kOpt, down: true,  flags: [.maskAlternate])
        sendKeyEvent(kCmd, down: false, flags: [.maskCommand, .maskAlternate])
        sendKeyEvent(kOpt, down: false, flags: [])
    }

    private func beginAppSwitcher(for action: GestureAction, refX: Float) -> Bool {
        var apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        guard apps.count > 1 else { return false }

        // Sort by MRU order to match the actual Cmd+Tab ordering.
        // Apps not yet seen in mruAppOrder go to the end.
        let mru = self.mruAppOrder
        apps.sort { a, b in
            let ai = mru.firstIndex(of: a.processIdentifier) ?? Int.max
            let bi = mru.firstIndex(of: b.processIdentifier) ?? Int.max
            return ai < bi
        }

        // Locate windowless Finder in the list (if present)
        let finderIdx: Int? = {
            guard !GestureEngine.finderHasVisibleWindows() else { return nil }
            return apps.firstIndex { $0.bundleIdentifier == "com.apple.finder" }
        }()

        // Compute effective boundaries — shrink if Finder is at an edge
        var effMin = 0
        var effMax = apps.count - 1
        if let fi = finderIdx {
            if fi == 0             { effMin = 1 }
            if fi == apps.count - 1 { effMax = apps.count - 2 }
        }
        guard effMin < effMax else { return false }  // nothing to switch to

        clearReciprocalToken()
        sendKeyEvent(kCmd, down: true, flags: .maskCommand)
        Haptic.switcherOpen()

        var index: Int
        if action == .appSwitcherNext {
            sendCmdTab(); index = 1
            // If landed on Finder in the middle, skip one more
            if let fi = finderIdx, index == fi, index < effMax {
                sendCmdTab(); index += 1
            }
        } else {
            sendCmdShiftTab(); index = apps.count - 1
            // If landed on Finder in the middle, skip one more
            if let fi = finderIdx, index == fi, index > effMin {
                sendCmdShiftTab(); index -= 1
            }
        }

        lastStepTime = ProcessInfo.processInfo.systemUptime
        phase = .switchingApps(SwitcherData(
            refX: refX, index: index, apps: apps,
            finderIndex: finderIdx, effectiveMin: effMin, effectiveMax: effMax
        ))
        updateObservableState()
        return true
    }

    // MARK: - MRU app tracking

    private func startMRUTracking() {
        // Seed with current frontmost app
        if let front = NSWorkspace.shared.frontmostApplication {
            mruAppOrder = [front.processIdentifier]
        }
        // Also seed from running apps so we have coverage immediately
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if !mruAppOrder.contains(app.processIdentifier) {
                mruAppOrder.append(app.processIdentifier)
            }
        }
        // Listen for every app activation to maintain exact MRU order
        mruObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            self.mruAppOrder.removeAll { $0 == pid }
            self.mruAppOrder.insert(pid, at: 0)
        }
    }

    // MARK: - Rule matching

    private func captureModifiers() -> CapturedModifiers {
        CapturedModifiers(NSEvent.modifierFlags)
    }

    private func modifierDebugLabel(_ m: CapturedModifiers) -> String {
        var parts: [String] = []
        if m.shift { parts.append("⇧") }
        if m.control { parts.append("⌃") }
        if m.option { parts.append("⌥") }
        if m.command { parts.append("⌘") }
        return parts.isEmpty ? "" : "[\(parts.joined())]"
    }

    private func bestRule(
        fingers: Int,
        direction: GestureDirection,
        speed: GestureSpeed = .normal,
        modifiers: CapturedModifiers
    ) -> GestureRule? {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isFullscreen = ActionExecutor.shared.isFrontmostWindowFullscreen()
        let isMaximized  = ActionExecutor.shared.isFrontmostWindowMaximized()

        let matching = Settings.shared.rules.filter { rule in
            rule.isActive
                && rule.fingers == fingers
                && rule.direction == direction
                && matchesWindowState(rule, isFullscreen: isFullscreen, isMaximized: isMaximized)
                && matchesAppFilter(rule, bundleID: bid)
                && modifiers.matches(rule.modifierFilter)
        }

        return bestRuleMatch(in: matching, speed: speed)
    }

    private func matchesWindowState(_ rule: GestureRule, isFullscreen: Bool, isMaximized: Bool) -> Bool {
        switch rule.windowStateFilter {
        case .any:            return true
        case .fullscreen:     return isFullscreen
        case .notFullscreen:  return !isFullscreen
        case .maximized:      return isMaximized
        case .notMaximized:   return !isMaximized
        }
    }

    private func matchesAppFilter(_ rule: GestureRule, bundleID: String?) -> Bool {
        guard let filter = rule.appFilter, !filter.isEmpty else { return true }
        return filter == bundleID
    }

    private func hasAnySwipeRule(fingers: Int) -> Bool {
        let swipeDirs: [GestureDirection] = [.swipeLeft, .swipeRight, .swipeUp, .swipeDown]
        return Settings.shared.rules.contains {
            $0.isActive && $0.fingers == fingers && swipeDirs.contains($0.direction)
        }
    }

    private func bestRuleMatch(in rules: [GestureRule], speed: GestureSpeed) -> GestureRule? {
        let normalized = speed == .any ? GestureSpeed.normal : speed
        // Latest rule in the list wins when several share the same gesture signature.
        if let exact = rules.last(where: { ($0.speed == .any ? .normal : $0.speed) == normalized }) {
            return exact
        }
        // When slow/normal/fast are all configured for the same gesture, never fall back
        // to a different speed — that caused slow swipes to trigger normal-speed actions.
        let configuredSpeeds = Set(rules.map { $0.speed == .any ? GestureSpeed.normal : $0.speed })
        if configuredSpeeds.count > 1 { return nil }
        guard speed != .normal else { return nil }
        return rules.last(where: { ($0.speed == .any ? .normal : $0.speed) == .normal })
    }

    // MARK: - Speed classification

    /// Rolling window of recent per-frame centroid displacements (movement-gated in candidate phase).
    private func appendVelocitySample(_ distance: Float, to samples: inout [Float]) {
        guard distance > 0 else { return }
        samples.append(distance)
        let cap = tuning.speedSampleCount
        if samples.count > cap {
            samples.removeFirst(samples.count - cap)
        }
    }

    /// Classifies swipe speed using median frame displacement and overall displacement / duration.
    private func classifySpeed(
        velocitySamples: [Float],
        totalDisplacement: Float,
        elapsedSeconds: TimeInterval
    ) -> GestureSpeed {
        let slowFrame = tuning.slowVelocityThreshold
        let fastFrame = tuning.fastVelocityThreshold
        // Approximate MT callback rate for mapping frame thresholds to units/sec.
        let fps: Float = 60
        let slowPerSecond = slowFrame * fps
        let fastPerSecond = fastFrame * fps

        let medianFrame: Float = {
            guard !velocitySamples.isEmpty else { return 0 }
            let sorted = velocitySamples.sorted()
            return sorted[sorted.count / 2]
        }()

        let perSecond: Float = totalDisplacement / Float(max(elapsedSeconds, 0.05))

        let frameSaysSlow = medianFrame > 0 && medianFrame <= slowFrame
        let frameSaysFast = medianFrame >= fastFrame
        let timeSaysSlow = perSecond <= slowPerSecond * 1.2
        let timeSaysFast = perSecond >= fastPerSecond * 0.85

        // Short flicks: trust recent frame peaks; long deliberate swipes: trust average speed.
        let isShortGesture = elapsedSeconds < 0.22

        if isShortGesture {
            if frameSaysFast { return .fast }
            if frameSaysSlow && timeSaysSlow { return .slow }
        } else {
            if timeSaysSlow && !frameSaysFast { return .slow }
            if timeSaysFast || frameSaysFast { return .fast }
        }

        if frameSaysSlow && timeSaysSlow { return .slow }
        if frameSaysFast || timeSaysFast { return .fast }
        return .normal
    }

    // MARK: - Reciprocal token

    private func executeSwipeRule(_ rule: GestureRule, fingers: Int, direction: GestureDirection) {
        Haptic.forAction(rule.action)
        ActionExecutor.shared.execute(rule.action, appPath: rule.appPath)
        if rule.reciprocalEnabled {
            reciprocalToken = makeReciprocalToken(for: rule.action, fingers: fingers, direction: direction)
        } else {
            clearReciprocalToken()
        }
        updateObservableState()
    }

    private func consumeReciprocalToken(fingers: Int, direction: GestureDirection) -> Bool {
        guard let token = reciprocalToken,
              token.fingers == fingers, token.direction == direction else { return false }
        if token.inverseAction == .restoreMinimizedApps,
           !ActionExecutor.shared.hasRestorableMinimizedApps {
            clearReciprocalToken(); return false
        }
        AppLogger.debug("[Engine] Reciprocal \(direction.rawValue) → \(token.inverseAction.rawValue)")
        let action = token.inverseAction
        clearReciprocalToken()
        Haptic.reciprocal()
        ActionExecutor.shared.execute(action)
        return true
    }

    private func makeReciprocalToken(for action: GestureAction, fingers: Int, direction: GestureDirection) -> ReciprocalToken? {
        guard let rev = opposite(direction), let inverse = action.inverseAction else { return nil }
        return ReciprocalToken(inverseAction: inverse, fingers: fingers, direction: rev)
    }

    private func clearReciprocalToken() {
        reciprocalToken = nil
        isReciprocalActive = false
    }

    private func opposite(_ dir: GestureDirection) -> GestureDirection? {
        switch dir {
        case .swipeLeft:  return .swipeRight
        case .swipeRight: return .swipeLeft
        case .swipeUp:    return .swipeDown
        case .swipeDown:  return .swipeUp
        case .click:      return nil
        }
    }

    // MARK: - Observable state

    private func updateObservableState() {
        switch phase {
        case .idle:          currentPhaseName = "Idle"
        case .candidate:     currentPhaseName = "Candidate"
        case .lockedSwipe:   currentPhaseName = "Locked (Swipe)"
        case .ignored:       currentPhaseName = "Ignored"
        case .fired:         currentPhaseName = "Fired"
        case .switchingApps: currentPhaseName = "App Switcher"
        }
        isReciprocalActive = reciprocalToken != nil
        onStateChange?()
    }

    // MARK: - Key events

    private func sendCmdTab() {
        sendKeyEvent(kTab, down: true,  flags: .maskCommand)
        sendKeyEvent(kTab, down: false, flags: .maskCommand)
    }

    private func sendCmdShiftTab() {
        sendKeyEvent(kShift, down: true,  flags: [.maskCommand, .maskShift])
        sendKeyEvent(kTab,   down: true,  flags: [.maskCommand, .maskShift])
        sendKeyEvent(kTab,   down: false, flags: [.maskCommand, .maskShift])
        sendKeyEvent(kShift, down: false, flags: .maskCommand)
    }

    private func sendKeyEvent(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let src = keyEventSource ?? CGEventSource(stateID: .hidSystemState)
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    // MARK: - Finder window inspection (Accessibility API)

    /// Returns `true` if Finder has at least one real, visible directory window.
    /// A window is considered real/visible only if:
    ///  - AXRole == "AXWindow"
    ///  - AXTitle != "Desktop"
    ///  - AXMinimized == false
    ///  - AXSize width ≥ 1 and height ≥ 1
    static func finderHasVisibleWindows() -> Bool {
        guard let finderApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first else { return false }

        let axApp = AXUIElementCreateApplication(finderApp.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        for window in windows {
            // Check AXRole == "AXWindow"
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String, role == "AXWindow" else {
                continue
            }

            // Exclude "Desktop" title
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, title == "Desktop" {
                continue
            }

            // Check not minimized
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool, minimized {
                continue
            }

            // Check non-zero size
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
                var size = CGSize.zero
                if AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) {
                    if size.width < 1 || size.height < 1 { continue }
                }
            }

            // Passed all checks — this is a real, visible Finder window
            return true
        }

        return false
    }
}

// ─────────────────────────────────────────────
// MARK: - Global MT state (written on MT/HID thread, read on main)
// ─────────────────────────────────────────────

private var deviceFingerCounts: [UnsafeMutableRawPointer: Int] = [:]
private var sessionPeakActiveTouches: Int = 0
private let countsLock = NSLock()

func updateDeviceFingerCount(device: UnsafeMutableRawPointer, count: Int) {
    countsLock.lock()
    defer { countsLock.unlock() }
    deviceFingerCounts[device] = count
    
    let currentMax = deviceFingerCounts.values.max() ?? 0
    if currentMax == 0 {
        sessionPeakActiveTouches = 0
    } else {
        sessionPeakActiveTouches = max(sessionPeakActiveTouches, currentMax)
    }
}

func getThreeFingerCount() -> Int {
    countsLock.lock()
    defer { countsLock.unlock() }
    return deviceFingerCounts.values.max() ?? 0
}

func getSessionPeakActiveTouches() -> Int {
    countsLock.lock()
    defer { countsLock.unlock() }
    return sessionPeakActiveTouches
}

/// Int32 stores/loads are effectively atomic on arm64/x86_64.
var glideActiveTouches: Int32 = 0
var glideClickFingerCount: Int32 = 0
var glidePeakFingerCount: Int32 = 0
var glideLastMTTimestamp: TimeInterval = 0

/// Frame deduplication counter. For < 3 fingers, skip redundant main-queue
/// dispatches when the finger count hasn't changed.
var glideLastDispatchedCount: Int32 = 0

// ── Per-finger age tracking ───────────────────────────────────────────────────
/// Maps each MultitouchSupport finger identifier to the uptime at which it was
/// first seen on the pad.  Written and read exclusively from the MT-callback
/// thread — no locking required.
private var glideFingerFirstSeen: [Int32: TimeInterval] = [:]

/// Age (seconds) of the oldest / newest currently-active finger.
/// Written on the MT-callback thread; read on the main thread at click time.
/// Double is 8-byte aligned → store/load is effectively atomic on arm64 & x86_64.
var glideOldestFingerAge: Double = 0.0
var glideNewestFingerAge: Double = 0.0

// ─────────────────────────────────────────────
// MARK: - Global MT callback
// ─────────────────────────────────────────────

let glideMTCallback: MTContactCallback = { device, data, count, _, _ in
    glideLastMTTimestamp = ProcessInfo.processInfo.systemUptime

    var validTouches: [MTTouch] = []
    if let data, count > 0 {
        let n = Int(count)
        let raw = data.assumingMemoryBound(to: MTTouch.self)
        let tuning = Settings.shared.tuning

        if tuning.edgeMarginEnabled {
            let m = tuning.edgeMargin
            for i in 0..<n {
                let t = raw[i]
                let x = t.normalizedPosition.x; let y = t.normalizedPosition.y
                if !(x < m.left || x > 1.0 - m.right || y < m.bottom || y > 1.0 - m.top) {
                    validTouches.append(t)
                }
            }
        } else {
            for i in 0..<n { validTouches.append(raw[i]) }
        }
    }

    let active = validTouches.filter { $0.state >= 3 && $0.state <= 4 }
    if let dev = device {
        updateDeviceFingerCount(device: dev, count: active.count)
    }

    let validCount = Int32(validTouches.count)

    guard validCount > 0 else {
        if glideActiveTouches > 0 {
            glideActiveTouches = 0
            glideLastDispatchedCount = 0
            // Clear per-finger age tracking — all fingers lifted
            glideFingerFirstSeen.removeAll(keepingCapacity: true)
            glideOldestFingerAge = 0
            glideNewestFingerAge = 0
            DispatchQueue.main.async {
                glideClickFingerCount = 0
                GestureEngine.shared.peakResetWorkItem?.cancel()
                let work = DispatchWorkItem { glidePeakFingerCount = 0 }
                GestureEngine.shared.peakResetWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                GestureEngine.shared.onTouches(TouchFrameData(count: 0, cx: 0, cy: 0, spread: 0, coherence: 1))
            }
        }
        return 0
    }

    let n = Int(validCount)

    // ── Per-finger age tracking ───────────────────────────────────────────────
    // Track when each finger ID first appeared on the pad.  This lets click
    // detection distinguish "all N fingers placed together" (small age spread)
    // from "M fingers resting + 1 tapping" (large age spread).
    // Accessed only from this MT-callback thread → no locking needed.
    // glideOldestFingerAge / glideNewestFingerAge are Double (8-byte aligned) →
    // store/load is effectively atomic on arm64 & x86_64 (same guarantee as
    // Int32 used elsewhere in this file).
    let nowTs = glideLastMTTimestamp

    // Register newly-arrived fingers
    for touch in validTouches {
        if glideFingerFirstSeen[touch.identifier] == nil {
            glideFingerFirstSeen[touch.identifier] = nowTs
        }
    }
    // Remove departed finger records (cheap: dict count rarely mismatches)
    if glideFingerFirstSeen.count != validTouches.count {
        let activeIDs = Set(validTouches.map { $0.identifier })
        glideFingerFirstSeen = glideFingerFirstSeen.filter { activeIDs.contains($0.key) }
    }
    // Publish oldest/newest ages for the main-thread click handler
    if let oldest = glideFingerFirstSeen.values.min(),
       let newest = glideFingerFirstSeen.values.max() {
        glideOldestFingerAge = nowTs - oldest
        glideNewestFingerAge = nowTs - newest
    }
    // ─────────────────────────────────────────────────────────────────────────

    // Save previous count before updating so we can detect threshold crossing
    let prevActiveTouches = glideActiveTouches
    glideActiveTouches = validCount

    if validCount >= 3 {
        glidePeakFingerCount = validCount
        // Cancel the peak-reset work item only when first crossing the 3-finger
        // threshold — not on every frame (which was dispatching 120×/s and
        // causing measurable CPU overhead at idle).
        if prevActiveTouches < 3 {
            DispatchQueue.main.async { GestureEngine.shared.peakResetWorkItem?.cancel() }
        }
    }

    // Skip redundant dispatches for < 3 fingers (prevents drag/scroll lag)
    if validCount < 3 && validCount == glideLastDispatchedCount { return 0 }
    glideLastDispatchedCount = validCount

    // Centroid
    var sumX: Float = 0, sumY: Float = 0
    for i in 0..<n { sumX += validTouches[i].normalizedPosition.x; sumY += validTouches[i].normalizedPosition.y }
    let cx = sumX / Float(n)
    let cy = sumY / Float(n)

    // Spread (average finger-to-centroid distance)
    var spread: Float = 0
    if n >= 3 {
        var s: Float = 0
        for i in 0..<n {
            let dx = validTouches[i].normalizedPosition.x - cx
            let dy = validTouches[i].normalizedPosition.y - cy
            s += (dx * dx + dy * dy).squareRoot()
        }
        spread = s / Float(n)
    }

    // Directional coherence (1.0 = all fingers same direction, 0.0 = diverging)
    var coherence: Float = 1.0
    if n >= 3 {
        var avgDirX: Float = 0, avgDirY: Float = 0, movingFingers = 0
        for i in 0..<n {
            let vx = validTouches[i].velocity.x; let vy = validTouches[i].velocity.y
            let mag = (vx * vx + vy * vy).squareRoot()
            if mag > 0.01 { avgDirX += vx / mag; avgDirY += vy / mag; movingFingers += 1 }
        }
        if movingFingers > 0 {
            avgDirX /= Float(movingFingers); avgDirY /= Float(movingFingers)
            coherence = (avgDirX * avgDirX + avgDirY * avgDirY).squareRoot()
        }
    }

    let frameData = TouchFrameData(count: validCount, cx: cx, cy: cy, spread: spread, coherence: coherence)
    DispatchQueue.main.async { GestureEngine.shared.onTouches(frameData) }
    return 0
}
