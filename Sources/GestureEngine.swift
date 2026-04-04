import Cocoa
import CoreGraphics

// ─────────────────────────────────────────────
// MARK: - Haptic engine
// ─────────────────────────────────────────────

private enum Haptic {

    static func forAction(_ action: GestureAction) {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch action {
        case .quitApp, .forceQuitApp, .quitFrontmost,
             .closeWindow, .sleep, .lockScreen:
            pattern = .generic
        case .minimizeWindow, .minimizeAllApps, .restoreMinimizedApps,
             .maximizeWindow, .restoreWindow,
             .enterFullscreen, .exitFullscreen, .toggleFullscreen,
             .snapLeft, .snapRight, .snapTopLeft, .snapTopRight,
             .snapBottomLeft, .snapBottomRight, .centerWindow, .moveNextDisplay:
            pattern = .levelChange
        case .missionControl, .appExpose, .showDesktop, .launchpad,
             .spotlight, .notifCenter, .screenshotArea, .screenshotFull,
             .hideApp, .hideOthers, .cycleWindows, .switchAppNext, .switchAppPrev,
             .appSwitcherNext, .appSwitcherPrev:
            pattern = .alignment
        case .openApp:
            pattern = .generic
        case .doNothing:
            return
        }
        perform(pattern, time: .now)
    }

    static func switcherStep() {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        perform(.alignment, time: .now)
    }

    static func switcherOpen() {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        perform(.generic, time: .now)
    }

    static func switcherCommit() {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        perform(.generic, time: .now)
    }

    static func reciprocal() {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        perform(.levelChange, time: .now)
    }

    static func click() {
        guard Settings.shared.hapticFeedbackEnabled else { return }
        perform(.generic, time: .now)
    }

    private static func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        time: NSHapticFeedbackManager.PerformanceTime
    ) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: time)
    }
}

// ─────────────────────────────────────────────
// MARK: - Touch frame data (MT callback → engine)
// ─────────────────────────────────────────────

/// Computed per MT callback frame on the MT thread, passed to onTouches()
/// on the main queue. Encapsulates all the evidence the engine needs.
struct TouchFrameData {
    let count: Int32
    let cx: Float
    let cy: Float
    let spread: Float         // average finger-to-centroid distance
    let coherence: Float      // 0.0 = chaotic, 1.0 = all fingers same direction
}

// ─────────────────────────────────────────────
// MARK: - GestureEngine
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
// MARK: - Gesture classification
// ─────────────────────────────────────────────

/// Mutually exclusive gesture type, decided during the candidate phase.
/// Once set to .swipe or .pinch, it NEVER switches back.
private enum GestureKind {
    case unknown
    case swipe
    case pinch
}

final class GestureEngine {

    static let shared = GestureEngine()
    private init() {}

    // MARK: - Session state machine

    /// Candidate-phase data: collected during the first few frames
    /// to decide if this touch sequence is a swipe.
    private struct CandidateData {
        let startX: Float
        let startY: Float
        let fingers: Int
        let startTime: TimeInterval
        let initialSpread: Float
        var frameCount: Int
        var cumulativeSpreadDelta: Float  // absolute cumulative change
        var prevSpread: Float
        var minCoherence: Float           // worst coherence seen so far
        var fingerCountStable: Bool
        // Velocity tracking (InputActions-inspired)
        var prevCx: Float
        var prevCy: Float
        var velocitySamples: [Float]      // per-frame centroid delta magnitudes
        // Gesture classification (pinch vs swipe)
        var gestureKind: GestureKind = .unknown
        var classificationFrameDelay: Int = 0  // frames elapsed since enough data to classify
    }

    /// Swipe tracking data: used after locking as swipe to track
    /// centroid movement toward the threshold.
    /// Mirrors InputActions' sliding window of per-frame deltas for direction detection.
    private struct SwipeTrackData {
        let startX: Float
        let startY: Float
        var lastX: Float
        var lastY: Float
        let fingers: Int
        let startTime: TimeInterval
        var velocitySamples: [Float]                // for speed classification
        var recentDeltas: [(dx: Float, dy: Float)]  // sliding window (InputActions: m_swipeDeltas)
        // Spread tracking for pre-swipe safety gate
        let initialSpread: Float
        var prevSpread: Float
        var cumulativeSpreadDelta: Float
    }

    /// App-switcher continuous-scroll data.
    private struct SwitcherData {
        var refX: Float
        var index: Int
        let apps: [NSRunningApplication]
    }

    /// The unified session state machine.
    /// `idle → candidate → lockedSwipe → fired → idle`
    ///                    `↘ ignored → idle`
    private enum GesturePhase {
        case idle
        case candidate(CandidateData)
        case lockedSwipe(SwipeTrackData)
        case ignored                        // not a swipe — do nothing until lift
        case fired                          // action fired, absorb remaining touches
        case switchingApps(SwitcherData)     // app-switcher continuous mode
    }

    // MARK: - Reciprocal token

    private struct ReciprocalToken {
        let inverseAction: GestureAction
        let fingers: Int
        let direction: GestureDirection   // the reverse direction needed to consume
        let contextApp: String?           // bundle ID at creation time
        let sessionGeneration: UInt64     // which gesture session created this
        let createdAt: TimeInterval       // safety timeout reference
    }

    // MARK: - State

    private var phase: GesturePhase = .idle
    private var reciprocalToken: ReciprocalToken?
    private var sessionGeneration: UInt64 = 0
    private var isRunning = false

    /// Timer that detects when the MT callback stops firing (device went stale)
    /// and force-restarts the multitouch bridge.
    private var mtWatchdogTimer: Timer?

    private var suppressionTap: CFMachPort?
    private var suppressionSource: CFRunLoopSource?
    private var suppressionEnabled = false

    /// Dedicated listen-only event tap for click detection.
    /// Unlike the suppression tap (.defaultTap), listen-only taps are NOT
    /// disabled by macOS after sleep/wake. This tap PERSISTS across
    /// engine stop/start cycles — it is only torn down on app quit.
    private var clickObservationTap: CFMachPort?
    private var clickObservationSource: CFRunLoopSource?
    private var clickTapInstalled = false

    /// Prevents double-processing a click from both the NSEvent monitor
    /// and the listenOnly CGEvent tap.
    private var lastClickProcessedTime: TimeInterval = 0

    private var interactionMonitors: [Any] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private var lastStepTime: TimeInterval = 0
    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)

    private let kCmd:   CGKeyCode = 0x37
    private let kShift: CGKeyCode = 0x38
    private let kTab:   CGKeyCode = 0x30
    private let kOpt:   CGKeyCode = 0x3A

    // MARK: - Observable state (for UI)

    private(set) var currentPhaseName: String = "Idle"
    private(set) var currentFingerCount: Int = 0
    private(set) var isReciprocalActive: Bool = false
    /// Last known centroid position (0–1 normalised), updated on every MT frame.
    /// Exposed so the trackpad margin preview can show a live dot.
    private(set) var currentCentroidX: Float = 0.5
    private(set) var currentCentroidY: Float = 0.5

    /// Callback invoked on main queue whenever the engine's observable state
    /// changes. Used by PreferencesStore to avoid 0.1s polling.
    var onStateChange: (() -> Void)?

    // (suppressContextClear was removed to prevent time-based reciprocal expiration)
    // MARK: - Tuning shorthand

    private var tuning: GestureTuning { Settings.shared.tuning }

    // MARK: - Lifecycle

    func start() {
        guard AXIsProcessTrusted() else { print("[Engine] Not trusted"); return }
        guard !isRunning else { return }

        // Full reset before starting
        resetAllGlobalState()
        phase = .idle
        reciprocalToken = nil
        sessionGeneration = 0
        lastClickProcessedTime = 0

        setupSuppressionTap()
        setupClickObservationTap()   // persistent — only created once
        startMultitouch()
        installInteractionMonitors()
        installWorkspaceObservers()
        startMTWatchdog()
        isRunning = true
        updateObservableState()
        AppLogger.debug("[Engine] Started")
    }

    func stop() {
        guard isRunning else { return }

        mtWatchdogTimer?.invalidate()
        mtWatchdogTimer = nil

        MultitouchBridge.shared.stop()
        teardownSuppressionTap()

        interactionMonitors.forEach { NSEvent.removeMonitor($0) }
        interactionMonitors.removeAll()

        let wnc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { wnc.removeObserver($0) }
        workspaceObservers.removeAll()

        // Full symmetric cleanup
        resetAllGlobalState()
        phase = .idle
        reciprocalToken = nil
        lastStepTime = 0
        suppressionEnabled = false
        isRunning = false
        updateObservableState()
        AppLogger.debug("[Engine] Stopped")
    }

    /// Zero all global MT state so no stale values survive stop/start.
    private func resetAllGlobalState() {
        glideActiveTouches = 0
        glideClickFingerCount = 0
        glidePeakFingerCount = 0
        glideLastMTTimestamp = 0
        glideLastDispatchedCount = 0
        glideLastDispatchedCx = 0
        glideLastDispatchedCy = 0
    }

    // MARK: - Multitouch

    private func startMultitouch() {
        MultitouchBridge.shared.start(callback: glideMTCallback)
    }

    /// Periodically checks that the MT callback is still firing.
    /// If no MT data arrives for 8 seconds while the engine is running,
    /// the trackpad device is presumed stale and the MT bridge is restarted.
    private func startMTWatchdog() {
        mtWatchdogTimer?.invalidate()
        // Seed the timestamp so we don't false-trigger immediately on start
        glideLastMTTimestamp = ProcessInfo.processInfo.systemUptime
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            let lastMT = glideLastMTTimestamp
            let now = ProcessInfo.processInfo.systemUptime
            // If no MT callback has fired in 8 seconds, the device is dead.
            // (During normal usage, MT fires at ~60 Hz whenever fingers touch.)
            // We use 8s to avoid false positives when the user simply isn't
            // touching the trackpad — the check only matters after wake.
            guard lastMT > 0, now - lastMT > 8.0 else { return }
            // Verify the user actually touched the trackpad recently by checking
            // if there are active touches right now. If glideActiveTouches > 0
            // but no callback arrived, the bridge is definitely stale.
            // However, after sleep MT usually goes silent completely (activeTouches = 0
            // and no callbacks), so we also restart if we detect a system wake
            // happened recently (the wake handler sets a flag).
            AppLogger.debug("[Engine] MT watchdog: no callback for \(now - lastMT)s — restarting MT bridge")
            MultitouchBridge.shared.stop()
            self.startMultitouch()
            glideLastMTTimestamp = now
        }
        timer.tolerance = 1.0   // Allow macOS to coalesce ±1s for battery savings
        mtWatchdogTimer = timer
    }

    // MARK: - Suppression tap

    /// Timer that periodically checks whether the CGEvent tap is still alive.
    /// macOS can silently invalidate taps after sleep/wake.
    private var tapHealthTimer: Timer?

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
                // macOS disables taps that take too long or after sleep.
                // Re-enable immediately when notified.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    AppLogger.debug("[Engine] Suppression tap was disabled by system — re-enabling")
                    if let tap = GestureEngine.shared.suppressionTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    // Return nil — the cgEvent is NULL for tap-disabled notifications
                    return nil
                }
                if type == .leftMouseDown {
                    let n = glideActiveTouches
                    if n >= 3 {
                        glideClickFingerCount = n
                    }
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
            startTapHealthTimer()
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
        tapHealthTimer?.invalidate()
        tapHealthTimer = nil
        if let tap = suppressionTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = suppressionSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        suppressionTap    = nil
        suppressionSource = nil
        suppressionEnabled = false
    }

    /// Periodically verifies the CGEvent taps are still valid.
    /// If macOS silently killed them (e.g. after sleep), tear down and recreate.
    private func startTapHealthTimer() {
        tapHealthTimer?.invalidate()
        let healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }

            // ── Suppression tap health ──
            if let tap = self.suppressionTap {
                if !CGEvent.tapIsEnabled(tap: tap) {
                    AppLogger.debug("[Engine] Tap health: suppression tap disabled, re-enabling")
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                if !CFMachPortIsValid(tap) {
                    AppLogger.debug("[Engine] Tap health: suppression mach port invalid, recreating")
                    self.teardownSuppressionTap()
                    self.setupSuppressionTap()
                }
            } else {
                AppLogger.debug("[Engine] Tap health: suppression tap nil, recreating")
                self.setupSuppressionTap()
            }

            // ── Click observation tap health ──
            if let tap = self.clickObservationTap {
                if !CGEvent.tapIsEnabled(tap: tap) {
                    AppLogger.debug("[Engine] Tap health: click tap disabled, re-enabling")
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                if !CFMachPortIsValid(tap) {
                    AppLogger.debug("[Engine] Tap health: click mach port invalid, recreating")
                    self.teardownClickObservationTap()
                    self.setupClickObservationTap()
                }
            } else {
                AppLogger.debug("[Engine] Tap health: click tap nil, recreating")
                self.setupClickObservationTap()
            }
        }
        healthTimer.tolerance = 2.0   // Allow macOS to coalesce ±2s for battery savings
        tapHealthTimer = healthTimer
    }

    // MARK: - Click observation tap (listenOnly — survives sleep/wake)

    /// Creates a `.listenOnly` CGEvent tap that observes leftMouseDown.
    /// Unlike the suppression tap, this tap:
    /// - Cannot be disabled by macOS timeout (it doesn't filter/block events)
    /// - Is NOT torn down during engine stop/start cycles
    /// - Provides a redundant click detection path independent of NSEvent monitors
    private func setupClickObservationTap() {
        guard !clickTapInstalled else { return }   // only create once

        let mask = UInt64(1 << CGEventType.leftMouseDown.rawValue)

        clickObservationTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,       // after other taps
            options: .listenOnly,             // passive — never disabled by macOS
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = GestureEngine.shared.clickObservationTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                guard type == .leftMouseDown else {
                    return nil
                }
                // Read finger count from all available sources
                let tapCount  = glideClickFingerCount
                let peakCount = glidePeakFingerCount
                let liveCount = glideActiveTouches
                let n = max(tapCount, peakCount, liveCount)
                if n >= 3 {
                    // Dispatch click processing to main queue
                    let fingerCount = Int(n)
                    DispatchQueue.main.async {
                        GestureEngine.shared.processClick(fingerCount: fingerCount)
                    }
                }
                return nil   // listenOnly — return value is ignored
            },
            userInfo: nil)

        if let tap = clickObservationTap {
            clickObservationSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), clickObservationSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            clickTapInstalled = true
            AppLogger.debug("[Engine] Click observation tap created (listenOnly)")
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

    // MARK: - Interaction monitors

    private func installInteractionMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.handleLeftClickFromMonitor()
        }) { interactionMonitors.append(m) }
        AppLogger.debug("[Engine] Installed \(interactionMonitors.count) interaction monitors")

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.handleExternalInteraction()
        }) { interactionMonitors.append(m) }
    }

    private func installWorkspaceObservers() {
        // App-switch token clearing has been intentionally removed to prevent time-based expiration
        // of reciprocal gestures like Mission Control.
    }

    /// Called from the NSEvent global monitor (backup path).
    private func handleLeftClickFromMonitor() {
        let tapCount  = Int(glideClickFingerCount)
        let peakCount = Int(glidePeakFingerCount)
        let liveCount = Int(glideActiveTouches)
        let n = max(tapCount, peakCount, liveCount)

        if n >= 3 {
            processClick(fingerCount: n)
        } else {
            // Normal 1-finger click: clear reciprocal state
            glideClickFingerCount = 0
            clearReciprocalToken()
        }
    }

    /// Core click handler — called from both the listenOnly CGEvent tap
    /// and the NSEvent global monitor. Uses a timestamp to dedup.
    func processClick(fingerCount n: Int) {
        if case .switchingApps = phase { return }

        // ── Edge margin guard ──
        if tuning.edgeMarginEnabled {
            let m = tuning.edgeMargin
            let inEdge = currentCentroidX < m.left
                      || currentCentroidX > (1.0 - m.right)
                      || currentCentroidY < m.bottom
                      || currentCentroidY > (1.0 - m.top)
            if inEdge {
                AppLogger.debug("[Engine] Click ignored — inside edge margin")
                return
            }
        }

        // Dedup: if this click was already processed within 100ms, skip.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastClickProcessedTime > 0.1 else { return }
        lastClickProcessedTime = now

        glideClickFingerCount = 0

        guard let rule = bestRule(fingers: n, direction: .click) else {
            return
        }

        AppLogger.debug("[Engine] Click — \(n) fingers → \(rule.action.rawValue)")
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
        guard glideActiveTouches < 2 else { return }
        if case .fired = phase { return }
        if case .switchingApps = phase { return }
        clearReciprocalToken()
    }

    // MARK: - Touch update (phase-driven dispatcher)

    func onTouches(_ frame: TouchFrameData) {
        // Note: glideActiveTouches is updated on the MT thread now
        // (before dispatch to main) so the CGEvent tap can see it immediately.
        setSuppressionActive(frame.count >= 3)

        let n = Int(frame.count)
        currentFingerCount = n

        // ── Fingers lifted: reset session ──
        if n < 2 {
            glideClickFingerCount = 0
            finishIfNeeded()
            updateObservableState()
            return
        }

        // Update centroid for UI live preview
        currentCentroidX = frame.cx
        currentCentroidY = frame.cy

        // ── Click-in-progress guard ──
        if glideClickFingerCount >= 3 {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime

        switch phase {

        // ──────────────────────────────────────────────
        // IDLE: fingers appeared — start a candidate session
        // ──────────────────────────────────────────────
        case .idle:
            guard hasAnySwipeRule(fingers: n) else { return }
            // ── Edge margin guard ──
            // Ignore gestures that begin inside the configured dead zones near
            // the trackpad bezel. cx/cy are normalised (0.0–1.0); cy=0 is bottom.
            if tuning.edgeMarginEnabled {
                let m = tuning.edgeMargin
                let inEdge = frame.cx < m.left
                          || frame.cx > (1.0 - m.right)
                          || frame.cy < m.bottom
                          || frame.cy > (1.0 - m.top)
                if inEdge { return }  // stay idle — don't start a candidate
            }
            sessionGeneration &+= 1
            let data = CandidateData(
                startX: frame.cx, startY: frame.cy,
                fingers: n, startTime: now,
                initialSpread: frame.spread,
                frameCount: 1,
                cumulativeSpreadDelta: 0,
                prevSpread: frame.spread,
                minCoherence: frame.coherence,
                fingerCountStable: true,
                prevCx: frame.cx,
                prevCy: frame.cy,
                velocitySamples: [],
                gestureKind: .unknown,
                classificationFrameDelay: 0
            )
            phase = .candidate(data)

        // ──────────────────────────────────────────────
        // CANDIDATE: collecting evidence before locking
        // ──────────────────────────────────────────────
        case .candidate(var data):
            // Finger count increased (more fingers landing) → restart candidate
            // with higher count. Only common for 4/5 finger gestures where
            // fingers don't all land at the same instant.
            if n > data.fingers {
                guard hasAnySwipeRule(fingers: n) else {
                    phase = .ignored
                    updateObservableState()
                    return
                }
                data = CandidateData(
                    startX: frame.cx, startY: frame.cy,
                    fingers: n, startTime: now,
                    initialSpread: frame.spread,
                    frameCount: 1,
                    cumulativeSpreadDelta: 0,
                    prevSpread: frame.spread,
                    minCoherence: frame.coherence,
                    fingerCountStable: true,
                    prevCx: frame.cx,
                    prevCy: frame.cy,
                    velocitySamples: [],
                    gestureKind: .unknown,
                    classificationFrameDelay: 0
                )
                phase = .candidate(data)
                AppLogger.debug("[Engine] Candidate restarted — finger count increased to \(n)")
                return
            }
            // Finger count decreased → veto
            if n < data.fingers {
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — finger count decreased (\(data.fingers) → \(n))")
                updateObservableState()
                return
            }

            data.frameCount += 1

            // ── Velocity sampling (InputActions-inspired) ──
            // Compute per-frame centroid displacement and accumulate
            let frameDx = frame.cx - data.prevCx
            let frameDy = frame.cy - data.prevCy
            let frameDist = (frameDx * frameDx + frameDy * frameDy).squareRoot()
            // Only sample up to speedSampleCount frames for velocity
            if data.velocitySamples.count < tuning.speedSampleCount {
                data.velocitySamples.append(frameDist)
            }
            data.prevCx = frame.cx
            data.prevCy = frame.cy

            // Accumulate spread evidence
            let frameDelta = abs(frame.spread - data.prevSpread)
            data.cumulativeSpreadDelta += frameDelta
            data.prevSpread = frame.spread

            // Track worst coherence
            if frame.coherence < data.minCoherence {
                data.minCoherence = frame.coherence
            }

            // ── Immediate veto: very large per-frame spread change ──
            // This catches aggressive pinch/spread early regardless of frame count
            if frameDelta > tuning.pinchFrameSpreadThreshold * 1.5 {
                data.gestureKind = .pinch
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — large frame spread delta \(frameDelta), locked as pinch")
                updateObservableState()
                return
            }

            // ── Compute centroid movement vs spread (used for classification) ──
            let centroidMovement = (
                (frame.cx - data.startX) * (frame.cx - data.startX) +
                (frame.cy - data.startY) * (frame.cy - data.startY)
            ).squareRoot()
            let totalSpreadChange = abs(frame.spread - data.initialSpread)

            // ── Early pinch dominance override ──
            // Even before full classification, if spread change is significantly
            // larger than centroid movement, immediately lock as pinch.
            // This catches pinch gestures that start before the classification
            // delay window completes. Uses 0.8x ratio (generous toward swipes).
            if totalSpreadChange > 0.002 && totalSpreadChange > centroidMovement * 0.8 && data.frameCount >= 2 {
                data.gestureKind = .pinch
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — early pinch dominance: spread \(totalSpreadChange) >> centroid \(centroidMovement)")
                updateObservableState()
                return
            }

            // ── Fix 4: Delay classification — let the gesture reveal itself ──
            // Minimum 3 frames before any decision. Early frames of pinch
            // often look like swipes (high coherence, low spread).
            let minFrames = max(Int(tuning.candidateFrames), 3)
            guard data.frameCount >= minFrames else {
                phase = .candidate(data)
                return
            }

            // ── Gesture classification (after 2-3 frame delay) ──
            // Once gestureKind is decided, it NEVER switches.
            if data.gestureKind == .unknown {
                data.classificationFrameDelay += 1
                if data.classificationFrameDelay >= 2 {
                    // Classify: if spread change dominates centroid movement → pinch
                    if totalSpreadChange > centroidMovement * 0.8 {
                        data.gestureKind = .pinch
                    } else {
                        data.gestureKind = .swipe
                    }
                    AppLogger.debug("[Engine] Gesture classified as \(data.gestureKind) — spread \(totalSpreadChange) vs centroid \(centroidMovement)")
                }
            }

            // ── If classified as pinch → permanently block swipe ──
            if data.gestureKind == .pinch {
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — classified as pinch, swipe permanently blocked")
                updateObservableState()
                return
            }

            // ── Fix 3: compare centroid movement vs spread ──
            // A swipe has high centroid movement and minimal spread change.
            // A pinch/spread has significant spread with small/incidental centroid drift.
            if totalSpreadChange > 0.002 && totalSpreadChange > centroidMovement * 0.5 {
                data.gestureKind = .pinch
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — pinch detected: spread \(totalSpreadChange) dominates centroid \(centroidMovement)")
                updateObservableState()
                return
            }

            // ── Fix 1 & 2: Cumulative spread check (pinch lock, not just veto) ──
            if data.cumulativeSpreadDelta > tuning.pinchSpreadThreshold {
                data.gestureKind = .pinch
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — cumulative spread \(data.cumulativeSpreadDelta) > \(tuning.pinchSpreadThreshold)")
                updateObservableState()
                return
            }

            // ── Fix 5: Coherence as positive signal ──
            // Very low coherence → fingers diverging → pinch territory
            if data.minCoherence < tuning.swipeCoherenceThreshold {
                data.gestureKind = .pinch
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — coherence \(data.minCoherence) < \(tuning.swipeCoherenceThreshold)")
                updateObservableState()
                return
            }

            // ── Fix 6: Hard swipe condition — only lock when evidence is clear ──
            // Require: centroid movement exceeds spread AND spread is small AND coherence OK
            // AND gestureKind is NOT pinch (locked classification)
            let spreadIsSmall = data.cumulativeSpreadDelta < tuning.pinchSpreadThreshold
            let centroidDominates = centroidMovement > totalSpreadChange
            let coherenceOK = data.minCoherence >= tuning.swipeCoherenceThreshold
            let notPinch = data.gestureKind != .pinch

            if spreadIsSmall && centroidDominates && coherenceOK && notPinch {
                // All checks passed — lock as swipe
                data.gestureKind = .swipe  // lock classification
                let swipeData = SwipeTrackData(
                    startX: data.startX, startY: data.startY,
                    lastX: frame.cx, lastY: frame.cy,
                    fingers: data.fingers, startTime: data.startTime,
                    velocitySamples: data.velocitySamples,
                    recentDeltas: [],
                    initialSpread: data.initialSpread,
                    prevSpread: frame.spread,
                    cumulativeSpreadDelta: data.cumulativeSpreadDelta
                )
                phase = .lockedSwipe(swipeData)
                AppLogger.debug("[Engine] Session locked as swipe — \(n) fingers, coherence \(data.minCoherence), centroid \(centroidMovement) vs spread \(totalSpreadChange)")
                updateObservableState()
                // Fall through to process this frame as a swipe
                processSwipeFrame(frame, data: swipeData, now: now)
            } else if data.frameCount >= minFrames + 5 {
                // Safety timeout: too many frames without clear classification → ignore
                phase = .ignored
                AppLogger.debug("[Engine] Session ignored — classification timeout at \(data.frameCount) frames")
                updateObservableState()
            } else {
                // Not enough evidence yet — continue collecting
                phase = .candidate(data)
            }

        // ──────────────────────────────────────────────
        // LOCKED SWIPE: tracking centroid for threshold
        // ──────────────────────────────────────────────
        case .lockedSwipe(let data):
            guard n == data.fingers else { finishIfNeeded(); return }
            processSwipeFrame(frame, data: data, now: now)

        // ──────────────────────────────────────────────
        // APP SWITCHER: continuous trackpad-driven Cmd+Tab
        // ──────────────────────────────────────────────
        case .switchingApps(var data):
            guard n == 3 else { commitAppSwitcher(data: data); return }
            let delta = frame.cx - data.refX
            if abs(delta) > tuning.appSwitcherStepThreshold,
               now - lastStepTime >= tuning.appSwitcherDebounce {
                if delta > 0, data.index < data.apps.count - 1 {
                    Haptic.switcherStep()
                    sendCmdTab()
                    lastStepTime = now
                    data.refX = frame.cx
                    data.index = min(data.index + 1, data.apps.count - 1)
                    phase = .switchingApps(data)
                } else if delta < 0, data.index > 0 {
                    Haptic.switcherStep()
                    sendCmdShiftTab()
                    lastStepTime = now
                    data.refX = frame.cx
                    data.index = max(data.index - 1, 0)
                    phase = .switchingApps(data)
                }
            }

        // ──────────────────────────────────────────────
        // IGNORED / FIRED: do nothing until lift
        // ──────────────────────────────────────────────
        case .ignored, .fired:
            break
        }
    }

    // MARK: - Swipe frame processing (InputActions-inspired)
    //
    // Key changes from original:
    // 1. Magnitude-based threshold: hypot(dx, dy) instead of checking abs(dx) then abs(dy)
    //    Fixes: diagonal swipes no longer biased toward horizontal
    // 2. Sliding delta window: direction from recent per-frame deltas, not total displacement
    //    Matches InputActions' m_swipeDeltas + averageAngle approach
    // 3. Angle-based direction: atan2 of accumulated delta vector → angle → cardinal direction
    //    Matches InputActions' SwipeTriggerCore angle range matching

    private func processSwipeFrame(_ frame: TouchFrameData, data: SwipeTrackData, now: TimeInterval) {
        var updated = data

        // ── Per-frame delta (InputActions: delta.unaccelerated()) ──
        let frameDx = frame.cx - data.lastX
        let frameDy = frame.cy - data.lastY
        let frameDist = (frameDx * frameDx + frameDy * frameDy).squareRoot()
        updated.lastX = frame.cx
        updated.lastY = frame.cy

        // ── Continue tracking spread during locked swipe phase ──
        // If spread suddenly grows, a pinch started after swipe lock — abort.
        let swipeFrameSpreadDelta = abs(frame.spread - updated.prevSpread)
        updated.cumulativeSpreadDelta += swipeFrameSpreadDelta
        updated.prevSpread = frame.spread

        let swipeSpreadChange = abs(frame.spread - updated.initialSpread)
        let swipeCentroidMovement = (
            (frame.cx - updated.startX) * (frame.cx - updated.startX) +
            (frame.cy - updated.startY) * (frame.cy - updated.startY)
        ).squareRoot()

        // If spread suddenly dominates during the swipe → pinch intruded, abort
        if swipeSpreadChange > 0.003 && swipeSpreadChange > swipeCentroidMovement * 0.8 {
            phase = .ignored
            AppLogger.debug("[Engine] Swipe aborted — spread grew during tracking: spread \(swipeSpreadChange) vs centroid \(swipeCentroidMovement)")
            updateObservableState()
            return
        }

        // Velocity sampling (continue from candidate phase)
        if updated.velocitySamples.count < tuning.speedSampleCount {
            updated.velocitySamples.append(frameDist)
        }

        // ── Sliding delta window (InputActions: m_swipeDeltas) ──
        // Prepend newest delta (InputActions inserts at begin)
        updated.recentDeltas.insert((dx: frameDx, dy: frameDy), at: 0)

        // ── Compute accumulated vector from window (InputActions: totalDelta) ──
        // Walk from most recent, accumulating until magnitude >= threshold.
        // Then trim older deltas beyond that point (InputActions: erase(++it, end)).
        var totalDx: Float = 0
        var totalDy: Float = 0
        var thresholdIndex: Int? = nil
        for (i, d) in updated.recentDeltas.enumerated() {
            totalDx += d.dx
            totalDy += d.dy
            let mag = (totalDx * totalDx + totalDy * totalDy).squareRoot()
            if mag >= tuning.initialThreshold {
                thresholdIndex = i
                break
            }
        }

        guard let cutoff = thresholdIndex else {
            // Motion threshold not yet reached — keep accumulating
            phase = .lockedSwipe(updated)
            return
        }

        // Trim old deltas beyond the threshold window (InputActions: m_swipeDeltas.erase)
        if cutoff + 1 < updated.recentDeltas.count {
            updated.recentDeltas.removeSubrange((cutoff + 1)...)
        }

        // ── Angle-based direction (InputActions: atan2deg360 of totalDelta) ──
        // Apple MT normalised coords: Y increases upward, so dy > 0 = up.
        // This matches atan2 convention directly (up = 90°).
        let angleDeg = atan2(totalDy, totalDx) * (180.0 / .pi)   // -180..+180
        let angle360 = angleDeg < 0 ? angleDeg + 360 : angleDeg  // 0..360

        // Match angle to cardinal direction using tolerance wedges
        // (InputActions: SwipeTriggerCore::canUpdate with angleRange matching)
        guard let direction = directionFromAngle(angle360) else {
            // In dead zone between cardinal wedges — keep accumulating
            phase = .lockedSwipe(updated)
            return
        }

        // ── Reciprocal check ──
        if consumeReciprocalToken(fingers: data.fingers, direction: direction) {
            phase = .fired
            updateObservableState()
            return
        }

        // ── Speed classification (velocity-based) ──
        let speed = classifySpeed(velocitySamples: updated.velocitySamples)

        // ── Pre-swipe safety gate ──
        // Before triggering any swipe, verify that spread hasn't grown
        // significantly and that coherence is good. This is the final
        // guard against pinch-induced false swipes.
        let gateSpreadChange = abs(frame.spread - updated.initialSpread)
        let gateSpreadSmall = gateSpreadChange < tuning.pinchSpreadThreshold * 0.8
        let gateCoherenceOK = frame.coherence > 0.8

        if !gateSpreadSmall || !gateCoherenceOK {
            // Safety gate failed — do NOT trigger swipe
            phase = .ignored
            AppLogger.debug("[Engine] Swipe blocked by safety gate — spread \(gateSpreadChange), coherence \(frame.coherence)")
            updateObservableState()
            return
        }

        // ── Match and fire (InputActions: updateTriggers) ──
        if let rule = bestRule(fingers: data.fingers, direction: direction, speed: speed) {
            AppLogger.debug("[Engine] Swipe \(direction.rawValue) — \(data.fingers) fingers, \(speed.rawValue) (avgVel=\(averageVelocity(updated.velocitySamples)), angle=\(String(format: "%.1f", angle360))°) → \(rule.action.rawValue)")
            if rule.action == .appSwitcherNext || rule.action == .appSwitcherPrev {
                if !beginAppSwitcher(for: rule.action, refX: frame.cx) {
                    phase = .fired
                }
            } else {
                executeSwipeRule(rule, fingers: data.fingers, direction: direction)
                phase = .fired
            }
        } else {
            phase = .fired
        }
        updateObservableState()
    }

    // MARK: - Angle-to-direction mapping (InputActions: SwipeTriggerCore::angleRange)
    //
    // Maps a 0–360° angle to a cardinal direction using configurable tolerance.
    // Each direction has a wedge of ±tolerance degrees centered on its axis:
    //   Right: 0° ± tol    Up: 90° ± tol    Left: 180° ± tol    Down: 270° ± tol
    // If tolerance < 45°, gaps between wedges form diagonal dead zones where
    // no direction is returned (gesture keeps accumulating until it becomes clearer).

    private func directionFromAngle(_ angle: Float) -> GestureDirection? {
        let tol = tuning.swipeAngleTolerance

        // Right: centered at 0° (wraps around 360°)
        if angle >= (360 - tol) || angle < tol {
            return .swipeRight
        }
        // Up: centered at 90°
        if angle >= (90 - tol) && angle < (90 + tol) {
            return .swipeUp
        }
        // Left: centered at 180°
        if angle >= (180 - tol) && angle < (180 + tol) {
            return .swipeLeft
        }
        // Down: centered at 270°
        if angle >= (270 - tol) && angle < (270 + tol) {
            return .swipeDown
        }
        // In a dead zone (only when tolerance < 45°)
        return nil
    }

    // MARK: - Finish / reset

    private func finishIfNeeded() {
        if case .switchingApps(let data) = phase {
            commitAppSwitcher(data: data)
        }
        phase        = .idle
        lastStepTime = 0
    }

    private func commitAppSwitcher(data: SwitcherData) {
        _ = data
        Haptic.switcherCommit()
        selectInAppSwitcher()
        AppLogger.debug("[Engine] App-switcher committed")
    }

    private func selectInAppSwitcher() {
        sendKeyEvent(kOpt, down: true,  flags: [.maskAlternate])
        sendKeyEvent(kCmd, down: false, flags: [.maskCommand, .maskAlternate])
        sendKeyEvent(kOpt, down: false, flags: [])
    }

    private func beginAppSwitcher(for action: GestureAction, refX: Float) -> Bool {
        var apps = runningApps()
        guard apps.count > 1 else { return false }
        if let front = NSWorkspace.shared.frontmostApplication,
           let idx = apps.firstIndex(where: { $0.processIdentifier == front.processIdentifier }) {
            apps.remove(at: idx); apps.insert(front, at: 0)
        }
        clearReciprocalToken()
        sendKeyEvent(kCmd, down: true, flags: .maskCommand)
        Haptic.switcherOpen()

        let index: Int
        if action == .appSwitcherNext { sendCmdTab(); index = 1 }
        else { sendCmdShiftTab(); index = apps.count - 1 }

        lastStepTime = ProcessInfo.processInfo.systemUptime
        phase = .switchingApps(SwitcherData(refX: refX, index: index, apps: apps))
        updateObservableState()
        return true
    }

    // MARK: - Rule matching

    private func bestRule(fingers: Int, direction: GestureDirection, speed: GestureSpeed = .normal) -> GestureRule? {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let all = Settings.shared.rules.filter { $0.fingers == fingers && $0.direction == direction }
        let specific = all.filter { $0.appFilter != nil && $0.appFilter == bid }
        let generic  = all.filter { $0.appFilter == nil }
        return bestRuleMatch(in: specific, speed: speed) ?? bestRuleMatch(in: generic, speed: speed)
    }

    private func hasAnySwipeRule(fingers: Int) -> Bool {
        let dirs: [GestureDirection] = [.swipeLeft, .swipeRight, .swipeUp, .swipeDown]
        return Settings.shared.rules.contains { $0.fingers == fingers && dirs.contains($0.direction) }
    }

    private func bestRuleMatch(in rules: [GestureRule], speed: GestureSpeed) -> GestureRule? {
        if let exact = rules.first(where: { normalizedSpeed($0.speed) == speed }) { return exact }
        guard speed != .normal else { return nil }
        return rules.first(where: { normalizedSpeed($0.speed) == .normal })
    }

    private func normalizedSpeed(_ speed: GestureSpeed) -> GestureSpeed {
        speed == .any ? .normal : speed
    }

    // MARK: - Speed classification (velocity-based, InputActions-inspired)

    /// Compute average velocity from collected per-frame centroid delta samples.
    private func averageVelocity(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Float(samples.count)
    }

    /// Classify speed based on average centroid displacement per frame.
    /// Faster finger movement → higher average delta → Fast.
    /// This directly measures how fast the finger is moving, rather than
    /// how long the gesture took (the old time-based approach).
    /// Inspired by InputActions' MotionTriggerHandler::determineSpeed().
    private func classifySpeed(velocitySamples: [Float]) -> GestureSpeed {
        let avgVel = averageVelocity(velocitySamples)
        if avgVel >= tuning.fastVelocityThreshold  { return .fast }
        if avgVel <= tuning.slowVelocityThreshold   { return .slow }
        return .normal
    }

    // MARK: - Reciprocal token system

    private func executeSwipeRule(_ rule: GestureRule, fingers: Int, direction: GestureDirection) {
        Haptic.forAction(rule.action)

        ActionExecutor.shared.execute(rule.action, appPath: rule.appPath)

        // Store reciprocal token only if the rule has reciprocal enabled
        // and the action has a natural inverse
        if rule.reciprocalEnabled {
            reciprocalToken = createReciprocalToken(for: rule.action, fingers: fingers, direction: direction)
        } else {
            clearReciprocalToken()
        }
        updateObservableState()
    }

    /// Try to consume the reciprocal token. Returns true if consumed.
    private func consumeReciprocalToken(fingers: Int, direction: GestureDirection) -> Bool {
        guard let token = reciprocalToken else { return false }
        // Must match: same finger count, exact opposite direction
        guard token.fingers == fingers, token.direction == direction else { return false }
        // For restore: check there are actually windows to restore
        if token.inverseAction == .restoreMinimizedApps,
           !ActionExecutor.shared.hasRestorableMinimizedApps {
            clearReciprocalToken()
            return false
        }
        AppLogger.debug("[Engine] Reciprocal \(direction.rawValue) — \(fingers) fingers → \(token.inverseAction.rawValue)")
        let action = token.inverseAction
        clearReciprocalToken()
        Haptic.reciprocal()
        ActionExecutor.shared.execute(action)
        return true
    }

    /// Create a reciprocal token using the action's built-in inverse mapping.
    /// Returns nil if the action has no natural inverse.
    private func createReciprocalToken(for action: GestureAction, fingers: Int, direction: GestureDirection) -> ReciprocalToken? {
        guard let rev = opposite(direction),
              let inverse = action.inverseAction else { return nil }

        let now = ProcessInfo.processInfo.systemUptime
        let contextApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return ReciprocalToken(inverseAction: inverse, fingers: fingers,
                               direction: rev, contextApp: contextApp,
                               sessionGeneration: sessionGeneration, createdAt: now)
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

    // MARK: - Observable state update

    private func updateObservableState() {
        switch phase {
        case .idle:                currentPhaseName = "Idle"
        case .candidate:           currentPhaseName = "Candidate"
        case .lockedSwipe:         currentPhaseName = "Locked (Swipe)"
        case .ignored:             currentPhaseName = "Ignored"
        case .fired:               currentPhaseName = "Fired"
        case .switchingApps:       currentPhaseName = "App Switcher"
        }
        isReciprocalActive = reciprocalToken != nil
        onStateChange?()
    }

    // MARK: - App switcher key events

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

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
}

// ─────────────────────────────────────────────
// MARK: - Global MT callback
// ─────────────────────────────────────────────

/// Written by the MT callback (MT thread) and the CGEvent tap callback (HID thread).
/// Read by the engine on main. Effectively atomic for Int32 on arm64/x86_64.
var glideActiveTouches: Int32 = 0

/// Set synchronously in the CGEvent tap callback the moment a leftMouseDown
/// fires with 3+ fingers. Consumed on main in handleLeftClick().
var glideClickFingerCount: Int32 = 0

/// Peak finger count from the MT callback. Set when count >= 3,
/// reset to 0 after a 300ms delay. This survives the timing race where
/// the MT "fingers lifted" callback is dispatched to main before the
/// NSEvent leftMouseDown monitor fires.
var glidePeakFingerCount: Int32 = 0

/// Last time the MT callback fired (ProcessInfo.systemUptime).
/// Used by the engine's watchdog to detect stale MT devices.
var glideLastMTTimestamp: TimeInterval = 0

/// Work item for resetting the peak finger count after a delay.
private var peakResetWorkItem: DispatchWorkItem?

/// Frame deduplication state. When 1–2 fingers rest on the trackpad without
/// meaningful movement, we skip the main-queue dispatch to avoid ~60
/// unnecessary wake-ups/sec. For count >= 3, every frame is dispatched
/// because the engine's state machine needs continuous evidence.
private var glideLastDispatchedCount: Int32 = 0
private var glideLastDispatchedCx: Float = 0
private var glideLastDispatchedCy: Float = 0

/// True if the current multitouch sequence has touched the margin at any point.
/// Blocks all gestures until all fingers are lifted.
var glideLifecycleBlocked: Bool = false

/// The MT callback. Computes per-frame evidence (centroid, spread, coherence)
/// and dispatches to the engine on main via TouchFrameData.
let glideMTCallback: MTContactCallback = { _, data, count, _, _ in
    // Record that the MT callback is alive (for the watchdog)
    glideLastMTTimestamp = ProcessInfo.processInfo.systemUptime

    var validTouches: [MTTouch] = []
    if let data, count > 0 {
        let n = Int(count)
        let rawTouches = data.assumingMemoryBound(to: MTTouch.self)
        let tuning = Settings.shared.tuning
        
        var anyInMargin = false
        if tuning.edgeMarginEnabled {
            let m = tuning.edgeMargin
            for i in 0..<n {
                let t = rawTouches[i]
                let x = t.normalizedPosition.x
                let y = t.normalizedPosition.y
                if x < m.left || x > (1.0 - m.right) || y < m.bottom || y > (1.0 - m.top) {
                    anyInMargin = true
                    break
                }
            }
        }
        
        if anyInMargin {
            glideLifecycleBlocked = true
        }
        
        if !glideLifecycleBlocked {
            for i in 0..<n {
                validTouches.append(rawTouches[i])
            }
        }
    } else {
        // All fingers lifted, reset the lifecycle block
        glideLifecycleBlocked = false
    }

    let validCount = Int32(validTouches.count)

    guard validCount > 0 else {
        if glideActiveTouches > 0 {
            // Update finger count immediately on MT thread so CGEvent tap sees it
            glideActiveTouches = 0
            glideLastDispatchedCount = 0
            glideLastDispatchedCx = 0
            glideLastDispatchedCy = 0
            DispatchQueue.main.async {
                glideClickFingerCount = 0
                // Schedule peak count reset after a short delay.
                // This keeps the peak count alive long enough for
                // handleLeftClick to read it even if the finger-lift
                // callback dispatches to main before the click handler.
                peakResetWorkItem?.cancel()
                let work = DispatchWorkItem { glidePeakFingerCount = 0 }
                peakResetWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)

                GestureEngine.shared.onTouches(TouchFrameData(
                    count: 0, cx: 0, cy: 0, spread: 0, coherence: 1
                ))
            }
        }
        return 0
    }

    let n = Int(validCount)

    // Update finger count immediately on MT thread (before dispatch to main)
    // so the CGEvent tap callback can see current count right away.
    // Int32 stores are effectively atomic on arm64/x86_64.
    glideActiveTouches = validCount

    // Track peak finger count for click detection
    if validCount >= 3 {
        glidePeakFingerCount = validCount
        // Cancel any pending reset
        DispatchQueue.main.async { peakResetWorkItem?.cancel() }
    }

    // ── Compute centroid ──
    var sumX: Float = 0, sumY: Float = 0
    for i in 0..<n {
        sumX += validTouches[i].normalizedPosition.x
        sumY += validTouches[i].normalizedPosition.y
    }
    let cx = sumX / Float(n)
    let cy = sumY / Float(n)

    // ── Frame deduplication for low-finger counts ──
    // For count < 3, the engine does minimal work (early returns or no-ops).
    // Skip the main-queue dispatch when nothing meaningful changed.
    // For count >= 3, always dispatch — the engine needs every frame for
    // candidate evidence, swipe tracking, and app-switcher.
    if validCount < 3 {
        let countChanged = validCount != glideLastDispatchedCount
        let centroidMoved = abs(cx - glideLastDispatchedCx) > 0.001
                         || abs(cy - glideLastDispatchedCy) > 0.001
        if !countChanged && !centroidMoved {
            return 0
        }
    }
    glideLastDispatchedCount = validCount
    glideLastDispatchedCx = cx
    glideLastDispatchedCy = cy

    // ── Compute spread (average finger-to-centroid distance) ──
    var spread: Float = 0
    if n >= 3 {
        var spreadSum: Float = 0
        for i in 0..<n {
            let dx = validTouches[i].normalizedPosition.x - cx
            let dy = validTouches[i].normalizedPosition.y - cy
            spreadSum += (dx * dx + dy * dy).squareRoot()
        }
        spread = spreadSum / Float(n)
    }

    // ── Compute directional coherence ──
    // Average of per-finger unit velocity vectors.
    // If all fingers move the same direction → magnitude ≈ 1.0 (swipe).
    // If fingers move in opposite directions → magnitude ≈ 0.0 (pinch).
    var coherence: Float = 1.0
    if n >= 3 {
        var avgDirX: Float = 0
        var avgDirY: Float = 0
        var movingFingers: Int = 0
        for i in 0..<n {
            let vx = validTouches[i].velocity.x
            let vy = validTouches[i].velocity.y
            let mag = (vx * vx + vy * vy).squareRoot()
            if mag > 0.01 {  // only count fingers that are actually moving
                avgDirX += vx / mag
                avgDirY += vy / mag
                movingFingers += 1
            }
        }
        if movingFingers > 0 {
            avgDirX /= Float(movingFingers)
            avgDirY /= Float(movingFingers)
            coherence = (avgDirX * avgDirX + avgDirY * avgDirY).squareRoot()
        }
        // else: no fingers moving yet → default coherence 1.0 (don't veto idle fingers)
    }

    let frameData = TouchFrameData(count: validCount, cx: cx, cy: cy,
                                   spread: spread, coherence: coherence)

    DispatchQueue.main.async {
        GestureEngine.shared.onTouches(frameData)
    }
    return 0
}
