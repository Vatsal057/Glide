import Foundation

enum SpeedClassifier {

    /// Rolling window of recent per-frame centroid displacements (movement-gated in candidate phase).
    static func appendVelocitySample(_ distance: Float, to samples: inout [Float], tuning: GestureTuning) {
        guard distance > 0 else { return }
        samples.append(distance)
        let cap = tuning.speedSampleCount
        if samples.count > cap {
            samples.removeFirst(samples.count - cap)
        }
    }

    /// Classifies and locks swipe intent from distance, smoothed velocity, acceleration, and hold time.
    static func classifySpeedIntent(
        velocitySamples: [Float],
        totalDisplacement: Float,
        elapsedSeconds: TimeInterval,
        configuredSpeeds: Set<GestureSpeed>,
        tuning: GestureTuning
    ) -> GestureSpeed? {
        let activeSpeeds = configuredSpeeds.isEmpty ? Set([GestureSpeed.normal]) : configuredSpeeds
        if activeSpeeds.count == 1 {
            return activeSpeeds.first ?? .normal
        }

        let slowFrame = tuning.slowVelocityThreshold
        let fastFrame = tuning.fastVelocityThreshold
        let initialDistance = tuning.initialThreshold
        let fps: Float = 60
        let slowPerSecond = slowFrame * fps
        let fastPerSecond = fastFrame * fps

        guard !velocitySamples.isEmpty else { return nil }
        let sorted = velocitySamples.sorted()
        let medianFrame: Float = {
            return sorted[sorted.count / 2]
        }()
        let peakFrame = velocitySamples.max() ?? 0
        let meanFrame = velocitySamples.reduce(0, +) / Float(velocitySamples.count)
        let peakAcceleration = zip(velocitySamples.dropFirst(), velocitySamples).map { current, previous in
            max(0, current - previous)
        }.max() ?? 0

        let perSecond: Float = totalDisplacement / Float(max(elapsedSeconds, 0.05))
        let consistency = meanFrame > 0 ? (peakFrame - (sorted.first ?? 0)) / meanFrame : 0

        let classificationHold: TimeInterval = 0.060
        let slowHold: TimeInterval = 0.090
        let fastReleaseWindow: TimeInterval = 0.145
        let slowDistance = initialDistance * 1.25
        let clearFastAcceleration = max((fastFrame - slowFrame) * 0.60, fastFrame * 0.35)

        let hasExplosiveStart =
            peakAcceleration >= clearFastAcceleration ||
            peakFrame >= fastFrame * 1.35
        let isFastFlick =
            activeSpeeds.contains(.fast) &&
            elapsedSeconds <= fastReleaseWindow &&
            hasExplosiveStart &&
            (peakFrame >= fastFrame || perSecond >= fastPerSecond * 0.90)

        if elapsedSeconds < classificationHold && !isFastFlick {
            return nil
        }

        if isFastFlick {
            return .fast
        }

        let looksControlledSlow =
            activeSpeeds.contains(.slow) &&
            medianFrame <= slowFrame * 1.12 &&
            perSecond <= slowPerSecond * 1.30 &&
            peakFrame < fastFrame * 0.80 &&
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
            (peakFrame >= fastFrame * 1.10 || perSecond >= fastPerSecond)

        if isClearFast {
            return .fast
        }

        let nearSlowBoundary =
            activeSpeeds.contains(.slow) &&
            medianFrame <= slowFrame * 1.30 &&
            perSecond <= slowPerSecond * 1.55 &&
            peakFrame < fastFrame * 0.85

        if nearSlowBoundary && (elapsedSeconds < slowHold || totalDisplacement < slowDistance) {
            return nil
        }

        let nearFastBoundary =
            activeSpeeds.contains(.fast) &&
            elapsedSeconds <= 0.180 &&
            (peakFrame >= fastFrame * 0.85 || perSecond >= fastPerSecond * 0.80)

        if nearFastBoundary && activeSpeeds.contains(.normal) {
            return nil
        }

        return .normal
    }
}
