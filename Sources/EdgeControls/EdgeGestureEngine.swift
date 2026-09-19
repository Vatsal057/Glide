import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TrackpadSurfaceSize
// ─────────────────────────────────────────────────────────────────────────────

struct TrackpadSurfaceSize: Equatable {
    var width: Double   // mm
    var height: Double  // mm

    /// Used only when the device will not report its own dimensions.
    static let `default` = TrackpadSurfaceSize(width: 157.8, height: 97.8)

    /// The real sensor size, straight from the device.
    ///
    /// Every edge setting is in millimetres so that the same number feels the same on
    /// any trackpad. Assuming a nominal size makes that a lie on any machine whose
    /// trackpad differs: a 6 mm margin quietly becomes 5 mm on a smaller pad, and the
    /// two axes scale by different amounts, so the setting means something different
    /// on the vertical edges than on the horizontal ones.
    /// Returns nil when the device will not answer, so callers can tell a real
    /// measurement from a fallback. A measured size that happens to equal the nominal
    /// one is otherwise indistinguishable from a failed query — which is exactly the
    /// false "device would not report" the diagnostics first printed on hardware where
    /// the query was working perfectly.
    static func measuredOrNil() -> TrackpadSurfaceSize? {
        var width = 0.0
        var height = 0.0
        guard GLDTGetSurfaceDimensions(&width, &height), width > 0, height > 0 else {
            return nil
        }
        return TrackpadSurfaceSize(width: width, height: height)
    }

    static func measured() -> TrackpadSurfaceSize { measuredOrNil() ?? .default }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeGestureEngine
//
// Detects 1-finger edge scrubs along Top, Bottom, Left, and Right edges.
// Uses TickAccumulator to quantize continuous finger travel into rate-limited,
// velocity-smoothed ticks driving native OSD bezels or App Switcher.
//
// Continuous actions (scrolling) are the exception: they read finger travel
// directly, bypassing the quantizer, and hold pointer suppression for the
// duration so the cursor stays put while the content moves.
// ─────────────────────────────────────────────────────────────────────────────

final class EdgeGestureEngine {

    struct Configuration {
        var isEnabled: Bool = true
        var topAction: EdgeAction = .none
        var bottomAction: EdgeAction = .none
        var leftAction: EdgeAction = .brightness
        var rightAction: EdgeAction = .volume
        var marginMm: Double = 12.0
        var activationTravelMm: Double = 4.0

        /// Fraction of each axis the TrackPoint's corner zone claims, or 0 when
        /// TrackPoint is not corner-activated. Edge gestures keep clear of it so the
        /// two features can't both lay claim to the same touch.
        var trackPointCornerZone: Double = 0
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

        /// Where the cursor sat when the finger landed, so the drift it picks up
        /// before the gesture is recognised can be undone on commit.
        let cursorOrigin: CGPoint?
    }

    // MARK: - Activation tuning

    /// How much straighter than sideways the motion must be to count as an edge
    /// slide. At 2.0, travel along the edge has to be at least twice any drift
    /// across it, so anything within about 27° of the edge qualifies.
    private static let directionPurityRatio = 2.0

    /// Inward drift tolerated before the gesture commits. A finger heading into the
    /// pad is steering the cursor, and it should keep doing so.
    private static let maxPreArmPerpendicularMm = 3.0

    /// Absolute floor on how far from an edge's ends a gesture may start, applied
    /// even when the margin is small. Corners are shared ground.
    private static let minCornerExclusionMm = 12.0

    /// Extra inward room a gesture keeps once it has committed.
    ///
    /// Entering is deliberately strict, to stay out of the way of cursor work.
    /// Staying should not be: by then the finger has already proved intent with a
    /// straight slide along the edge, and the cost of being wrong has flipped — a
    /// gesture dropped halfway is worse than one held a little too long.
    private static let postCommitSlackMm = 10.0

    var config: Configuration
    var surfaceSize: TrackpadSurfaceSize = .default

    /// Tracks touch identifiers that did not originate at an edge,
    /// preventing normal cursor movements from turning into edge controls.
    private var disqualifiedTouchIds: Set<Int32> = []

    private var activeGesture: ActiveGesture?

    /// Currently active edge being scrubbed (observed by preferences diagram).
    private(set) var activeEdge: TrackpadPhysicalEdge?

    /// Whether this engine currently holds pointer suppression for a committed edge
    /// gesture. Tracked separately from `activeGesture` so the claim is always
    /// released, even on the paths that drop the gesture without inspecting it.
    /// Readable so the `--test-edge-controls` suite can assert it is handed back.
    private(set) var isSuppressingPointer = false

    /// Whether a gesture has passed the activation gate and is driving its action.
    ///
    /// Deliberately separate from `isSuppressingPointer`: the pointer freezes as soon
    /// as the finger lands in the strip, while committing takes a deliberate slide.
    /// Conflating the two is what let an earlier version of the test suite believe it
    /// was checking the activation gate when it was really checking suppression.
    var hasCommittedGesture: Bool { activeGesture?.isSwiping == true }

    init(config: Configuration = Configuration()) {
        self.config = config
    }

    func reset() {
        endPointerSuppression()
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
            switcherSession: nil,
            cursorOrigin: CGEvent(source: nil)?.location
        )
        activeEdge = edge

        // Freeze the pointer the moment the finger lands in the strip — not when the
        // gesture later commits.
        //
        // Waiting for the commit leaves the activation travel unguarded, and those few
        // millimetres are enough cursor movement to be obvious. It is invisible on the
        // bottom edge only because macOS largely ignores cursor contribution from
        // contacts right at the rim, which is also why apps that never suppress at all
        // appear to behave: they are riding that, and it does not extend as far up the
        // other three edges.
        //
        // The rule is therefore positional, matching what a user actually perceives:
        // inside an assigned strip the pointer holds still, and it comes back the
        // moment the finger heads inward. Only touches that *originated* in the strip
        // qualify, so sweeping in from the middle of the pad keeps steering the cursor.
        beginPointerSuppression()
    }

    private func advance(current: ActiveGesture, touch: GLDTouchPoint, currentPos: CGPoint, timestamp: TimeInterval) {
        // 1. Edge proximity, with hysteresis: it takes less to keep a gesture than to
        // start one.
        //
        // Fingers do not track straight. Sliding along an edge, especially a long one
        // or the top where the hand has to reach over, wanders several millimetres
        // inward — easily more than a tight margin. Holding a committed gesture to the
        // same threshold it entered on drops it mid-slide, and because dropping it
        // also releases the pointer, the visible symptom is the cursor lurching back
        // into life partway through. Once the gesture has earned its commit the
        // intent is not in doubt, so it gets meaningfully more room.
        let retainDepth = current.isSwiping
            ? config.marginMm + Self.postCommitSlackMm
            : config.marginMm
        guard isWithinEdge(currentPos, edge: current.edge, depth: retainDepth) else {
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

        // 3. Activation gate. Nothing fires, and the pointer is not touched, until
        // the finger has clearly committed to travelling *along* the edge.
        //
        // Two independent conditions, because distance alone is not enough: a
        // finger crossing the pad diagonally from near an edge racks up plenty of
        // along-axis travel while obviously steering the cursor. Requiring the
        // motion to be mostly parallel to the edge as well is what separates the
        // two, and it is cheap — both numbers are already measured.
        if !updated.isSwiping {
            // Any real inward excursion before committing means cursor work.
            // Checked in absolute terms so it catches a straight inward push, which
            // has no along-axis travel for a ratio to bite on.
            if abs(perpAxisMm) > Self.maxPreArmPerpendicularMm {
                disqualifiedTouchIds.insert(touch.identifier)
                reset()
                return
            }

            let travelledFarEnough = abs(alongAxisMm) >= config.activationTravelMm
            let travelledStraightEnough =
                abs(alongAxisMm) >= Self.directionPurityRatio * abs(perpAxisMm)

            guard travelledFarEnough && travelledStraightEnough else {
                // Not committed yet. Keep watching rather than disqualifying: a slow
                // or slightly curved start still becomes a clean edge slide, and the
                // absolute cap above is what rejects genuine cursor motion.
                activeGesture = updated
                return
            }

            updated.isSwiping = true

            // Suppression is already in place from touch-down, so nothing should have
            // moved. This is a backstop: enabling a tap is not instantaneous, so a
            // frame or two of native motion can slip through before it bites, and this
            // puts the cursor back where the finger landed.
            if let origin = updated.cursorOrigin {
                CursorDriver.shared.warp(to: origin)
            }

            if updated.action == .appSwitcher && updated.switcherSession == nil {
                let switcher = EdgeAppSwitcherSession()
                let movingForward = alongAxisMm > 0
                if switcher.begin(movingForward: movingForward) {
                    updated.switcherSession = switcher
                }
            }
            if updated.action == .scroll {
                EdgeScrollSession.shared.begin(pointsPerMm: Settings.shared.edgeControls.scrollSpeed)
            }
        }

        guard abs(travelMm) > 0.0001 else {
            activeGesture = updated
            return
        }

        // 4. Continuous actions map travel straight onto output and skip the tick
        // quantizer entirely — see EdgeAction.isContinuous for why.
        if updated.action.isContinuous {
            feedScroll(travelMm: travelMm)
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
            if updated.action.wantsHapticTicks {
                HapticEngine.shared.play(outcome.isAttenuated ? .softTick : .tap)
            }
        }

        activeGesture = updated
    }

    // MARK: - Pointer Suppression

    /// Freezes the system cursor for the duration of a committed edge gesture.
    ///
    /// Edge controls run on a single contact, so the finger working the slider is
    /// the same one macOS reads as pointer movement: without this the cursor drifts
    /// off toward whichever screen edge you are sliding along. For scrolling it also
    /// decides *where* the scroll lands, since wheel events go to the window under
    /// the pointer — freezing it keeps the scroll on the window it started over.
    ///
    /// `ScrollDriver` and `CursorDriver` stamp their events with
    /// `CursorDriver.syntheticMarker`, which is what the suppression tap passes
    /// through, so Glide's own output survives while native motion is swallowed.
    private func beginPointerSuppression() {
        guard !isSuppressingPointer else { return }
        isSuppressingPointer = true
        let manager = GestureEngine.shared.inputManager
        manager?.setPointerSuppression(true, owner: .edgeControls)
        // Logged with the outcome, not just the request: "asked for suppression" and
        // "the pointer is actually frozen" are different claims, and only the second
        // one is what the user sees.
        AppLogger.debug("[Edge] committed on \(activeEdge?.rawValue ?? "?") — "
                        + "manager: \(manager == nil ? "MISSING" : "ok"), "
                        + "tap active: \(manager?.trackPointSuppressionEnabled ?? false)")
    }

    /// Hands the pointer back and lets any scroll coast out. Suppression is dropped
    /// immediately rather than held for the momentum: the finger is already off the
    /// trackpad by then, so there is no native pointer motion left to swallow.
    private func endPointerSuppression() {
        guard isSuppressingPointer else { return }
        isSuppressingPointer = false
        GestureEngine.shared.inputManager?.setPointerSuppression(false, owner: .edgeControls)
        EdgeScrollSession.shared.end(momentum: Settings.shared.edgeControls.scrollMomentum)
        AppLogger.debug("[Edge] released — pointer returned")
    }

    /// Vertical scroll points for one frame of travel along an edge.
    ///
    /// Every edge scrolls vertically, including the top and bottom. A horizontal
    /// rim reads as a forward/back strip rather than a horizontal scrollbar, and
    /// vertical is what people actually want to scroll, so `travelMm` is measured
    /// along whichever edge is in use and always drives the vertical axis.
    ///
    /// Direction matches the system's natural scrolling: sliding up a side edge —
    /// or right along a top or bottom edge — moves *forward* through the document,
    /// the way content follows your fingers on a two-finger scroll. `invertScroll`
    /// flips it to the scrollbar convention for anyone who prefers that.
    ///
    /// Pure and returned rather than posted so the sign convention — easy to get
    /// backwards across two coordinate spaces — can be checked by the
    /// `--test-edge-controls` suite without emitting real events.
    static func scrollPoints(travelMm: Double, settings: EdgeControlsSettings) -> Double {
        let direction = settings.invertScroll ? -1.0 : 1.0
        // ScrollDriver's +vertical goes toward the *start* of the document, so
        // moving forward through it is negative.
        return -travelMm * settings.scrollSpeed * direction
    }

    private func feedScroll(travelMm: Double) {
        let points = Self.scrollPoints(travelMm: travelMm, settings: Settings.shared.edgeControls)
        EdgeScrollSession.shared.addTravel(points: points)
    }

    // MARK: - Action Dispatch

    private func dispatchAction(_ action: EdgeAction, directionPositive: Bool, session: EdgeAppSwitcherSession?) {
        switch action {
        case .none:
            break
        case .scroll:
            // Continuous: applied in `advance` without passing through ticks.
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

    /// Picks the edge a touch belongs to, or nil if it belongs to none.
    ///
    /// Corners are where the trouble is: with any meaningful margin the four zones
    /// overlap there, "which edge is this?" has no right answer, and it is also where
    /// the TrackPoint's corner activation lives. So corners are refused outright, and
    /// because the exclusion is never shallower than the margin that alone guarantees
    /// at most one edge can qualify. Picking the nearest is then just a deterministic
    /// tie-break rather than the thing doing the work.
    private func detectEdge(for point: CGPoint, depth: Double) -> (TrackpadPhysicalEdge, EdgeAction)? {
        let edgesToCheck: [(TrackpadPhysicalEdge, EdgeAction)] = [
            (.top, config.topAction),
            (.bottom, config.bottomAction),
            (.left, config.leftAction),
            (.right, config.rightAction)
        ]

        var best: (edge: TrackpadPhysicalEdge, action: EdgeAction, distance: Double)?
        for (edge, action) in edgesToCheck {
            guard action != .none else { continue }
            let distance = distanceToEdgeMm(point, edge: edge)
            guard distance <= depth else { continue }
            guard distanceFromEdgeEndsMm(point, edge: edge) >= cornerExclusionMm(for: edge, depth: depth)
            else { continue }
            if best == nil || distance < best!.distance {
                best = (edge, action, distance)
            }
        }
        guard let best else { return nil }
        return (best.edge, best.action)
    }

    /// How far a gesture must start from either end of an edge.
    ///
    /// The floor is `depth` itself, which is what makes the edge zones provably
    /// disjoint: a point within `depth` of one edge and at least `depth` from that
    /// edge's ends cannot also be within `depth` of a perpendicular edge. On top of
    /// that sits an absolute minimum, and the TrackPoint's corner reach along this
    /// edge's own axis when corner activation is in use.
    private func cornerExclusionMm(for edge: TrackpadPhysicalEdge, depth: Double) -> Double {
        let alongLength = edge.isHorizontal ? surfaceSize.width : surfaceSize.height
        var exclusion = max(Self.minCornerExclusionMm, depth)
        if config.trackPointCornerZone > 0 {
            exclusion = max(exclusion, config.trackPointCornerZone * alongLength)
        }
        // Never eat the whole edge, however the settings are combined.
        return min(exclusion, alongLength * 0.4)
    }

    /// Inward distance from `edge`, in millimetres.
    private func distanceToEdgeMm(_ point: CGPoint, edge: TrackpadPhysicalEdge) -> Double {
        switch edge {
        case .left:   return Double(point.x) * surfaceSize.width
        case .right:  return (1.0 - Double(point.x)) * surfaceSize.width
        case .bottom: return Double(point.y) * surfaceSize.height
        case .top:    return (1.0 - Double(point.y)) * surfaceSize.height
        }
    }

    /// Distance to the nearer end of `edge`, measured along it.
    private func distanceFromEdgeEndsMm(_ point: CGPoint, edge: TrackpadPhysicalEdge) -> Double {
        if edge.isHorizontal {
            let x = Double(point.x) * surfaceSize.width
            return min(x, surfaceSize.width - x)
        }
        let y = Double(point.y) * surfaceSize.height
        return min(y, surfaceSize.height - y)
    }

    /// Whether a point is still close enough to `edge` to keep a gesture alive.
    /// Deliberately has no corner rule: sliding along an edge *into* a corner is a
    /// normal way to finish a scrub, and cancelling there would feel arbitrary.
    private func isWithinEdge(_ point: CGPoint, edge: TrackpadPhysicalEdge, depth: Double) -> Bool {
        distanceToEdgeMm(point, edge: edge) <= depth
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
        case .none, .scroll:
            // Continuous or inert: the accumulator is built but never consulted.
            break
        }
        return cfg
    }
}
