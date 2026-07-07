import Foundation

enum SpeedClassifier {

    /// Grace window: below this elapsed time a not-yet-fast swipe stays unclassified,
    /// so a fast swipe whose first frames straddle the trigger distance isn't
    /// prematurely locked as normal/slow.
    static let graceSeconds: TimeInterval = 0.05

    /// Classifies swipe speed from average velocity at the moment the swipe
    /// crosses the trigger distance.
    ///
    /// - Parameters:
    ///   - totalDisplacement: centroid travel since movement start (trackpad widths)
    ///   - elapsedSeconds: wall-clock time since movement start
    ///   - configuredSpeeds: tiers that have rules for this direction/fingers
    ///   - slowMax: average speed at or below which a swipe is slow (widths/second)
    ///   - fastMin: average speed at or above which a swipe is fast (widths/second)
    /// - Returns: locked tier, or nil to defer within the grace window.
    static func classify(
        totalDisplacement: Float,
        elapsedSeconds: TimeInterval,
        configuredSpeeds: Set<GestureSpeed>,
        slowMax: Float,
        fastMin: Float
    ) -> GestureSpeed? {
        let activeSpeeds = configuredSpeeds.isEmpty ? Set([GestureSpeed.normal]) : configuredSpeeds
        if activeSpeeds.count == 1 {
            return activeSpeeds.first
        }

        let speed = totalDisplacement / Float(max(elapsedSeconds, 0.01))

        if activeSpeeds.contains(.fast), speed >= fastMin {
            return .fast
        }
        if elapsedSeconds < graceSeconds {
            return nil
        }
        if activeSpeeds.contains(.slow), speed <= slowMax {
            return .slow
        }
        if activeSpeeds.contains(.normal) {
            return .normal
        }
        // Only slow+fast configured and speed fell between them: nearest tier wins.
        return speed >= (slowMax + fastMin) / 2 ? .fast : .slow
    }

    // ─────────────────────────────────────────────
    // MARK: - Classic logic
    // ─────────────────────────────────────────────

    /// Rolling window for classic mode's velocity statistics.
    static let classicSampleCap = 8

    /// Appends a time-normalized velocity sample (trackpad-widths/second).
    static func appendVelocitySample(_ velocity: Float, to samples: inout [Float]) {
        guard velocity > 0 else { return }
        samples.append(velocity)
        if samples.count > classicSampleCap {
            samples.removeFirst(samples.count - classicSampleCap)
        }
    }

    /// Classic multi-signal classifier: locks swipe intent from distance, smoothed
    /// velocity, acceleration, and hold time. Kept as a selectable mode.
    ///
    /// Fixed relative to the original: samples arrive as widths/second (no 60fps
    /// assumption), elapsed runs from movement start rather than finger-down, and
    /// the window is 8 samples instead of 4.
    static func classifyClassic(
        velocitySamples: [Float],
        totalDisplacement: Float,
        elapsedSeconds: TimeInterval,
        configuredSpeeds: Set<GestureSpeed>,
        slowMax: Float,
        fastMin: Float,
        initialDistance: Float
    ) -> GestureSpeed? {
        let activeSpeeds = configuredSpeeds.isEmpty ? Set([GestureSpeed.normal]) : configuredSpeeds
        if activeSpeeds.count == 1 {
            return activeSpeeds.first
        }
        guard !velocitySamples.isEmpty else { return nil }

        let sorted = velocitySamples.sorted()
        let median = sorted[sorted.count / 2]
        let peak = sorted.last ?? 0
        let mean = velocitySamples.reduce(0, +) / Float(velocitySamples.count)
        let peakAcceleration = zip(velocitySamples.dropFirst(), velocitySamples).map { current, previous in
            max(0, current - previous)
        }.max() ?? 0

        let perSecond: Float = totalDisplacement / Float(max(elapsedSeconds, 0.05))
        let consistency = mean > 0 ? (peak - (sorted.first ?? 0)) / mean : 0

        let classificationHold: TimeInterval = 0.060
        let slowHold: TimeInterval = 0.090
        let fastReleaseWindow: TimeInterval = 0.145
        let slowDistance = initialDistance * 1.25
        let clearFastAcceleration = max((fastMin - slowMax) * 0.60, fastMin * 0.35)

        let hasExplosiveStart =
            peakAcceleration >= clearFastAcceleration ||
            peak >= fastMin * 1.35
        let isFastFlick =
            activeSpeeds.contains(.fast) &&
            elapsedSeconds <= fastReleaseWindow &&
            hasExplosiveStart &&
            (peak >= fastMin || perSecond >= fastMin * 0.90)

        if elapsedSeconds < classificationHold && !isFastFlick {
            return nil
        }

        if isFastFlick {
            return .fast
        }

        let looksControlledSlow =
            activeSpeeds.contains(.slow) &&
            median <= slowMax * 1.12 &&
            perSecond <= slowMax * 1.30 &&
            peak < fastMin * 0.80 &&
            peakAcceleration < clearFastAcceleration &&
            consistency < 2.20

        if looksControlledSlow && (elapsedSeconds < slowHold || totalDisplacement < slowDistance) {
            return nil
        }

        let isControlledSlow =
            looksControlledSlow &&
            elapsedSeconds >= slowHold &&
            totalDisplacement >= slowDistance

        if isControlledSlow {
            return .slow
        }

        let isClearFast =
            activeSpeeds.contains(.fast) &&
            elapsedSeconds <= 0.220 &&
            hasExplosiveStart &&
            (peak >= fastMin * 1.10 || perSecond >= fastMin)

        if isClearFast {
            return .fast
        }

        let nearSlowBoundary =
            activeSpeeds.contains(.slow) &&
            median <= slowMax * 1.30 &&
            perSecond <= slowMax * 1.55 &&
            peak < fastMin * 0.85

        if nearSlowBoundary && (elapsedSeconds < slowHold || totalDisplacement < slowDistance) {
            return nil
        }

        let nearFastBoundary =
            activeSpeeds.contains(.fast) &&
            elapsedSeconds <= 0.180 &&
            (peak >= fastMin * 0.85 || perSecond >= fastMin * 0.80)

        if nearFastBoundary && activeSpeeds.contains(.normal) {
            return nil
        }

        return activeSpeeds.contains(.normal) ? .normal : nil
    }
}
