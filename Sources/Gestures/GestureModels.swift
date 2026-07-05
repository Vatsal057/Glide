import Foundation
import Cocoa

// ─────────────────────────────────────────────
// MARK: - Touch frame data
// ─────────────────────────────────────────────

struct TouchFrameData {
    let count: Int32
    let cx: Float
    let cy: Float
    let spread: Float
    let coherence: Float
    /// Mean signed angular movement of the fingers around the centroid since the
    /// previous frame, in degrees. Positive = counterclockwise.
    var twist: Float = 0
}

// ─────────────────────────────────────────────
// MARK: - Gesture classification
// ─────────────────────────────────────────────

enum GestureKind { case unknown, swipe, pinch }

// ─────────────────────────────────────────────
// MARK: - Session state machine models
// ─────────────────────────────────────────────

struct CandidateData {
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
    /// Accumulated signed twist (degrees) — drives rotation gesture detection.
    var cumulativeTwist: Float = 0
}

struct SwipeTrackData {
    let startX: Float; let startY: Float
    var lastX: Float; var lastY: Float
    let fingers: Int; let startTime: TimeInterval
    let modifiersAtStart: CapturedModifiers
    var velocitySamples: [Float]
    var recentDeltas: [(dx: Float, dy: Float)]
    let initialSpread: Float
    var prevSpread: Float
    var cumulativeSpreadDelta: Float
    var continuousRefX: Float
    var continuousRefY: Float
    var lastContinuousActionTime: TimeInterval
    var continuousRule: GestureRule?
    var lockedSpeed: GestureSpeed?
}

struct SwitcherData {
    var refX: Float; var index: Int
    let fingerCount: Int
    let apps: [NSRunningApplication]
    let finderIndex: Int?   // position of windowless Finder, nil if Finder has windows
    let effectiveMin: Int   // left boundary (tightened if Finder is at left edge)
    let effectiveMax: Int   // right boundary (tightened if Finder is at right edge)
}

enum GesturePhase {
    case idle
    case candidate(CandidateData)
    case lockedSwipe(SwipeTrackData)
    case ignored
    case fired
    case continuousSwipe(SwipeTrackData)
    case switchingApps(SwitcherData)
}

// ─────────────────────────────────────────────
// MARK: - Reciprocal token
// ─────────────────────────────────────────────

struct ReciprocalToken {
    let inverseAction: GestureAction
    let fingers: Int
    let direction: GestureDirection
    let sourceRuleID: UUID
    let expiresAt: TimeInterval
}
import Foundation

extension GestureDirection {

    /// Determines the cardinal direction from a 0-360 degree angle.
    static func fromAngle(_ angle: Float, tolerance: Float) -> GestureDirection? {
        if angle >= (360 - tolerance) || angle < tolerance          { return .swipeRight }
        if angle >= (90 - tolerance)  && angle < (90 + tolerance)   { return .swipeUp }
        if angle >= (180 - tolerance) && angle < (180 + tolerance)  { return .swipeLeft }
        if angle >= (270 - tolerance) && angle < (270 + tolerance)  { return .swipeDown }
        return nil
    }

    /// Returns true if the direction matches the primary axis (horizontal/vertical)
    /// of the starting direction.
    func matchesAxis(of other: GestureDirection) -> Bool {
        switch other {
        case .swipeLeft, .swipeRight, .swipeLeftRight:
            return self == .swipeLeft || self == .swipeRight
        case .swipeUp, .swipeDown, .swipeUpDown:
            return self == .swipeUp || self == .swipeDown
        case .click, .forceClick, .tapHold, .rotateCW, .rotateCCW:
            return false
        }
    }
}
