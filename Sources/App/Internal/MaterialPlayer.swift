import Foundation

// ─────────────────────────────────────────────
// MARK: - MaterialPlayer
// ─────────────────────────────────────────────

/// Turns millimetres of finger travel into actuator pulses for one material.
///
/// Shared by every surface-feel producer. Keeps one small state record per
/// contact so each finger gets its own tooth phase, pressure calibration, and
/// burst rhythm. Everything here runs on the multitouch thread: no locks, no
/// main-thread hops, no per-frame allocations beyond dictionary bookkeeping.
final class MaterialPlayer {

    private struct ContactState {
        var accumulator = TickAccumulator()
        var lastX: Float = 0
        var lastY: Float = 0
        var hasLastPosition = false
        var strengthIndex = 0
        var ticksInBurst = 0
        var swallowedTeeth = 0
        // Pressure (Q1): rolling per-contact calibration of touch size.
        var sizeSmoothed: Float = 0
        var sizeMin: Float = 0
        var sizeMax: Float = 0
        var frameID: UInt64 = 0
    }

    /// Hard cap on tracked contacts (mirrors the NEXT-STEPS fixed-buffer rule).
    private static let maxContacts = 32

    private var contacts: [Int32: ContactState] = [:]
    private var frameID: UInt64 = 0
    private let engine = HapticEngine.shared

    /// Starts a new frame. Call once per MT frame, then `consume` once per
    /// contact, then `endFrame`.
    func beginFrame() {
        frameID &+= 1
    }

    /// Feeds one contact's new position (normalised 0...1 coordinates).
    func consume(contactID: Int32, x: Float, y: Float, size: Float,
                 mmPerUnitX: Double, mmPerUnitY: Double,
                 material: Material, intensity: Double, pressSizeScaling: Bool,
                 timestamp: TimeInterval) {
        var st = contacts[contactID] ?? ContactState()
        st.frameID = frameID

        // ── Pressure calibration: rolling per-contact min/max of touch size,
        //    adapting slowly so grip changes recalibrate within seconds.
        if !st.hasLastPosition {
            st.sizeSmoothed = size
            st.sizeMin = size
            st.sizeMax = size
        } else {
            let sm = st.sizeSmoothed + (size - st.sizeSmoothed) * 0.25
            var mn = min(st.sizeMin, sm)
            var mx = max(st.sizeMax, sm)
            mn += (sm - mn) * 0.002
            mx += (sm - mx) * 0.002
            st.sizeSmoothed = sm
            st.sizeMin = mn
            st.sizeMax = mx
        }

        // ── Travel in millimetres.
        var deltaMM = 0.0
        if st.hasLastPosition {
            let dx = Double(x - st.lastX) * mmPerUnitX
            let dy = Double(y - st.lastY) * mmPerUnitY
            deltaMM = (dx * dx + dy * dy).squareRoot()
        }
        st.lastX = x
        st.lastY = y
        st.hasLastPosition = true

        // ── Tooth for this material.
        var cfg = TickConfiguration()
        cfg.stepSize = max(material.toothMM, 0.5)
        cfg.maximumTickRate = max(material.maxTickRate, 1)
        cfg.maximumTicksPerSample = 3
        cfg.attenuationVelocity = 400  // fast swipes tick softer, not harder
        st.accumulator.configuration = cfg

        defer { contacts[contactID] = st }
        guard deltaMM > 0 else { return }

        // ── Jitter: perturb the fed distance so tooth spacing feels irregular.
        var fed = deltaMM
        if material.jitter > 0 {
            let j = (Double.random(in: 0...1) * 2 - 1) * material.jitter
            fed = max(deltaMM * (1 + j), 0)
        }

        let outcome = st.accumulator.consume(delta: fed, timestamp: timestamp,
                                             phase: .active)
        guard outcome.count > 0 else { return }

        // ── Burst: swallow teeth after each cluster to carve the silent gap.
        var emitCount = outcome.count
        if st.swallowedTeeth > 0 {
            let swallowed = min(emitCount, st.swallowedTeeth)
            st.swallowedTeeth -= swallowed
            emitCount -= swallowed
        }

        let strengths = material.effectiveStrengths
        for _ in 0..<emitCount {
            var strength = strengths[st.strengthIndex % strengths.count]
            st.strengthIndex += 1
            if pressSizeScaling {
                let pressure = pressure01(smoothed: st.sizeSmoothed,
                                          minimum: st.sizeMin, maximum: st.sizeMax)
                strength = pressureBiased(strength, pressure: pressure)
            }
            strength = intensityCapped(strength, intensity: intensity)
            if outcome.isAttenuated { strength = weakened(strength) }
            engine.pulse(strength)
        }

        if material.burst > 1 {
            st.ticksInBurst += emitCount
            if st.ticksInBurst >= material.burst {
                st.ticksInBurst = 0
                st.swallowedTeeth = max(material.burstGapTeeth, 1)
            }
        }
    }

    /// Ends the frame: drops contacts that lifted (didn't appear this frame).
    /// The common case (no lifts) leaves storage untouched.
    func endFrame() {
        let id = frameID
        var hasStale = false
        for state in contacts.values where state.frameID != id {
            hasStale = true
            break
        }
        if hasStale {
            contacts = contacts.filter { $0.value.frameID == id }
        }
        if contacts.count > Self.maxContacts {
            let keep = contacts.sorted { $0.value.frameID > $1.value.frameID }
                .prefix(Self.maxContacts)
            contacts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    /// Drops all contact state (all fingers lifted, or feature disabled).
    func reset() {
        contacts.removeAll(keepingCapacity: true)
    }

    // MARK: Strength shaping

    /// Normalised press 0...1 from the rolling size calibration.
    private func pressure01(smoothed: Float, minimum: Float, maximum: Float) -> Double {
        let span = maximum - minimum
        guard span > 0.0001 else { return 0.5 }
        return Double(min(max((smoothed - minimum) / span, 0), 1))
    }

    /// Firmer press shifts the pick one step stronger; light press weaker.
    /// The material's rhythm (strength cycle) is preserved.
    private func pressureBiased(_ s: HapticStrength, pressure: Double) -> HapticStrength {
        switch s {
        case .weak:   return pressure > 0.66 ? .medium : .weak
        case .medium: return pressure > 0.66 ? .strong : (pressure < 0.33 ? .weak : .medium)
        case .strong: return pressure < 0.33 ? .medium : .strong
        }
    }

    /// Intensity is a ceiling on how strong texture pulses may get.
    private func intensityCapped(_ s: HapticStrength, intensity: Double) -> HapticStrength {
        let ceiling: HapticStrength =
            intensity < 0.34 ? .weak : (intensity < 0.67 ? .medium : .strong)
        return min(s, ceiling)
    }

    /// Fast movement ticks softer rather than harder.
    private func weakened(_ s: HapticStrength) -> HapticStrength {
        switch s {
        case .weak:   return .weak
        case .medium: return .weak
        case .strong: return .medium
        }
    }
}
