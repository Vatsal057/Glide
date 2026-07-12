import Foundation
import ApplicationServices
import CoreGraphics

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
    fileprivate static var _prevFingerAngle: [Int32: Float] = [:]
    /// Fingers that were on the pad when a left-button press started with <3
    /// touches (i.e. a click-drag, not a click gesture). While the button stays
    /// down they are excluded from gesture frames, so a swipe made with the
    /// other fingers mid-drag still reads as 3/4/5 fingers and the stationary
    /// drag finger can't corrupt the centroid/spread (pinch veto).
    fileprivate static var _dragAnchorIDs: Set<Int32> = []

    /// Mean signed angular delta (degrees, + = counterclockwise) of the fingers
    /// around the centroid since the previous frame. Stateful per finger ID.
    static func computeTwist(_ touches: [MTTouch], cx: Float, cy: Float) -> Float {
        stateLock.lock()
        defer { stateLock.unlock() }
        var sum: Float = 0
        var matched = 0
        var newAngles: [Int32: Float] = [:]
        for t in touches {
            let angle = atan2(t.normalizedPosition.y - cy, t.normalizedPosition.x - cx) * (180 / .pi)
            newAngles[t.identifier] = angle
            if let prev = _prevFingerAngle[t.identifier] {
                var d = angle - prev
                if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                sum += d
                matched += 1
            }
        }
        _prevFingerAngle = newAngles
        return matched > 0 ? sum / Float(matched) : 0
    }

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

    /// Snapshot the fingers currently on the pad as drag anchors. Call when a
    /// left mouse-down arrives with fewer than 3 fingers (a click/drag, not a
    /// click gesture).
    static func armDragAnchors() {
        stateLock.lock()
        _dragAnchorIDs = Set(_fingerFirstSeen.keys)
        stateLock.unlock()
    }

    /// True while a click-drag is in progress (anchors armed, button still down).
    static var dragAnchorsActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !_dragAnchorIDs.isEmpty
    }

    /// Removes drag-anchor touches from a frame while the left button is held;
    /// clears the anchors once the button is released. Called once per MT frame.
    static func filterDragAnchors(_ touches: inout [MTTouch], leftButtonDown: Bool) {
        stateLock.lock()
        let anchors = _dragAnchorIDs
        stateLock.unlock()
        guard !anchors.isEmpty else { return }
        if leftButtonDown {
            // ponytail: anchor by finger identity; a drag re-grip (drag lock) gets
            // a new touch ID and isn't filtered — acceptable, gesture just needs a retry.
            touches.removeAll { anchors.contains($0.identifier) }
        } else {
            stateLock.lock()
            _dragAnchorIDs.removeAll()
            stateLock.unlock()
        }
    }

    static var glideActiveTouches: Int32 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _activeTouches }
        set { stateLock.lock(); defer { stateLock.unlock() }; _activeTouches = newValue }
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
        _prevFingerAngle.removeAll(keepingCapacity: true)
        _dragAnchorIDs.removeAll(keepingCapacity: true)
    }
}
let glideMTCallback: MTContactCallback = { device, data, count, _, _ in
    // Runs up to 120×/s per device — single pass, one array, capacity reserved
    // up front so steady-state frames make no heap allocations.
    var activeTouches: [MTTouch] = []
    if let data, count > 0 {
        let n = Int(count)
        activeTouches.reserveCapacity(n)
        let raw = data.assumingMemoryBound(to: MTTouch.self)
        let tuning = Settings.shared.tuning
        let edge = tuning.edgeMarginEnabled
        let m = tuning.edgeMargin

        for i in 0..<n {
            let t = raw[i]
            guard t.state >= 3 && t.state <= 4 else { continue }
            if edge {
                let x = t.normalizedPosition.x; let y = t.normalizedPosition.y
                if x < m.left || x > 1.0 - m.right || y < m.bottom || y > 1.0 - m.top { continue }
            }
            activeTouches.append(t)
        }
    }
    // Drop the drag-anchor finger(s) while a click-drag's left button is held, so
    // a swipe made with the other fingers still reads as N fingers and the
    // stationary drag finger doesn't pollute centroid/spread. Thread-safe button read.
    let leftButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
    TouchTracker.filterDragAnchors(&activeTouches, leftButtonDown: leftButtonDown)

    if let dev = device {
        TouchTracker.updateDeviceFingerCount(device: dev, count: activeTouches.count)
    }

    let activeCount = Int32(activeTouches.count)
    let nowTs = ProcessInfo.processInfo.systemUptime

    // One lock acquisition per frame — all shared bookkeeping happens inside.
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
            TouchTracker._prevFingerAngle.removeAll(keepingCapacity: true)
        }
        TouchTracker.stateLock.unlock()
        if hadTouches {
            DispatchQueue.main.async {
                TouchTracker.glideClickFingerCount = 0
                GestureEngine.shared.onTouches(TouchFrameData(count: 0, cx: 0, cy: 0, spread: 0, coherence: 1))
            }
        }
        return 0
    }

    let n = Int(activeCount)

    for touch in activeTouches {
        if TouchTracker._fingerFirstSeen[touch.identifier] == nil {
            TouchTracker._fingerFirstSeen[touch.identifier] = nowTs
        }
    }
    if TouchTracker._fingerFirstSeen.count != activeTouches.count {
        // ≤11 touches — linear scan beats building a Set every frame.
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

    if skipDispatch { return 0 }

    var sumX: Float = 0, sumY: Float = 0
    for i in 0..<n { sumX += activeTouches[i].normalizedPosition.x; sumY += activeTouches[i].normalizedPosition.y }
    let cx = sumX / Float(n)
    let cy = sumY / Float(n)

    var spread: Float = 0
    if n >= 3 {
        var s: Float = 0
        for i in 0..<n {
            let dx = activeTouches[i].normalizedPosition.x - cx
            let dy = activeTouches[i].normalizedPosition.y - cy
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
            sumVx += activeTouches[i].velocity.x
            sumVy += activeTouches[i].velocity.y
        }
        let meanVx = sumVx / countFloat
        let meanVy = sumVy / countFloat
        let meanMag = (meanVx * meanVx + meanVy * meanVy).squareRoot()

        var sumMag: Float = 0
        for i in 0..<n {
            let vx = activeTouches[i].velocity.x
            let vy = activeTouches[i].velocity.y
            sumMag += (vx * vx + vy * vy).squareRoot()
        }
        let meanOfMags = sumMag / countFloat

        if meanOfMags > 0.001 {
            coherence = meanMag / meanOfMags
        }
    }

    let twist: Float = n >= 3 ? TouchTracker.computeTwist(activeTouches, cx: cx, cy: cy) : 0

    let frameData = TouchFrameData(count: activeCount, cx: cx, cy: cy, spread: spread, coherence: coherence, twist: twist)
    DispatchQueue.main.async { GestureEngine.shared.onTouches(frameData) }
    return 0
}
