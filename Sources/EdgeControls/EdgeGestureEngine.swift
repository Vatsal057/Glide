import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TrackpadSurfaceSize
// ─────────────────────────────────────────────────────────────────────────────

struct TrackpadSurfaceSize: Equatable {
    var width: Double   // mm
    var height: Double  // mm

    /// Standard dimensions of modern MacBook Pro / Air trackpads.
    static let `default` = TrackpadSurfaceSize(width: 157.8, height: 97.8)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeGestureEngine
//
// Detects 1-finger edge scrubs along Top, Bottom, Left, and Right edges.
// Uses TickAccumulator to quantize continuous finger travel into rate-limited,
// velocity-smoothed ticks driving native OSD bezels or App Switcher.
// ─────────────────────────────────────────────────────────────────────────────

final class EdgeGestureEngine {

    struct Configuration {
        var isEnabled: Bool = true
        var topAction: EdgeAction = .none
        var bottomAction: EdgeAction = .none
        var leftAction: EdgeAction = .brightness
        var rightAction: EdgeAction = .volume
        var marginMm: Double = 8.0
    }

    private struct ActiveGesture {
        let touchId: Int32
        let edge: TrackpadPhysicalEdge
        let action: EdgeAction
        let startPosition: CGPoint
        var lastPosition: CGPoint
        var isSwiping: Bool
        let accumulator: TickAccumulator
        var switcherSession: EdgeAppSwitcherSession?
    }

    var config: Configuration
    var surfaceSize: TrackpadSurfaceSize = .default

    /// Tracks touch identifiers that did not originate at an edge,
    /// preventing normal cursor movements from turning into edge controls.
    private var disqualifiedTouchIds: Set<Int32> = []

    private var activeGesture: ActiveGesture?

    /// Currently active edge being scrubbed (observed by preferences diagram).
    private(set) var activeEdge: TrackpadPhysicalEdge?

    init(config: Configuration = Configuration()) {
        self.config = config
    }

    func reset() {
        if let current = activeGesture, current.isSwiping, current.action == .appSwitcher {
            current.switcherSession?.cancel()
        }
        activeGesture = nil
        activeEdge = nil
    }

    // MARK: - Frame ingestion

    func consume(touch: GLDTouchPoint?, contacts: Int, timestamp: TimeInterval) {
        guard config.isEnabled else {
            if activeGesture != nil { reset() }
            disqualifiedTouchIds.removeAll(keepingCapacity: true)
            return
        }

        // Edge controls strictly require exactly 1 contact.
        // 2 contacts is scroll/pinch, 3+ contacts is Glide gesture.
        guard contacts == 1, let touch else {
            if let current = activeGesture {
                if current.isSwiping && current.action == .appSwitcher {
                    current.switcherSession?.commit()
                }
                reset()
            }
            disqualifiedTouchIds.removeAll(keepingCapacity: true)
            return
        }

        if disqualifiedTouchIds.contains(touch.identifier) {
            return
        }

        let currentPos = CGPoint(x: CGFloat(touch.x), y: CGFloat(touch.y))

        if let current = activeGesture, current.touchId == touch.identifier {
            advance(current: current, touch: touch, currentPos: currentPos, timestamp: timestamp)
        } else {
            // Touch must originate at the edge to be considered.
            if activeGesture != nil { reset() }
            beginIfNeeded(touch: touch, currentPos: currentPos, timestamp: timestamp)
        }
    }

    // MARK: - Gesture Lifecycle

    private func beginIfNeeded(touch: GLDTouchPoint, currentPos: CGPoint, timestamp: TimeInterval) {
        // Touch must land within the edge margin (touching the edge)
        guard let (edge, action) = detectEdge(for: currentPos, depth: config.marginMm),
              action != .none else {
            // Touch landed away from the edge; disqualify for its entire lifetime
            disqualifiedTouchIds.insert(touch.identifier)
            return
        }

        let tickConfig = makeTickConfiguration(for: action)
        let accumulator = TickAccumulator(configuration: tickConfig)

        activeGesture = ActiveGesture(
            touchId: touch.identifier,
            edge: edge,
            action: action,
            startPosition: currentPos,
            lastPosition: currentPos,
            isSwiping: false,
            accumulator: accumulator,
            switcherSession: nil
        )
        activeEdge = edge
    }

    private func advance(current: ActiveGesture, touch: GLDTouchPoint, currentPos: CGPoint, timestamp: TimeInterval) {
        // 1. Strict edge proximity: must remain near the edge ("touching it").
        // Moving further inward than marginMm immediately terminates the gesture.
        guard isWithinEdge(currentPos, edge: current.edge, depth: config.marginMm) else {
            if current.isSwiping && current.action == .appSwitcher {
                current.switcherSession?.commit()
            }
            disqualifiedTouchIds.insert(touch.identifier)
            reset()
            return
        }

        // 2. Measure movement along the edge and perpendicular to the edge
        let alongAxisMm: Double
        let perpAxisMm: Double
        let travelMm: Double

        if current.edge.isHorizontal {
            alongAxisMm = Double(currentPos.x - current.startPosition.x) * surfaceSize.width
            perpAxisMm = Double(currentPos.y - current.startPosition.y) * surfaceSize.height
            travelMm = Double(currentPos.x - current.lastPosition.x) * surfaceSize.width
        } else {
            alongAxisMm = Double(currentPos.y - current.startPosition.y) * surfaceSize.height
            perpAxisMm = Double(currentPos.x - current.startPosition.x) * surfaceSize.width
            travelMm = Double(currentPos.y - current.lastPosition.y) * surfaceSize.height
        }

        // If the finger moves inward toward trackpad center rather than along the edge,
        // it is a cursor drag or inward motion, not an edge swipe.
        if abs(perpAxisMm) > abs(alongAxisMm) + 1.5 {
            disqualifiedTouchIds.insert(touch.identifier)
            reset()
            return
        }

        var updated = current
        updated.lastPosition = currentPos

        // 3. Swipe threshold: require intentional motion along the edge (>= 2.0 mm)
        // before firing any ticks or opening App Switcher.
        if !updated.isSwiping {
            let swipeThresholdMm = 2.0
            if abs(alongAxisMm) >= swipeThresholdMm {
                updated.isSwiping = true
                if updated.action == .appSwitcher && updated.switcherSession == nil {
                    let switcher = EdgeAppSwitcherSession()
                    let movingForward = alongAxisMm > 0
                    if switcher.begin(movingForward: movingForward) {
                        updated.switcherSession = switcher
                    }
                }
            } else {
                activeGesture = updated
                return
            }
        }

        guard abs(travelMm) > 0.0001 else {
            activeGesture = updated
            return
        }

        let outcome = updated.accumulator.consume(
            delta: travelMm,
            timestamp: timestamp,
            phase: .active
        )

        if outcome.count > 0 {
            let isPositive = travelMm > 0
            for _ in 0..<outcome.count {
                dispatchAction(updated.action, directionPositive: isPositive, session: updated.switcherSession)
            }
            if updated.action != .appSwitcher {
                HapticEngine.shared.play(outcome.isAttenuated ? .softTick : .tap)
            }
        }

        activeGesture = updated
    }

    private func dispatchAction(_ action: EdgeAction, directionPositive: Bool, session: EdgeAppSwitcherSession?) {
        switch action {
        case .none:
            break
        case .volume:
            SystemActions.sendMediaKey(directionPositive ? .volumeUp : .volumeDown)
        case .brightness:
            SystemActions.sendMediaKey(directionPositive ? .brightnessUp : .brightnessDown)
        case .keyboardBacklight:
            SystemActions.sendMediaKey(directionPositive ? .illuminationUp : .illuminationDown)
        case .appSwitcher:
            session?.step(forward: directionPositive)
        case .microphone:
            let mic = AudioDeviceVolume.defaultInput()
            if let current = mic.read() {
                let next = current + (directionPositive ? (1.0 / 16.0) : -(1.0 / 16.0))
                mic.write(next)
            }
        case .nightShift:
            NightShiftAdapter.shared.adjust(deltaSteps: directionPositive ? 1.0 : -1.0)
        }
    }

    // MARK: - Geometry & Edge Detection

    private func detectEdge(for point: CGPoint, depth: Double) -> (TrackpadPhysicalEdge, EdgeAction)? {
        let edgesToCheck: [(TrackpadPhysicalEdge, EdgeAction)] = [
            (.top, config.topAction),
            (.bottom, config.bottomAction),
            (.left, config.leftAction),
            (.right, config.rightAction)
        ]

        for (edge, action) in edgesToCheck {
            guard action != .none else { continue }
            if isWithinEdge(point, edge: edge, depth: depth) {
                return (edge, action)
            }
        }
        return nil
    }

    private func isWithinEdge(_ point: CGPoint, edge: TrackpadPhysicalEdge, depth: Double) -> Bool {
        switch edge {
        case .left:
            return Double(point.x) * surfaceSize.width <= depth
        case .right:
            return (1.0 - Double(point.x)) * surfaceSize.width <= depth
        case .bottom:
            return Double(point.y) * surfaceSize.height <= depth
        case .top:
            return (1.0 - Double(point.y)) * surfaceSize.height <= depth
        }
    }

    private func makeTickConfiguration(for action: EdgeAction) -> TickConfiguration {
        var cfg = TickConfiguration.default
        switch action {
        case .volume, .brightness, .keyboardBacklight, .microphone:
            // ~70mm travel for 16 notches => ~4.375mm per tick
            cfg.stepSize = 4.5
            cfg.maximumTickRate = 24.0
            cfg.attenuationVelocity = 160.0
        case .appSwitcher:
            // ~12mm travel per app step for distinct, controllable scrubbing
            cfg.stepSize = 12.0
            cfg.maximumTickRate = 12.0
            cfg.attenuationVelocity = 200.0
        case .nightShift:
            cfg.stepSize = 6.0
            cfg.maximumTickRate = 20.0
            cfg.attenuationVelocity = 160.0
        case .none:
            break
        }
        return cfg
    }
}
