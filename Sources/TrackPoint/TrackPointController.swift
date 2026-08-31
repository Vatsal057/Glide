import Cocoa

// ─────────────────────────────────────────────
// MARK: - TrackPointSample
// ─────────────────────────────────────────────

/// One contact, reduced to what the stick cares about. Built on the multitouch
/// thread, consumed on the main thread.
struct TrackPointSample {
    let id: Int32
    let x: Float
    let y: Float

    init(_ touch: GLDTouchPoint) {
        id = touch.identifier
        x = touch.x
        y = touch.y
    }
}

// ─────────────────────────────────────────────
// MARK: - TrackPointController
// ─────────────────────────────────────────────

/// Turns a corner of the trackpad into a pointing stick.
///
/// A trackpad is absolute: finger position maps to cursor position, so range is
/// capped by the size of the pad. A TrackPoint is relative: displacement maps to
/// cursor *velocity*, so a fingertip-sized patch reaches the whole screen and
/// the finger never has to lift and reset.
///
/// Lifecycle, driven entirely by `ingest`:
///
///   idle ──lone contact in zone──▶ arming ──held still past delay──▶ engaged
///                                    │                                  │
///                                    ├──pushed too far first──▶ rejected┤
///                                    ▼                                  ▼
///                                   idle ◀────────contact lifted────────┘
///
/// `arming` exists so an ordinary cursor drag that happens to start in the
/// corner is left alone: commit to the corner and it becomes a stick, sweep out
/// of it and macOS keeps the touch. Native cursor tracking is only suppressed
/// once engaged, so a rejected touch never loses any movement.
///
/// All methods run on the main thread.
final class TrackPointController {

    static let shared = TrackPointController()
    private init() {}

    private enum State {
        case idle
        /// Waiting out the activation delay. `anchor` is where the finger landed.
        case arming(id: Int32, anchor: CGPoint)
        /// This contact moved too far to be a stick; ignore it until it lifts.
        case rejected(id: Int32)
        case engaged(id: Int32, anchor: CGPoint, mode: TrackPointMode)

        /// The contact this feature is following, or -1. Published to the
        /// multitouch thread so frames keep arriving for it: without that the
        /// state machine would stop hearing about the finger it is waiting on.
        var trackedID: Int32 {
            switch self {
            case .idle:                  return -1
            case .arming(let id, _):     return id
            case .rejected(let id):      return id
            case .engaged(let id, _, _): return id
            }
        }
    }

    /// Normalized multitouch coordinates stretch the short axis: on a ~1.6:1 pad
    /// the same physical push reads 1.6× larger vertically. Scaling y by the
    /// inverse makes a push feel like the same push in every direction.
    private static let verticalScale = 0.625
    private static let tickInterval = 1.0 / 120.0
    /// Ceiling on a single integration step, so a stalled main thread can't
    /// discharge its whole backlog into one cursor jump.
    private static let maxStep = 0.05

    /// Kept in lockstep with the multitouch thread's view of what to follow, so
    /// the two can't drift apart on any path out of a session.
    private var state: State = .idle {
        didSet {
            // A trailing anchor rewrites `state` on most frames; only the contact
            // being followed needs publishing, and that rarely changes.
            let tracked = state.trackedID
            if tracked != oldValue.trackedID { TouchTracker.trackPointAnchoredID = tracked }
        }
    }
    private var lastSample: TrackPointSample?
    private var offset: CGPoint = .zero
    private var armTimer: DispatchWorkItem?
    private var driveTimer: DispatchSourceTimer?
    private var lastTick: TimeInterval = 0

    var isEngaged: Bool {
        if case .engaged = state { return true }
        return false
    }

    /// One finger drives the pointer; a second resting finger turns the stick into
    /// a scroller, the way a TrackPoint's middle button does. Three or more is a
    /// gesture and never reaches here.
    private func mode(forContacts contacts: Int) -> TrackPointMode {
        contacts >= 2 && Settings.shared.trackPoint.scrollEnabled ? .scroll : .pointer
    }

    // MARK: - Settings

    /// Publishes the zone to the multitouch thread and opens or closes the
    /// single-contact frame path in the C bridge. Call after any settings change
    /// and on engine start.
    func applySettings() {
        let settings = Settings.shared.trackPoint
        TouchTracker.updateTrackPointCache(enabled: settings.enabled,
                                           zone: settings.zone,
                                           reach: settings.zoneSize)
        // Gesture rules all need three fingers; the stick needs one. Only widen
        // the bridge's forwarding window while the feature is actually on.
        MultitouchBridge.shared.setMinimumContactCount(settings.enabled ? 1 : 3)
        if !settings.enabled { reset() }
    }

    /// Drops any session and returns the cursor to macOS.
    func reset() {
        cancelArmTimer()
        if isEngaged { releaseControl(playHaptic: false) }
        state = .idle
        lastSample = nil
        offset = .zero
    }

    // MARK: - Touch input

    /// - Parameters:
    ///   - candidate: a lone contact inside the zone, the only thing that may
    ///     start a session. Nil when there are other fingers down or none in the zone.
    ///   - tracked: the contact currently driving an engaged session, if still present.
    ///   - contacts: total active contacts this frame.
    func ingest(candidate: TrackPointSample?, tracked: TrackPointSample?, contacts: Int) {
        guard Settings.shared.trackPoint.enabled else {
            reset()
            return
        }
        if let sample = tracked ?? candidate { lastSample = sample }

        switch state {
        case .engaged(let id, let anchor, let activeMode):
            if contacts >= 3 {
                // Three fingers down is a gesture, not a stick. Hand the frame
                // back rather than steer the cursor through someone's swipe.
                // The contact stays rejected until it lifts, so releasing the
                // gesture doesn't silently re-engage under their fingers.
                releaseControl(playHaptic: false)
                state = .rejected(id: id)
                offset = .zero
            } else if let tracked, tracked.id == id {
                let wanted = mode(forContacts: contacts)
                if wanted != activeMode {
                    switchMode(to: wanted, at: tracked, id: id)
                } else {
                    updateOffset(from: tracked, anchor: anchor, id: id, mode: activeMode)
                }
            } else if let candidate {
                // The driving contact dropped out of the multitouch state and
                // came back under a fresh identifier (fingers that barely move
                // do this). Re-anchor instead of letting a stale offset fling
                // the cursor, and keep the session alive.
                reanchor(to: candidate)
            } else {
                releaseControl(playHaptic: true)
                state = .idle
                offset = .zero
            }

        case .arming(let id, let anchor):
            guard let candidate else {
                cancelArmTimer()
                state = contacts > 0 ? .rejected(id: id) : .idle
                return
            }
            guard candidate.id == id else {
                arm(candidate)
                return
            }
            let dx = CGFloat(candidate.x) - anchor.x
            let dy = CGFloat(candidate.y) - anchor.y
            let travelled = (dx * dx + dy * dy).squareRoot()
            if travelled > CGFloat(Settings.shared.trackPoint.activationMovement) {
                // Moving before committing means this is a normal swipe or drag.
                cancelArmTimer()
                state = .rejected(id: id)
            }

        case .rejected(let id):
            if let candidate, candidate.id != id { arm(candidate) }
            else if contacts == 0 { state = .idle }

        case .idle:
            if let candidate { arm(candidate) }
        }
    }

    /// Engine shutdown, sleep, or the feature being switched off.
    func engineWillStop() { reset() }

    // MARK: - State transitions

    private func arm(_ sample: TrackPointSample) {
        cancelArmTimer()
        let anchor = CGPoint(x: CGFloat(sample.x), y: CGFloat(sample.y))
        state = .arming(id: sample.id, anchor: anchor)
        offset = .zero

        let delay = Settings.shared.trackPoint.activationDelay
        // A motionless finger produces no further frames, so the transition out
        // of `arming` has to be driven by the clock rather than by input.
        let work = DispatchWorkItem { [weak self] in self?.engageIfStillArming(id: sample.id) }
        armTimer = work
        if delay <= 0 {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func engageIfStillArming(id: Int32) {
        guard case .arming(let armedID, _) = state, armedID == id else { return }
        guard let sample = lastSample, sample.id == id else { return }
        armTimer = nil

        // Anchor where the finger sits now, not where it landed: the small drift
        // allowed during the delay would otherwise read as a standing push and
        // creep the cursor the instant the stick engages.
        let startMode = mode(forContacts: 1)
        state = .engaged(id: id, anchor: CGPoint(x: CGFloat(sample.x), y: CGFloat(sample.y)), mode: startMode)
        offset = .zero

        prepareDriver(for: startMode)
        GestureEngine.shared.inputManager?.setTrackPointSuppression(true)
        startDriveTimer()
        playHaptic(.softTick)
        AppLogger.debug("[TrackPoint] Engaged in \(Settings.shared.trackPoint.zone.rawValue)")
    }

    /// Swaps what the stick drives without ending the session. Re-anchors so the
    /// new mode starts from neutral: carrying a full-scale pointer push straight
    /// into scrolling would launch the page the instant the second finger lands.
    private func switchMode(to newMode: TrackPointMode, at sample: TrackPointSample, id: Int32) {
        state = .engaged(id: id, anchor: CGPoint(x: CGFloat(sample.x), y: CGFloat(sample.y)), mode: newMode)
        offset = .zero
        prepareDriver(for: newMode)
        // The mode is invisible on screen, so it gets its own confirmation.
        playHaptic(.softTick)
        AppLogger.debug("[TrackPoint] Mode → \(newMode.rawValue)")
    }

    private func prepareDriver(for newMode: TrackPointMode) {
        switch newMode {
        case .pointer: CursorDriver.shared.begin()
        case .scroll:  ScrollDriver.shared.begin()
        }
    }

    private func reanchor(to sample: TrackPointSample) {
        state = .engaged(id: sample.id,
                         anchor: CGPoint(x: CGFloat(sample.x), y: CGFloat(sample.y)),
                         mode: mode(forContacts: 1))
        offset = .zero
    }

    /// Gives the cursor back to macOS. Leaves `state` to the caller, which knows
    /// whether the contact is gone or merely disqualified.
    private func releaseControl(playHaptic shouldPlay: Bool) {
        stopDriveTimer()
        GestureEngine.shared.inputManager?.setTrackPointSuppression(false)
        if shouldPlay { playHaptic(.softTick) }
        AppLogger.debug("[TrackPoint] Released")
    }

    private func cancelArmTimer() {
        armTimer?.cancel()
        armTimer = nil
    }

    /// Measures the push, and lets the anchor trail a finger that has pushed past
    /// full scale.
    ///
    /// A physical pointing stick cannot deflect beyond its socket — past that
    /// limit it simply reports "hard over in this direction". A fixed anchor has
    /// no such limit, and everything beyond full scale used to collapse to the
    /// same max-speed reading while the *direction* kept swinging wildly around a
    /// point the finger had long since left. Circling was the worst case: the
    /// finger orbits a centre that isn't the anchor, so the push raked from the
    /// dead zone to several times full scale and back once per revolution — the
    /// cursor stalled on the near side and raced on the far side.
    ///
    /// Clamping the push and dragging the anchor along behind it fixes that
    /// without touching the feel of a deliberate small push, which never reaches
    /// the limit: below full scale the anchor is perfectly still and fine control
    /// is exactly as before. Above it, the push settles into the direction the
    /// finger is actually travelling, so an orbiting finger yields a steady
    /// circle instead of a lopsided one.
    private func updateOffset(from sample: TrackPointSample, anchor: CGPoint, id: Int32, mode: TrackPointMode) {
        var push = CGPoint(x: CGFloat(sample.x) - anchor.x, y: CGFloat(sample.y) - anchor.y)
        let range = CGFloat(Settings.shared.trackPoint.pushRange)
        let magnitude = Self.correctedMagnitude(push)

        if magnitude > range, magnitude > 0 {
            let scale = range / magnitude
            push.x *= scale
            push.y *= scale
            state = .engaged(id: id,
                             anchor: CGPoint(x: CGFloat(sample.x) - push.x,
                                             y: CGFloat(sample.y) - push.y),
                             mode: mode)
        }
        offset = push

        // Frames only arrive while the finger moves, but the cursor has to start
        // gliding the instant the push crosses out of the dead zone — so re-arm the
        // drive timer here if `tick()` parked it. `startDriveTimer` resets the
        // integration clock, so the first step after a pause can't discharge a stale
        // interval into one cursor jump.
        if driveTimer == nil,
           magnitude > CGFloat(Settings.shared.trackPoint.deadZone) {
            startDriveTimer()
        }
    }

    /// Push magnitude with the trackpad's aspect ratio taken out, so a given
    /// physical distance reads the same in every direction.
    private static func correctedMagnitude(_ push: CGPoint) -> CGFloat {
        let x = Double(push.x)
        let y = Double(push.y) * verticalScale
        return CGFloat((x * x + y * y).squareRoot())
    }

    private func playHaptic(_ pattern: HapticPattern) {
        guard Settings.shared.trackPoint.hapticFeedback else { return }
        HapticEngine.shared.play(pattern)
    }

    // MARK: - Cursor drive loop

    private func startDriveTimer() {
        stopDriveTimer()
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.tickInterval,
                       repeating: Self.tickInterval,
                       leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        driveTimer = timer
        timer.resume()
    }

    private func stopDriveTimer() {
        driveTimer?.cancel()
        driveTimer = nil
    }

    private func tick() {
        guard case .engaged(_, _, let mode) = state else {
            stopDriveTimer()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(now - lastTick, Self.maxStep)
        lastTick = now
        guard elapsed > 0 else { return }

        let settings = Settings.shared.trackPoint
        let pushX = Double(offset.x)
        let pushY = Double(offset.y) * Self.verticalScale
        let magnitude = Double(Self.correctedMagnitude(offset))

        let deadZone = Double(settings.deadZone)
        guard magnitude > deadZone else {
            // Resting inside the dead zone: the cursor must not move, so the 120 Hz
            // timer has nothing left to do. Stop it and let `updateOffset` restart it
            // the moment the finger pushes back out. A *steady* push outside the dead
            // zone never trips this guard, so holding a deflection keeps the cursor
            // gliding without depending on new frames — only a finger settled on the
            // anchor stops the wake-ups, which is exactly when they were pure waste.
            stopDriveTimer()
            return
        }

        // Normalize the push to 0…1 of its useful range, then curve it. The
        // exponent is what makes a stick usable: near the anchor it crawls for
        // pixel work, at full push it crosses the screen.
        let span = max(Double(settings.pushRange) - deadZone, 0.001)
        let fraction = min((magnitude - deadZone) / span, 1.0)
        let topSpeed = Double(mode == .scroll ? settings.scrollSpeed : settings.maxSpeed)
        let step = topSpeed * pow(fraction, Double(settings.acceleration)) * elapsed

        let unitX = pushX / magnitude
        let unitY = pushY / magnitude

        switch mode {
        case .pointer:
            // Core Graphics y grows downward, the trackpad's grows up.
            CursorDriver.shared.move(dx: CGFloat(unitX * step), dy: CGFloat(-unitY * step))
        case .scroll:
            // Pushing up moves up through the document, the way a stick or a
            // scrollbar behaves rather than the way dragging content does.
            let direction = settings.invertScroll ? -1.0 : 1.0
            ScrollDriver.shared.scroll(vertical: unitY * step * direction,
                                       horizontal: -unitX * step * direction)
        }
    }
}
