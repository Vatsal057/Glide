import Cocoa
import CoreGraphics
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: - Haptic engine
// ─────────────────────────────────────────────

private enum Haptic {
    static func forAction(_ action: GestureAction) {
        guard GestureEngine.shared.settings?.hapticFeedback ?? true else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch action {
        case .quitAppUnderCursor, .forceQuitAppUnderCursor, .quitFrontmostApp, .closeWindow, .sleep, .lockScreen, .openApp:
            pattern = .generic
        case .minimizeWindow, .minimizeAllApps, .restoreMinimizedApps,
             .maximizeWindow, .restoreWindow,
             .enterFullscreen, .exitFullscreen, .toggleFullscreen,
             .snapLeft, .snapRight, .snapTopLeft, .snapTopRight,
             .snapBottomLeft, .snapBottomRight, .centerWindow, .moveToNextDisplay:
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
        guard GestureEngine.shared.settings?.hapticFeedback ?? true else { return }
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
// MARK: - GestureTuning
// ─────────────────────────────────────────────

private struct EdgeMargin {
    var left: Float
    var right: Float
    var top: Float
    var bottom: Float
}

private struct GestureTuning {
    var initialThreshold:           Float
    var appSwitcherStepThreshold:   Float
    var appSwitcherDebounce:        TimeInterval
    var fastVelocityThreshold:      Float
    var slowVelocityThreshold:      Float
    var speedSampleCount:           Int
    var candidateFrames:            Int
    var pinchSpreadThreshold:       Float
    var pinchFrameSpreadThreshold:  Float
    var swipeCoherenceThreshold:    Float
    var swipeAngleTolerance:        Float
    var edgeMarginEnabled:          Bool
    var edgeMargin:                 EdgeMargin
}

// ─────────────────────────────────────────────
// MARK: - Global MT state
// ─────────────────────────────────────────────

private var deviceFingerCounts: [UnsafeMutableRawPointer: Int] = [:]
private var sessionPeakActiveTouches: Int = 0
private let countsLock = NSLock()

fileprivate func updateDeviceFingerCount(device: UnsafeMutableRawPointer, count: Int) {
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

fileprivate func getThreeFingerCount() -> Int {
    countsLock.lock()
    defer { countsLock.unlock() }
    return deviceFingerCounts.values.max() ?? 0
}

fileprivate func getSessionPeakActiveTouches() -> Int {
    countsLock.lock()
    defer { countsLock.unlock() }
    return sessionPeakActiveTouches
}

fileprivate var glideActiveTouches: Int32 = 0
fileprivate var glideClickFingerCount: Int32 = 0
fileprivate var glidePeakFingerCount: Int32 = 0
fileprivate var glideLastMTTimestamp: TimeInterval = 0
fileprivate var glideLastDispatchedCount: Int32 = 0
private var glideFingerFirstSeen: [Int32: TimeInterval] = [:]
fileprivate var glideOldestFingerAge: Double = 0.0
fileprivate var glideNewestFingerAge: Double = 0.0

// ─────────────────────────────────────────────
// MARK: - Global MT callback
// ─────────────────────────────────────────────

let glideMTCallback: MTContactCallback = { device, data, count, _, _ in
    glideLastMTTimestamp = ProcessInfo.processInfo.systemUptime

    var validTouches: [MTTouch] = []
    if let data, count > 0 {
        let n = Int(count)
        let raw = data.assumingMemoryBound(to: MTTouch.self)
        let tuning = GestureEngine.shared.tuning

        if tuning.edgeMarginEnabled {
            let m = tuning.edgeMargin
            for i in 0..<n {
                let t = raw[i]
                let x = t.normalizedX; let y = t.normalizedY
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

    let nowTs = glideLastMTTimestamp

    for touch in validTouches {
        if glideFingerFirstSeen[touch.identifier] == nil {
            glideFingerFirstSeen[touch.identifier] = nowTs
        }
    }
    if glideFingerFirstSeen.count != validTouches.count {
        let activeIDs = Set(validTouches.map { $0.identifier })
        glideFingerFirstSeen = glideFingerFirstSeen.filter { activeIDs.contains($0.key) }
    }
    if let oldest = glideFingerFirstSeen.values.min(),
       let newest = glideFingerFirstSeen.values.max() {
        glideOldestFingerAge = nowTs - oldest
        glideNewestFingerAge = nowTs - newest
    }

    let prevActiveTouches = glideActiveTouches
    glideActiveTouches = validCount

    if validCount >= 3 {
        glidePeakFingerCount = validCount
        if prevActiveTouches < 3 {
            DispatchQueue.main.async { GestureEngine.shared.peakResetWorkItem?.cancel() }
        }
    }

    if validCount < 3 && validCount == glideLastDispatchedCount { return 0 }
    glideLastDispatchedCount = validCount

    var sumX: Float = 0, sumY: Float = 0
    for i in 0..<n { sumX += validTouches[i].normalizedX; sumY += validTouches[i].normalizedY }
    let cx = sumX / Float(n)
    let cy = sumY / Float(n)

    var spread: Float = 0
    if n >= 3 {
        var sVal: Float = 0
        for i in 0..<n {
            let dx = validTouches[i].normalizedX - cx
            let dy = validTouches[i].normalizedY - cy
            sVal += (dx * dx + dy * dy).squareRoot()
        }
        spread = sVal / Float(n)
    }

    var coherence: Float = 1.0
    if n >= 3 {
        var avgDirX: Float = 0, avgDirY: Float = 0, movingFingers = 0
        for i in 0..<n {
            let vx = validTouches[i].velocityX; let vy = validTouches[i].velocityY
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

// ─────────────────────────────────────────────
// MARK: - GestureEngine
// ─────────────────────────────────────────────

final class GestureEngine {

    static let shared = GestureEngine()
    private init() {}

    // Injected by the app
    var store:    GestureStore?
    var settings: AppSettings?

    var isEnabled: Bool = true {
        didSet {
            if let tap = suppressionTap {
                CGEvent.tapEnable(tap: tap, enable: isEnabled)
            }
        }
    }

    // MARK: - Session state machine

    private struct CandidateData {
        let startX: Float; let startY: Float
        let fingers: Int; let startTime: TimeInterval
        let initialSpread: Float
        let modifiersAtStart: ModifierKey
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
        let modifiersAtStart: ModifierKey
        var velocitySamples: [Float]
        var recentDeltas: [(dx: Float, dy: Float)]
        let initialSpread: Float
        var prevSpread: Float
        var cumulativeSpreadDelta: Float
    }

    private struct SwitcherData {
        var refX: Float; var index: Int
        let apps: [NSRunningApplication]
        let finderIndex: Int?
        let effectiveMin: Int
        let effectiveMax: Int
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
        let direction: GestureType
    }

    // MARK: - State

    private var phase: GesturePhase = .idle
    private var reciprocalToken: ReciprocalToken?
    private var isRunning = false

    private var mruAppOrder: [pid_t] = []
    private var mruObserver: Any?

    private var healthTimer: Timer?

    private var suppressionTap: CFMachPort?
    private var suppressionSource: CFRunLoopSource?
    private(set) var suppressionEnabled = false

    private var clickObservationTap: CFMachPort?
    private var clickObservationSource: CFRunLoopSource?
    private var clickTapInstalled = false

    private var lastClickProcessedTime: TimeInterval = 0

    private var interactionMonitors: [Any] = []
    
    private var lastClickEventTime: TimeInterval = 0
    
    private var pressureMonitor: Any?
    private var lastForceClickTime: TimeInterval = 0
    private let forceCooldown: TimeInterval = 0.4

    private var lastStepTime: TimeInterval = 0
    private lazy var keyEventSource = CGEventSource(stateID: .hidSystemState)

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

    fileprivate var tuning: GestureTuning {
        let s = settings ?? AppSettings()
        return GestureTuning(
            initialThreshold: Float(s.activationThreshold) / 1000.0,
            appSwitcherStepThreshold: Float(s.switcherStepDistance) / 10000.0,
            appSwitcherDebounce: s.switcherDebounce,
            fastVelocityThreshold: Float(s.fastVelocityThreshold) / 150000.0,
            slowVelocityThreshold: Float(s.slowVelocityThreshold) / 100000.0,
            speedSampleCount: s.speedSampleFrames,
            candidateFrames: s.candidateFrames,
            pinchSpreadThreshold: Float(s.pinchSpreadThreshold),
            pinchFrameSpreadThreshold: Float(s.pinchFrameThreshold),
            swipeCoherenceThreshold: Float(s.swipeCoherence),
            swipeAngleTolerance: Float(s.angleTolerance),
            edgeMarginEnabled: s.edgeMarginsEnabled,
            edgeMargin: EdgeMargin(
                left: Float(s.marginLeft) / 100.0,
                right: Float(s.marginRight) / 100.0,
                top: Float(s.marginTop) / 100.0,
                bottom: Float(s.marginBottom) / 100.0
            )
        )
    }

    var activeTouchCount: Int {
        Int(glideActiveTouches)
    }

    // MARK: - Global MT state (moved to file-level global scope)

    // MARK: - Lifecycle

    func start() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            NSLog("[Engine] Accessibility not yet granted — will poll")
            pollForAccessibility()
            return
        }
        actuallyStart()
    }

    private func pollForAccessibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if AXIsProcessTrusted() {
                NSLog("[Engine] Accessibility granted — starting engine")
                self?.actuallyStart()
            } else {
                self?.pollForAccessibility()
            }
        }
    }

    private func actuallyStart() {
        guard !isRunning else { return }

        resetGlobalMTState()
        phase = .idle
        reciprocalToken = nil
        lastClickProcessedTime = 0

        setupSuppressionTap()
        setupClickObservationTap()

        MultitouchBridge.shared.start(callback: glideMTCallback)
        installInteractionMonitors()
        startHealthTimer()
        startMRUTracking()
        isRunning = true
        updateObservableState()
        AppLogger.debug("Started")
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
        AppLogger.debug("Stopped")
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    private func resetGlobalMTState() {
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

    // MARK: - Health timer

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

    private func checkMTHealth() {
        let lastMT = glideLastMTTimestamp
        let now = ProcessInfo.processInfo.systemUptime
        guard lastMT > 0, now - lastMT > 8.0 else { return }
        AppLogger.debug("MT watchdog: no callback for \(now - lastMT)s — restarting")
        MultitouchBridge.shared.stop()
        MultitouchBridge.shared.start(callback: glideMTCallback)
        glideLastMTTimestamp = now
    }

    private func checkTapHealth() {
        if let tap = suppressionTap {
            if !CFMachPortIsValid(tap) {
                AppLogger.debug("Tap health: suppression port invalid — recreating")
                teardownSuppressionTap()
                setupSuppressionTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) && suppressionEnabled {
                AppLogger.debug("Tap health: suppression disabled — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            setupSuppressionTap()
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let tap = clickObservationTap {
            let stale = now - lastClickEventTime > 10.0
            
            if !CFMachPortIsValid(tap) {
                AppLogger.debug("Tap health: click port invalid — recreating")
                teardownClickObservationTap()
                setupClickObservationTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) {
                AppLogger.debug("Tap health: click disabled — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            } else if stale && glideActiveTouches >= 3 {
                AppLogger.debug("Tap health: click tap stale with active touches — rebuilding")
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
                    if GestureEngine.shared.suppressionEnabled,
                       let tap = GestureEngine.shared.suppressionTap {
                        AppLogger.debug("Suppression tap timed out — re-enabling (active)")
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                if type == .leftMouseDown {
                    if glideActiveTouches >= 3 {
                        glideClickFingerCount = glideActiveTouches
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
            AppLogger.debug("Suppression tap created")
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

    // MARK: - Click observation tap

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
                    if GestureEngine.shared.settings?.hapticFeedback ?? true {
                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    }
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
            AppLogger.debug("Click observation tap created")
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
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.handleExternalInteraction()
        }) { interactionMonitors.append(m) }

        startForceClickDetection()
        AppLogger.debug("Installed \(interactionMonitors.count) interaction monitors")
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
            DispatchQueue.main.async { self.processClick(fingerCount: count, isForce: true) }
        }
        if let pm = pressureMonitor { interactionMonitors.append(pm) }
    }

    func processClick(fingerCount n: Int, isForce: Bool = false) {
        if case .switchingApps = phase { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastClickProcessedTime > 0.5 else { return }
        lastClickProcessedTime = now
        glideClickFingerCount = 0

        let modifiers = currentModifier()
        
        var matchedRule: GestureRule? = nil
        if isForce {
            matchedRule = bestRule(fingers: n, direction: .forceClick, modifier: modifiers)
        }
        if matchedRule == nil {
            matchedRule = bestRule(fingers: n, direction: .click, modifier: modifiers)
        }
        
        guard let rule = matchedRule else { return }

        AppLogger.debug("Click — \(n) fingers \(modifierDebugLabel(modifiers)) → \(rule.action.rawValue)")
        clearReciprocalToken()
        phase = .fired

        ActionExecutor.shared.execute(rule.action, targetApp: rule.targetApp)
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
                modifiersAtStart: currentModifier(),
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
                    modifiersAtStart: currentModifier(),
                    frameCount: 1, cumulativeSpreadDelta: 0,
                    prevSpread: frame.spread, minCoherence: frame.coherence,
                    prevCx: frame.cx, prevCy: frame.cy,
                    velocitySamples: []
                ))
                AppLogger.debug("Candidate restarted — \(n) fingers")
                return
            }
            if n < data.fingers { phase = .ignored; updateObservableState(); return }

            data.frameCount += 1

            let frameDx = frame.cx - data.prevCx
            let frameDy = frame.cy - data.prevCy
            let movedFromStart = ((frame.cx - data.startX) * (frame.cx - data.startX)
                                + (frame.cy - data.startY) * (frame.cy - data.startY)).squareRoot()
            
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
                    AppLogger.debug("Classified as \(data.gestureKind)")
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
                AppLogger.debug("Locked as swipe — \(n) fingers")
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
                if delta > 0, data.index < data.effectiveMax {
                    Haptic.switcherStep(); sendCmdTab()
                    lastStepTime = now; data.refX = frame.cx
                    data.index += 1
                    if let fi = data.finderIndex, data.index == fi,
                       data.index < data.effectiveMax {
                        sendCmdTab()
                        data.index += 1
                    }
                    phase = .switchingApps(data)
                } else if delta < 0, data.index > data.effectiveMin {
                    Haptic.switcherStep(); sendCmdShiftTab()
                    lastStepTime = now; data.refX = frame.cx
                    data.index -= 1
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
            AppLogger.debug("Swipe aborted — spread grew mid-swipe")
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

        let gateSpreadOK = abs(frame.spread - updated.initialSpread) < tuning.pinchSpreadThreshold * 0.8
        let gateCoherenceOK = frame.coherence > 0.8
        guard gateSpreadOK && gateCoherenceOK else {
            phase = .ignored
            AppLogger.debug("Swipe blocked by safety gate")
            updateObservableState(); return
        }

        if let rule = bestRule(fingers: data.fingers, direction: direction, speed: speed,
                               modifier: updated.modifiersAtStart) {
            AppLogger.debug("Swipe \(direction.rawValue) — \(data.fingers)F \(speed.rawValue) \(modifierDebugLabel(updated.modifiersAtStart)) (Δ=\(String(format: "%.3f", swipeCentroidMovement)) t=\(String(format: "%.2f", elapsed))s) → \(rule.action.rawValue)")
            if rule.action == .nextApp || rule.action == .prevApp {
                if !beginAppSwitcher(for: rule.action, refX: frame.cx) { phase = .fired }
            } else {
                executeSwipeRule(rule, fingers: data.fingers, direction: direction)
                phase = .fired
            }
        } else {
            AppLogger.debug("Swipe \(direction.rawValue) — \(data.fingers)F \(speed.rawValue): no matching rule")
            phase = .fired
        }
        updateObservableState()
    }

    // MARK: - Direction from angle

    private func directionFromAngle(_ angle: Float) -> GestureType? {
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
        AppLogger.debug("App-switcher committed")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            GestureEngine.restoreMinimizedWindows()
        }
    }

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
            NSLog("[Engine] Restored \(restoredCount) minimized window(s)")
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

        let mru = self.mruAppOrder
        apps.sort { a, b in
            let ai = mru.firstIndex(of: a.processIdentifier) ?? Int.max
            let bi = mru.firstIndex(of: b.processIdentifier) ?? Int.max
            return ai < bi
        }

        let finderIdx: Int? = {
            guard !GestureEngine.finderHasVisibleWindows() else { return nil }
            return apps.firstIndex { $0.bundleIdentifier == "com.apple.finder" }
        }()

        var effMin = 0
        var effMax = apps.count - 1
        if let fi = finderIdx {
            if fi == 0             { effMin = 1 }
            if fi == apps.count - 1 { effMax = apps.count - 2 }
        }
        guard effMin < effMax else { return false }

        clearReciprocalToken()
        sendKeyEvent(kCmd, down: true, flags: .maskCommand)
        Haptic.switcherOpen()

        var index: Int
        if action == .nextApp {
            sendCmdTab(); index = 1
            if let fi = finderIdx, index == fi, index < effMax {
                sendCmdTab(); index += 1
            }
        } else {
            sendCmdShiftTab(); index = apps.count - 1
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
        if let front = NSWorkspace.shared.frontmostApplication {
            mruAppOrder = [front.processIdentifier]
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if !mruAppOrder.contains(app.processIdentifier) {
                mruAppOrder.append(app.processIdentifier)
            }
        }
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

    private func modifierDebugLabel(_ m: ModifierKey) -> String {
        switch m {
        case .none: return ""
        case .command: return "[⌘]"
        case .shift: return "[⇧]"
        case .option: return "[⌥]"
        case .control: return "[⌃]"
        }
    }

    private func bestRule(
        fingers: Int,
        direction: GestureType,
        speed: SwipeSpeed = .normal,
        modifier: ModifierKey
    ) -> GestureRule? {
        guard let store = store else { return nil }
        guard let fingerCount = FingerCount(rawValue: fingers) else { return nil }

        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isFullscreen = isFrontmostWindowFullscreen()
        let isMaximized  = isFrontmostWindowMaximized()

        let matching = store.rules.filter { rule in
            rule.isEnabled
                && rule.fingerCount == fingerCount
                && rule.gestureType == direction
                && matchesWindowState(rule, isFullscreen: isFullscreen, isMaximized: isMaximized)
                && matchesAppFilter(rule, bundleID: bid)
                && (rule.modifier == .none || rule.modifier == modifier)
        }

        return bestRuleMatch(in: matching, speed: speed)
    }

    private func matchesWindowState(_ rule: GestureRule, isFullscreen: Bool, isMaximized: Bool) -> Bool {
        switch rule.windowState {
        case .any:            return true
        case .fullscreen:     return isFullscreen
        case .notFullscreen:  return !isFullscreen
        case .maximized:      return isMaximized
        case .notMaximized:   return !isMaximized
        }
    }

    private func matchesAppFilter(_ rule: GestureRule, bundleID: String?) -> Bool {
        guard !rule.appFilter.isEmpty else { return true }
        return rule.appFilter == bundleID
    }

    private func hasAnySwipeRule(fingers: Int) -> Bool {
        guard let store = store else { return false }
        guard let fingerCount = FingerCount(rawValue: fingers) else { return false }
        let swipeDirs: [GestureType] = [.swipeLeft, .swipeRight, .swipeUp, .swipeDown]
        return store.rules.contains {
            $0.isEnabled && $0.fingerCount == fingerCount && swipeDirs.contains($0.gestureType)
        }
    }

    private func bestRuleMatch(in rules: [GestureRule], speed: SwipeSpeed) -> GestureRule? {
        if let exact = rules.last(where: { $0.speed == speed }) {
            return exact
        }
        let configuredSpeeds = Set(rules.map { $0.speed })
        if configuredSpeeds.count > 1 { return nil }
        guard speed != .normal else { return nil }
        return rules.last(where: { $0.speed == .normal })
    }

    // MARK: - Speed classification

    private func appendVelocitySample(_ distance: Float, to samples: inout [Float]) {
        guard distance > 0 else { return }
        samples.append(distance)
        let fillCap = tuning.speedSampleCount
        if samples.count > fillCap {
            samples.removeFirst(samples.count - fillCap)
        }
    }

    private func classifySpeed(
        velocitySamples: [Float],
        totalDisplacement: Float,
        elapsedSeconds: TimeInterval
    ) -> SwipeSpeed {
        let slowFrame = tuning.slowVelocityThreshold
        let fastFrame = tuning.fastVelocityThreshold
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

    private func executeSwipeRule(_ rule: GestureRule, fingers: Int, direction: GestureType) {
        Haptic.forAction(rule.action)
        ActionExecutor.shared.execute(rule.action, targetApp: rule.targetApp)
        if rule.reciprocal {
            reciprocalToken = makeReciprocalToken(for: rule.action, fingers: fingers, direction: direction)
        } else {
            clearReciprocalToken()
        }
        updateObservableState()
    }

    private func consumeReciprocalToken(fingers: Int, direction: GestureType) -> Bool {
        guard let token = reciprocalToken,
              token.fingers == fingers, token.direction == direction else { return false }
        if token.inverseAction == .restoreMinimizedApps,
           !hasRestorableMinimizedApps() {
            clearReciprocalToken(); return false
        }
        AppLogger.debug("Reciprocal \(direction.rawValue) → \(token.inverseAction.rawValue)")
        let action = token.inverseAction
        clearReciprocalToken()
        Haptic.reciprocal()
        ActionExecutor.shared.execute(action)
        return true
    }

    private func makeReciprocalToken(for action: GestureAction, fingers: Int, direction: GestureType) -> ReciprocalToken? {
        guard let rev = opposite(direction), let inverse = inverseAction(for: action) else { return nil }
        return ReciprocalToken(inverseAction: inverse, fingers: fingers, direction: rev)
    }

    private func clearReciprocalToken() {
        reciprocalToken = nil
        isReciprocalActive = false
    }

    private func opposite(_ dir: GestureType) -> GestureType? {
        switch dir {
        case .swipeLeft:  return .swipeRight
        case .swipeRight: return .swipeLeft
        case .swipeUp:    return .swipeDown
        case .swipeDown:  return .swipeUp
        default:          return nil
        }
    }

    private func inverseAction(for action: GestureAction) -> GestureAction? {
        switch action {
        case .missionControl:       return .missionControl
        case .appExpose:            return .appExpose
        case .showDesktop:          return .showDesktop
        case .launchpad:            return .launchpad
        case .toggleFullscreen:     return .toggleFullscreen
        case .notificationCenter:   return .notificationCenter
        case .enterFullscreen:      return .exitFullscreen
        case .exitFullscreen:       return .enterFullscreen
        case .maximizeWindow:       return .restoreWindow
        case .restoreWindow:        return .maximizeWindow
        case .minimizeWindow:       return .restoreWindow
        case .minimizeAllApps:      return .restoreMinimizedApps
        case .restoreMinimizedApps: return .minimizeAllApps
        case .snapLeft, .snapRight,
             .snapTopLeft, .snapTopRight,
             .snapBottomLeft, .snapBottomRight,
             .centerWindow:         return .restoreWindow
        case .activateNextApp:      return .activatePrevApp
        case .activatePrevApp:      return .activateNextApp
        default:                    return nil
        }
    }

    private func hasRestorableMinimizedApps() -> Bool {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var wins: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &wins) == .success,
                  let windowList = wins as? [AXUIElement] else { continue }
            for w in windowList {
                var minimized: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized) == .success,
                   (minimized as? Bool) == true {
                    return true
                }
            }
        }
        return false
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

    // MARK: - Window Inspection (Accessibility API)

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &win) == .success,
              CFGetTypeID(win!) == AXUIElementGetTypeID() else { return nil }
        return (win as! AXUIElement)
    }

    private func axBool(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &val) == .success else { return nil }
        return val as? Bool
    }

    private func isFrontmostWindowFullscreen() -> Bool {
        guard let w = focusedWindow() else { return false }
        return axBool(w, attribute: "AXFullScreen" as CFString) ?? false
    }

    private func isFrontmostWindowMaximized() -> Bool {
        guard let w = focusedWindow(),
              let frame = windowFrame(w),
              let screen = screen(for: w) else { return false }
        let visible = screen.visibleFrame
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let cocoaFrame = CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
        let tolerance: CGFloat = 16
        return abs(cocoaFrame.minX - visible.minX) <= tolerance
            && abs(cocoaFrame.minY - visible.minY) <= tolerance
            && abs(cocoaFrame.width  - visible.width)  <= tolerance
            && abs(cocoaFrame.height - visible.height) <= tolerance
    }

    private func windowFrame(_ win: AXUIElement) -> CGRect? {
        var posRef:  CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)  == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString,     &sizeRef) == .success else { return nil }
        var pos  = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef  as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize,  &size)
        return CGRect(origin: pos, size: size)
    }

    private func screen(for window: AXUIElement) -> NSScreen? {
        guard let frame = windowFrame(window) else { return NSScreen.main }
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let cocoaFrame = CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

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
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String, role == "AXWindow" else {
                continue
            }

            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, title == "Desktop" {
                continue
            }

            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool, minimized {
                continue
            }

            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
                var size = CGSize.zero
                if AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) {
                    if size.width < 1 || size.height < 1 { continue }
                }
            }

            return true
        }

        return false
    }

    private func currentModifier() -> ModifierKey {
        let f = NSEvent.modifierFlags
        if f.contains(.command) { return .command }
        if f.contains(.shift)   { return .shift }
        if f.contains(.option)  { return .option }
        if f.contains(.control) { return .control }
        return .none
    }
}

// ─────────────────────────────────────────────
// MARK: - AppLogger
// ─────────────────────────────────────────────

private struct AppLogger {
    static func debug(_ msg: String) {
        NSLog("[Engine] %@", msg)
        print("[Engine] \(msg)")
    }
}
