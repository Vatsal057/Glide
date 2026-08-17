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
    private static let frameDispatchLock = NSLock()
    private static var pendingTerminalFrame: TouchFrameData?
    private static var pendingLatestFrame: TouchFrameData?
    private static var frameDispatchScheduled = false

    fileprivate static func enqueueFrame(_ frame: TouchFrameData) {
        frameDispatchLock.lock()
        if frame.count < 3 {
            pendingTerminalFrame = frame
            pendingLatestFrame = nil
        } else {
            pendingLatestFrame = frame
        }
        let shouldSchedule = !frameDispatchScheduled
        if shouldSchedule { frameDispatchScheduled = true }
        frameDispatchLock.unlock()

        if shouldSchedule {
            DispatchQueue.main.async { drainLatestFrame() }
        }
    }

    private static func drainLatestFrame() {
        frameDispatchLock.lock()
        let frame: TouchFrameData?
        if let terminal = pendingTerminalFrame {
            frame = terminal
            pendingTerminalFrame = nil
        } else {
            frame = pendingLatestFrame
            pendingLatestFrame = nil
        }
        frameDispatchLock.unlock()

        if let frame { GestureEngine.shared.onTouches(frame) }

        frameDispatchLock.lock()
        let hasPendingFrame = pendingTerminalFrame != nil || pendingLatestFrame != nil
        if !hasPendingFrame { frameDispatchScheduled = false }
        frameDispatchLock.unlock()

        if hasPendingFrame {
            DispatchQueue.main.async { drainLatestFrame() }
        }
    }

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

    fileprivate static var _edgeMarginEnabled: Bool = false
    fileprivate static var _edgeMargin: EdgeMargin = EdgeMargin(left: 0, right: 0, top: 0, bottom: 0)

    static func updateTuningCache(edgeMarginEnabled: Bool, edgeMargin: EdgeMargin) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _edgeMarginEnabled = edgeMarginEnabled
        _edgeMargin = edgeMargin
    }

    // ── TrackPoint cache (read on the MT thread once per frame) ──

    fileprivate static var _trackPointEnabled: Bool = false
    /// The single corner that anchors the stick. Scrolling is a second finger on
    /// the pad, not a second corner, so one zone covers both modes.
    fileprivate static var _trackPointZone: TrackpadZone = .bottomRight
    fileprivate static var _trackPointReach: Float = 0.16
    /// Identifier of the contact the TrackPoint is following, or -1. Keeps frames
    /// flowing for that one finger even after others join — so a second finger can
    /// tap-to-click or scroll without dropping the session, and so the controller
    /// still hears the lift of a contact it has already disqualified.
    fileprivate static var _trackPointAnchoredID: Int32 = -1
    fileprivate static var _trackPointStreaming: Bool = false

    static func updateTrackPointCache(enabled: Bool, zone: TrackpadZone, reach: Float) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _trackPointEnabled = enabled
        _trackPointZone = zone
        _trackPointReach = reach
        if !enabled {
            _trackPointAnchoredID = -1
            _trackPointStreaming = false
        }
    }

    static var trackPointAnchoredID: Int32 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _trackPointAnchoredID }
        set { stateLock.lock(); defer { stateLock.unlock() }; _trackPointAnchoredID = newValue }
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
        _trackPointAnchoredID = -1
        _trackPointStreaming = false
        stateLock.unlock()

        frameDispatchLock.lock()
        pendingTerminalFrame = nil
        pendingLatestFrame = nil
        frameDispatchLock.unlock()
    }
}
let glideMTCallback: GLDTFrameCallback = { points, count, timestamp, context in
    feedTrackPoint(points, count)

    var activeTouches: [GLDTouchPoint] = []
    if let points = points, count > 0 {
        let n = Int(count)
        activeTouches.reserveCapacity(n)
        TouchTracker.stateLock.lock()
        let edge = TouchTracker._edgeMarginEnabled
        let m = TouchTracker._edgeMargin
        TouchTracker.stateLock.unlock()

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
        }
        TouchTracker.stateLock.unlock()
        if hadTouches {
            TouchTracker.enqueueFrame(
                TouchFrameData(count: 0, cx: 0, cy: 0, spread: 0, coherence: 1)
            )
        }
        return
    }

    let n = Int(activeCount)

    for touch in activeTouches {
        if TouchTracker._fingerFirstSeen[touch.identifier] == nil {
            TouchTracker._fingerFirstSeen[touch.identifier] = nowTs
        }
    }
    // Mutating the dictionary while iterating its own `keys` view forces a copy of
    // the storage mid-loop, on the multitouch thread, every frame a finger lifts.
    // Filtering in place says the same thing without one.
    if TouchTracker._fingerFirstSeen.count != activeTouches.count {
        TouchTracker._fingerFirstSeen = TouchTracker._fingerFirstSeen.filter { entry in
            activeTouches.contains { $0.identifier == entry.key }
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
    TouchTracker.enqueueFrame(frameData)
}

/// Feeds the corner TrackPoint from the raw contact list, ahead of everything
/// the gesture pipeline does with the same frame.
///
/// Deliberately independent of `TouchFrameData`: it reads a single contact,
/// which no gesture rule ever matches, and it runs *before* the edge-margin
/// palm rejection — a stick anchored in the corner of the pad would otherwise
/// be filtered away by the very margin that protects swipes from stray thumbs.
///
/// Costs nothing when the feature is off, and nothing beyond a bounds check
/// when it's on but no finger is in the zone.
private func feedTrackPoint(_ points: UnsafePointer<GLDTouchPoint>?, _ count: Int32) {
    TouchTracker.stateLock.lock()
    let enabled    = TouchTracker._trackPointEnabled
    let zone       = TouchTracker._trackPointZone
    let reach      = TouchTracker._trackPointReach
    let anchoredID = TouchTracker._trackPointAnchoredID
    let wasStreaming = TouchTracker._trackPointStreaming
    TouchTracker.stateLock.unlock()

    guard enabled else { return }

    var contacts = 0
    var lone: GLDTouchPoint?
    var anchored: GLDTouchPoint?
    if let points, count > 0 {
        for index in 0..<Int(count) {
            let touch = points[index]
            guard touch.state >= 3 && touch.state <= 4 else { continue }
            contacts += 1
            lone = touch
            if touch.identifier == anchoredID { anchored = touch }
        }
    }

    // A candidate is a lone contact sitting in the zone — the only thing that
    // may *start* a session. Extra fingers disqualify it, so resting a hand on
    // the pad can never arm the stick.
    var candidate: TrackPointSample?
    if contacts == 1, let lone, zone.contains(x: lone.x, y: lone.y, reach: reach) {
        candidate = TrackPointSample(lone)
    }

    let streaming = candidate != nil || anchoredID >= 0
    guard streaming || wasStreaming else { return }

    TouchTracker.stateLock.lock()
    TouchTracker._trackPointStreaming = streaming
    TouchTracker.stateLock.unlock()

    let tracked = anchored.map(TrackPointSample.init)
    DispatchQueue.main.async {
        TrackPointController.shared.ingest(candidate: candidate, tracked: tracked, contacts: contacts)
    }
}
