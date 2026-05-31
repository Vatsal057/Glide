import Foundation
import ApplicationServices

enum TouchTracker {
    // ─────────────────────────────────────────────
    // MARK: - Global MT state (written on MT/HID thread, read on main)
    // ─────────────────────────────────────────────

    static var deviceFingerCounts: [UnsafeMutableRawPointer: Int] = [:]
    static var sessionPeakActiveTouches: Int = 0
    static let countsLock = NSLock()

    static func updateDeviceFingerCount(device: UnsafeMutableRawPointer, count: Int) {
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

    static func getThreeFingerCount() -> Int {
        countsLock.lock()
        defer { countsLock.unlock() }
        return deviceFingerCounts.values.max() ?? 0
    }

    static func getSessionPeakActiveTouches() -> Int {
        countsLock.lock()
        defer { countsLock.unlock() }
        return sessionPeakActiveTouches
    }

    /// Max age difference (seconds) between oldest and newest active finger for a valid click.
    static let maxClickFingerAgeSpread: TimeInterval = 0.15

    static func areClickTouchesSimultaneous() -> Bool {
        let spread = glideOldestFingerAge - glideNewestFingerAge
        return spread <= maxClickFingerAgeSpread
    }

    static func clickGestureMatchesFingerState(count: Int, peak: Int) -> Bool {
        guard count >= 3, peak >= count else { return false }
        if count == peak { return true }
        return areClickTouchesSimultaneous()
    }

    static var glideActiveTouches: Int32 = 0
    static var glideClickFingerCount: Int32 = 0
    static var glidePeakFingerCount: Int32 = 0
    static var glideLastMTTimestamp: TimeInterval = 0

    static var glideLastDispatchedCount: Int32 = 0

    static var glideFingerFirstSeen: [Int32: TimeInterval] = [:]

    static var glideOldestFingerAge: Double = 0.0
    static var glideNewestFingerAge: Double = 0.0

    static func resetGlobalMTState() {
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
}
let glideMTCallback: MTContactCallback = { device, data, count, _, _ in
    TouchTracker.glideLastMTTimestamp = ProcessInfo.processInfo.systemUptime

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

    let activeTouches = validTouches.filter { $0.state >= 3 && $0.state <= 4 }
    if let dev = device {
        TouchTracker.updateDeviceFingerCount(device: dev, count: activeTouches.count)
    }

    let activeCount = Int32(activeTouches.count)

    guard activeCount > 0 else {
        if TouchTracker.glideActiveTouches > 0 {
            TouchTracker.glideActiveTouches = 0
            TouchTracker.glideLastDispatchedCount = 0
            TouchTracker.glideFingerFirstSeen.removeAll(keepingCapacity: true)
            TouchTracker.glideOldestFingerAge = 0
            TouchTracker.glideNewestFingerAge = 0
            DispatchQueue.main.async {
                TouchTracker.glideClickFingerCount = 0
                GestureEngine.shared.peakResetWorkItem?.cancel()
                let work = DispatchWorkItem { TouchTracker.glidePeakFingerCount = 0 }
                GestureEngine.shared.peakResetWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                GestureEngine.shared.onTouches(TouchFrameData(count: 0, cx: 0, cy: 0, spread: 0, coherence: 1))
            }
        }
        return 0
    }

    let n = Int(activeCount)

    let nowTs = TouchTracker.glideLastMTTimestamp

    for touch in activeTouches {
        if TouchTracker.glideFingerFirstSeen[touch.identifier] == nil {
            TouchTracker.glideFingerFirstSeen[touch.identifier] = nowTs
        }
    }
    if TouchTracker.glideFingerFirstSeen.count != activeTouches.count {
        let activeIDs = Set(activeTouches.map { $0.identifier })
        TouchTracker.glideFingerFirstSeen = TouchTracker.glideFingerFirstSeen.filter { activeIDs.contains($0.key) }
    }
    if let oldest = TouchTracker.glideFingerFirstSeen.values.min(),
       let newest = TouchTracker.glideFingerFirstSeen.values.max() {
        TouchTracker.glideOldestFingerAge = nowTs - oldest
        TouchTracker.glideNewestFingerAge = nowTs - newest
    }

    let prevActiveTouches = TouchTracker.glideActiveTouches
    TouchTracker.glideActiveTouches = activeCount

    if activeCount >= 3 {
        TouchTracker.glidePeakFingerCount = activeCount
        if prevActiveTouches < 3 {
            DispatchQueue.main.async { GestureEngine.shared.peakResetWorkItem?.cancel() }
        }
    }

    if activeCount < 3 && activeCount == TouchTracker.glideLastDispatchedCount { return 0 }
    TouchTracker.glideLastDispatchedCount = activeCount

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

    let frameData = TouchFrameData(count: activeCount, cx: cx, cy: cy, spread: spread, coherence: coherence)
    DispatchQueue.main.async { GestureEngine.shared.onTouches(frameData) }
    return 0
}
