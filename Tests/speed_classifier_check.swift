// Self-check for SpeedClassifier. Run from repo root:
//   swiftc -o /tmp/speed_check Tests/speed_classifier_check.swift Sources/Gestures/Components/SpeedClassifier.swift && /tmp/speed_check
//
// Minimal stand-in for the app's GestureSpeed (Settings.swift) so the classifier
// compiles without dragging in the whole target.
enum GestureSpeed { case slow, normal, fast }

let slowMax: Float = 0.005 * 60   // default tuning × 60 = 0.30 widths/s
let fastMin: Float = 0.009 * 60   // default tuning × 60 = 0.54 widths/s
let all: Set<GestureSpeed> = [.slow, .normal, .fast]

func check(_ d: Float, _ t: Double, _ speeds: Set<GestureSpeed>, _ expected: GestureSpeed?, _ label: String) {
    let got = SpeedClassifier.classify(totalDisplacement: d, elapsedSeconds: t,
                                       configuredSpeeds: speeds, slowMax: slowMax, fastMin: fastMin)
    assert(got == expected, "\(label): expected \(String(describing: expected)), got \(String(describing: got))")
}

func checkClassic(_ samples: [Float], _ d: Float, _ t: Double, _ speeds: Set<GestureSpeed>, _ expected: GestureSpeed?, _ label: String) {
    let got = SpeedClassifier.classifyClassic(velocitySamples: samples, totalDisplacement: d,
                                              elapsedSeconds: t, configuredSpeeds: speeds,
                                              slowMax: slowMax, fastMin: fastMin, initialDistance: 0.014)
    assert(got == expected, "\(label): expected \(String(describing: expected)), got \(String(describing: got))")
}

@main enum Check {
    static func main() {
        // Single configured tier short-circuits regardless of measured speed.
        check(0.014, 0.5, [.fast], .fast, "single tier")
        // Empty set behaves as normal-only.
        check(0.014, 0.5, [], .normal, "empty set")
        // Flick: crosses trigger fast → .fast even inside the grace window.
        check(0.014, 0.02, all, .fast, "flick")
        // Grace: not yet fast, too early to call slow/normal → defer.
        check(0.010, 0.03, all, nil, "grace defers")
        // Controlled slow: low average speed after grace.
        check(0.020, 0.12, all, .slow, "slow")
        // Normal: mid speed after grace.
        check(0.050, 0.12, all, .normal, "normal")
        // Fast configured, speed above fastMin after grace.
        check(0.070, 0.10, all, .fast, "fast after grace")
        // Only slow+fast configured: between thresholds → nearest tier.
        check(0.040, 0.10, [.slow, .fast], .slow, "gap nearest slow")   // 0.40 < midpoint 0.42
        check(0.045, 0.10, [.slow, .fast], .fast, "gap nearest fast")   // 0.45 > midpoint 0.42
        // Zero-ish elapsed clamps, no divide-by-zero.
        check(0.014, 0.0, all, .fast, "elapsed clamp")                  // 0.014/0.01 = 1.4 ≥ fastMin

        // ── Classic logic ──
        // Single tier short-circuits before touching samples.
        checkClassic([], 0.02, 0.5, [.fast], .fast, "classic single tier")
        // No samples yet → defer.
        checkClassic([], 0.02, 0.5, all, nil, "classic no samples")
        // Explosive peak within the flick window → fast.
        checkClassic([0.2, 0.9, 1.2], 0.02, 0.08, all, .fast, "classic flick")
        // Steady gentle motion held long enough over distance → slow.
        checkClassic([0.30, 0.28, 0.31, 0.29, 0.30], 0.020, 0.15, all, .slow, "classic slow")
        // Too early to commit → defer.
        checkClassic([0.30, 0.28], 0.005, 0.03, all, nil, "classic early defer")

        print("SpeedClassifier self-check passed")
    }
}
