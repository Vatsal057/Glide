import Foundation
import ApplicationServices

/// Per-gesture verdict for the suppression tap. Starts `undecided` (events pass
/// through so native recognition isn't starved). The moment the processor
/// resolves a swipe direction it becomes `block` (a Glide rule covers it — the
/// system saw only a sub-threshold prefix) or `pass` (no rule — the native
/// gesture keeps the full event stream). Reset when fingers drop below 3.
enum GestureSuppressionDecision: Int32 {
    case undecided = 0, block = 1, pass = 2
}

enum TouchTracker {
    // ─────────────────────────────────────────────
    // MARK: - Global MT state
    //
    // Written on the MT/HID callback thread, read (and sometimes written) on
    // the main thread. Every mutable field below is guarded by `stateLock`;
    // the public accessors take the lock, the MT callback takes it once per
    // frame and works on the backing fields directly. NSLock is not
    // re-entrant — never call a public accessor while holding the lock.
    // ─────────────────────────────────────────────

    static let stateLock = NSLock()

    fileprivate static var _deviceFingerCounts: [UnsafeMutableRawPointer: Int] = [:]
    fileprivate static var _sessionPeakActiveTouches: Int = 0
    fileprivate static var _fingerFirstSeen: [Int32: TimeInterval] = [:]
    fileprivate static var _activeTouches: Int32 = 0
    fileprivate static var _clickFingerCount: Int32 = 0
    fileprivate static var _lastMTTimestamp: TimeInterval = 0
    fileprivate static var _lastDispatchedCount: Int32 = 0
    fileprivate static var _oldestFingerAge: Double = 0
    fileprivate static var _newestFingerAge: Double = 0
    fileprivate static var _lastFingerLiftTime: TimeInterval = 0
    fileprivate static var _gestureDecision: Int32 = 0
    fileprivate static var _pinchRuleActive: Bool = false

    static func updateDeviceFingerCount(device: UnsafeMutableRawPointer, count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _deviceFingerCounts[device] = count

        let currentMax = _deviceFingerCounts.values.max() ?? 0
        if currentMax == 0 {
            _sessionPeakActiveTouches = 0
        } else {
            _sessionPeakActiveTouches = max(_sessionPeakActiveTouches, currentMax)
        }
    }

    static func getThreeFingerCount() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _deviceFingerCounts.values.max() ?? 0
    }

    static func getSessionPeakActiveTouches() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _sessionPeakActiveTouches
    }

    /// Max age difference (seconds) between oldest and newest active finger for a valid click.
    static let maxClickFingerAgeSpread: TimeInterval = 0.15

    /// How long after a finger lift clicks stay blocked. Tap-to-click on an extra
    /// finger (e.g. 3 resting + 4th taps) emits the mouseDown right as that finger
    /// lifts; a deliberate click keeps every finger planted through the press.
    /// Finger *ages* can't be used for this — resting fingers intermittently drop
    /// out of the MT touch state and re-register, resetting their first-seen time.
    static let recentLiftClickBlock: TimeInterval = 0.25

    static func areClickTouchesSimultaneous() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return areClickTouchesSimultaneousLocked()
    }

    fileprivate static func areClickTouchesSimultaneousLocked() -> Bool {
        let spread = _oldestFingerAge - _newestFingerAge
        return spread <= maxClickFingerAgeSpread
    }

    static func clickGestureMatchesFingerState(count: Int, peak: Int) -> Bool {
        guard count >= 3, peak >= count else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        if now - _lastFingerLiftTime < recentLiftClickBlock { return false }
        if count == peak { return true }
        return areClickTouchesSimultaneousLocked()
    }

    static var glideActiveTouches: Int32 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _activeTouches }
        set { stateLock.lock(); defer { stateLock.unlock() }; _activeTouches = newValue }
    }

    /// True while the current finger count has a configured Glide pinch rule.
    /// Read by the suppression tap: magnify events are only swallowed when a
    /// pinch rule could consume them — otherwise native pinch/spread
    /// (Launchpad, Show Desktop) keeps its full event stream even mid-block.
    static var glidePinchRuleActive: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _pinchRuleActive }
        set { stateLock.lock(); defer { stateLock.unlock() }; _pinchRuleActive = newValue }
    }

    static var glideGestureDecision: GestureSuppressionDecision {
        get { stateLock.lock(); defer { stateLock.unlock() }; return GestureSuppressionDecision(rawValue: _gestureDecision) ?? .undecided }
        set { stateLock.lock(); defer { stateLock.unlock() }; _gestureDecision = newValue.rawValue }
    }

    static var glideClickFingerCount: Int32 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _clickFingerCount }
        set { stateLock.lock(); defer { stateLock.unlock() }; _clickFingerCount = newValue }
    }

    static func resetGlobalMTState() {
        stateLock.lock()
        defer { stateLock.unlock() }
        _deviceFingerCounts.removeAll(keepingCapacity: true)
        _sessionPeakActiveTouches = 0
        _activeTouches = 0
        _clickFingerCount = 0
        _lastMTTimestamp = 0
        _lastDispatchedCount = 0
        _fingerFirstSeen.removeAll(keepingCapacity: true)
        _oldestFingerAge = 0
        _newestFingerAge = 0
        _lastFingerLiftTime = 0
        _gestureDecision = 0
    }
}
let glideMTCallback: GLDTFrameCallback = { points, count, timestamp, context in
    var activeTouches: [GLDTouchPoint] = []
    if let points = points, count > 0 {
        let n = Int(count)
        activeTouches.reserveCapacity(n)
        let tuning = Settings.shared.tuning
        let edge = tuning.edgeMarginEnabled
        let m = tuning.edgeMargin

        for i in 0..<n {
            let t = points[i]
            guard t.state >= 3 && t.state <= 4 else { continue }
            if edge {
                if t.x < m.left || t.x > 1.0 - m.right || t.y < m.bottom || t.y > 1.0 - m.top { continue }
            }
            activeTouches.append(t)
        }
    }

    // Since the C-bridge abstracts devices and only opens the default one,
    // we use a dummy pointer to track its finger count.
    let dummyDevice = UnsafeMutableRawPointer(bitPattern: 1)!
    TouchTracker.updateDeviceFingerCount(device: dummyDevice, count: activeTouches.count)

    let activeCount = Int32(activeTouches.count)
    let nowTs = ProcessInfo.processInfo.systemUptime

    TouchTracker.stateLock.lock()
    TouchTracker._lastMTTimestamp = nowTs

    guard activeCount > 0 else {
        let hadTouches = TouchTracker._activeTouches > 0
        if hadTouches {
            TouchTracker._activeTouches = 0
            TouchTracker._lastDispatchedCount = 0
            TouchTracker._fingerFirstSeen.removeAll(keepingCapacity: true)
            TouchTracker._oldestFingerAge = 0
            TouchTracker._newestFingerAge = 0
            TouchTracker._gestureDecision = 0
        }
        TouchTracker.stateLock.unlock()
        if hadTouches {
            DispatchQueue.main.async {
                TouchTracker.glideClickFingerCount = 0
                GestureEngine.shared.onTouches(TouchFrameData(count: 0, cx: 0, cy: 0, spread: 0, coherence: 1))
            }
        }
        return
    }

    let n = Int(activeCount)

    for touch in activeTouches {
        if TouchTracker._fingerFirstSeen[touch.identifier] == nil {
            TouchTracker._fingerFirstSeen[touch.identifier] = nowTs
        }
    }
    if TouchTracker._fingerFirstSeen.count != activeTouches.count {
        for key in TouchTracker._fingerFirstSeen.keys where !activeTouches.contains(where: { $0.identifier == key }) {
            TouchTracker._fingerFirstSeen.removeValue(forKey: key)
        }
    }
    if let oldest = TouchTracker._fingerFirstSeen.values.min(),
       let newest = TouchTracker._fingerFirstSeen.values.max() {
        TouchTracker._oldestFingerAge = nowTs - oldest
        TouchTracker._newestFingerAge = nowTs - newest
    }

    let prevActiveTouches = TouchTracker._activeTouches
    TouchTracker._activeTouches = activeCount
    if activeCount < prevActiveTouches {
        TouchTracker._lastFingerLiftTime = nowTs
    }

    let skipDispatch = activeCount < 3 && activeCount == TouchTracker._lastDispatchedCount
    if !skipDispatch {
        TouchTracker._lastDispatchedCount = activeCount
    }
    TouchTracker.stateLock.unlock()

    if skipDispatch { return }

    var sumX: Float = 0, sumY: Float = 0
    for i in 0..<n { sumX += activeTouches[i].x; sumY += activeTouches[i].y }
    let cx = sumX / Float(n)
    let cy = sumY / Float(n)

    var spread: Float = 0
    if n >= 3 {
        var s: Float = 0
        for i in 0..<n {
            let dx = activeTouches[i].x - cx
            let dy = activeTouches[i].y - cy
            s += (dx * dx + dy * dy).squareRoot()
        }
        spread = s / Float(n)
    }

    var coherence: Float = 1.0
    if n >= 3 {
        let countFloat = Float(n)
        var sumVx: Float = 0
        var sumVy: Float = 0
        for i in 0..<n {
            sumVx += activeTouches[i].vx
            sumVy += activeTouches[i].vy
        }
        let meanVx = sumVx / countFloat
        let meanVy = sumVy / countFloat
        let meanMag = (meanVx * meanVx + meanVy * meanVy).squareRoot()

        var sumMag: Float = 0
        for i in 0..<n {
            let vx = activeTouches[i].vx
            let vy = activeTouches[i].vy
            sumMag += (vx * vx + vy * vy).squareRoot()
        }
        let meanOfMags = sumMag / countFloat

        if meanOfMags > 0.001 {
            coherence = meanMag / meanOfMags
        }
    }

    let frameData = TouchFrameData(count: activeCount, cx: cx, cy: cy, spread: spread, coherence: coherence)
    DispatchQueue.main.async { GestureEngine.shared.onTouches(frameData) }
}
