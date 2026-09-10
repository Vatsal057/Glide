import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TickAccumulator
//
// Converts a stream of continuous movement deltas into discrete notches/ticks.
// Used by Edge Controls to turn millimetres of finger travel along an edge
// into quantized adjustments and haptic feedback.
// ─────────────────────────────────────────────────────────────────────────────

enum GestureMovementPhase: Equatable {
    case active
    case coasting
    case ended
}

struct TickConfiguration: Equatable {
    /// Distance (in mm or units) between two ticks while moving slowly.
    var stepSize: Double = 8.0

    /// Rate ceiling in ticks per second to prevent unpleasant buzzing.
    var maximumTickRate: Double = 24.0

    /// Extra step widening applied while movement coasts.
    var coastingStepMultiplier: Double = 2.0

    /// Weight given to the newest sample when smoothing velocity (0...1).
    var velocitySmoothing: Double = 0.3

    /// Speed above which ticks switch to softer intensity.
    var attenuationVelocity: Double = 220.0

    /// Idle gap after which accumulated state is reset.
    var idleTimeout: TimeInterval = 0.25

    /// Max ticks dispatched per single sample frame.
    var maximumTicksPerSample: Int = 2

    static let `default` = TickConfiguration()

    var minimumTickInterval: TimeInterval {
        1.0 / (maximumTickRate * 1.5)
    }
}

struct TickOutcome: Equatable {
    var count: Int = 0
    var isAttenuated: Bool = false

    static let none = TickOutcome()
}

final class TickAccumulator {
    var configuration: TickConfiguration

    private var accumulator: Double = 0
    private var smoothedVelocity: Double = 0
    private var lastSampleTime: TimeInterval?
    private var lastTickTime: TimeInterval?

    init(configuration: TickConfiguration = .default) {
        self.configuration = configuration
    }

    func reset() {
        accumulator = 0
        smoothedVelocity = 0
        lastSampleTime = nil
        lastTickTime = nil
    }

    func consume(delta: Double, timestamp: TimeInterval, phase: GestureMovementPhase) -> TickOutcome {
        guard phase != .ended else {
            reset()
            return .none
        }

        let elapsed = lastSampleTime.map { timestamp - $0 } ?? .infinity
        lastSampleTime = timestamp

        if elapsed > configuration.idleTimeout {
            accumulator = 0
            smoothedVelocity = 0
            lastTickTime = nil
        }

        guard delta != 0 else { return .none }

        if accumulator != 0, signum(accumulator) != signum(delta) {
            accumulator = 0
        }
        accumulator += delta

        updateVelocity(delta: delta, elapsed: elapsed)

        let step = currentStep(for: phase)
        guard abs(accumulator) >= step else { return .none }

        if let lastTickTime, timestamp - lastTickTime < configuration.minimumTickInterval {
            accumulator = step * signum(accumulator)
            return .none
        }

        var count = 0
        while abs(accumulator) >= step, count < configuration.maximumTicksPerSample {
            accumulator -= step * signum(accumulator)
            count += 1
        }

        if abs(accumulator) > step {
            accumulator = step * signum(accumulator)
        }

        lastTickTime = timestamp
        let isFast = smoothedVelocity >= configuration.attenuationVelocity
        return TickOutcome(count: count, isAttenuated: phase == .coasting || isFast)
    }

    private func updateVelocity(delta: Double, elapsed: TimeInterval) {
        let interval = min(max(elapsed, 1.0 / 240.0), configuration.idleTimeout)
        let instantaneous = abs(delta) / interval

        if smoothedVelocity == 0 {
            smoothedVelocity = instantaneous
        } else {
            let weight = min(max(configuration.velocitySmoothing, 0), 1)
            smoothedVelocity += weight * (instantaneous - smoothedVelocity)
        }
    }

    private func currentStep(for phase: GestureMovementPhase) -> Double {
        let rateLimitedStep = smoothedVelocity / configuration.maximumTickRate
        var step = max(configuration.stepSize, rateLimitedStep)
        if phase == .coasting {
            step *= configuration.coastingStepMultiplier
        }
        return step
    }

    private func signum(_ value: Double) -> Double {
        value < 0 ? -1 : 1
    }
}
