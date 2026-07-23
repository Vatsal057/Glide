import Foundation
import ApplicationServices

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
    fileprivate static var _latchedGestureCount: Int32 = 0
    fileprivate static var _horizBlockedCounts: Set<Int> = []
    fileprivate static var _vertBlockedCounts: Set<Int> = []
    fileprivate static var _pinchBlockedCounts: Set<Int> = []
    fileprivate static var _gestureAxis: Int32 = 0          // GestureAxis raw
    fileprivate static var _axisStartValid = false
    fileprivate static var _axisStartCx: Float = 0
    fileprivate static var _axisStartCy: Float = 0
    fileprivate static var _axisStartSpread: Float = 0

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

    /// Finger count latched for the whole touch session: once 3+ contacts are
    /// down it holds the MAXIMUM seen and only resets when every finger lifts.
    /// A momentary contact dropout (thumb re-registering, finger dip to 2) can
    /// therefore never flip suppression off mid-gesture.
    static var glideGestureFingerCount: Int32 {
        stateLock.lock(); defer { stateLock.unlock() }; return _latchedGestureCount
    }

    /// Finger counts whose events the suppression tap swallows, split by what
    /// Glide actually claims: horizontal swipes (rules or app switcher),
    /// vertical swipes, and pinches (magnify events). Precomputed on the main
    /// thread whenever rules change — the tap thread only ever does a set
    /// lookup, so blocking is race-free from event #1 and an unconfigured
    /// axis/pinch reaches the system untouched.
    static func setSuppressedCounts(horiz: Set<Int>, vert: Set<Int>, pinch: Set<Int>) {
        stateLock.lock(); defer { stateLock.unlock() }
        _horizBlockedCounts = horiz
        _vertBlockedCounts = vert
        _pinchBlockedCounts = pinch
    }

    static func isHorizBlocked(count: Int) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return _horizBlockedCounts.contains(count)
    }

    static func isVertBlocked(count: Int) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return _vertBlockedCounts.contains(count)
    }

    static func isPinchBlocked(count: Int) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return _pinchBlockedCounts.contains(count)
    }

    /// Dominant motion of the current touch session, classified straight from
    /// the raw MT stream on its own thread (no main-thread hop, so the tap
    /// never races it). Latched once per session; reset when all fingers lift.
    enum GestureAxis: Int32 { case none = 0, horizontal = 1, vertical = 2, pinch = 3 }

    static var glideGestureAxis: GestureAxis {
        stateLock.lock(); defer { stateLock.unlock() }
        return GestureAxis(rawValue: _gestureAxis) ?? .none
    }

    /// Movement needed before the session's axis locks. Well below Glide's own
    /// swipe threshold and far below any native gesture's commit point.
    private static let axisLockDistance: Float = 0.008

    static func updateGestureAxis(cx: Float, cy: Float, spread: Float) {
        stateLock.lock(); defer { stateLock.unlock() }
        guard _axisStartValid else {
            _axisStartValid = true
            _axisStartCx = cx; _axisStartCy = cy; _axisStartSpread = spread
            return
        }
        guard _gestureAxis == GestureAxis.none.rawValue else { return }
        let dx = abs(cx - _axisStartCx)
        let dy = abs(cy - _axisStartCy)
        let ds = abs(spread - _axisStartSpread)
        if ds >= axisLockDistance, ds > max(dx, dy) * 0.8 {
            _gestureAxis = GestureAxis.pinch.rawValue
        } else if max(dx, dy) >= axisLockDistance {
            _gestureAxis = (dx > dy ? GestureAxis.horizontal : GestureAxis.vertical).rawValue
        }
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
        _latchedGestureCount = 0
        _gestureAxis = 0
        _axisStartValid = false
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
            TouchTracker._latchedGestureCount = 0
            TouchTracker._gestureAxis = 0
            TouchTracker._axisStartValid = false
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
    if activeCount >= 3, activeCount > TouchTracker._latchedGestureCount {
        TouchTracker._latchedGestureCount = activeCount
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

    if activeCount >= 3 {
        TouchTracker.updateGestureAxis(cx: cx, cy: cy, spread: spread)
    }

    let frameData = TouchFrameData(count: activeCount, cx: cx, cy: cy, spread: spread, coherence: coherence)
    DispatchQueue.main.async { GestureEngine.shared.onTouches(frameData) }
}
