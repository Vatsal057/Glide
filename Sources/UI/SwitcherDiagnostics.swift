import Foundation

/// Per-second counters for the app switcher's hot paths.
///
/// Dormant unless `GLIDE_SWITCHER_DIAG=1` is in the environment: every entry
/// point returns on an immutable `let` before touching a lock, so a normal run
/// pays nothing for this file being here.
///
/// It exists to answer one question that reading the code cannot settle. While
/// the panel is up and the fingers are holding still, something is still
/// consuming CPU, and the plausible causes are indistinguishable from the
/// outside: phantom selection steps from trackpad drift, a SwiftUI layout and
/// preference feedback loop that never settles, repeated window captures, or
/// live glass recompositing that costs nothing of ours at all. Each of those
/// leaves a different fingerprint in these counters.
enum SwitcherDiagnostics {

    static let isEnabled = ProcessInfo.processInfo.environment["GLIDE_SWITCHER_DIAG"] == "1"

    enum Counter: String, CaseIterable {
        /// Selection changes asked for by the gesture processor. A high count with
        /// motionless fingers means drift is crossing `appSwitcherStepThreshold`.
        case selectCalls     = "select() calls"
        case selectChanged   = "  ..that moved the selection"
        /// SwiftUI re-evaluating the panel. High with nothing else high means a
        /// layout/preference loop rather than anything input-driven.
        case bodyEvaluations = "panel body evaluations"
        /// One per glass slab per SwiftUI layout pass.
        case slabReports     = "glass slab reports"
        case slabApplies     = "  ..that changed a slab frame"
        /// Window preview work, the most expensive thing the panel can do.
        case captureRounds   = "capture rounds started"
        case windowsCaptured = "windows captured"
    }

    private static let lock = NSLock()
    private static var counts: [Counter: Int] = [:]
    private static var timer: Timer?
    private static var lastSlabDescription = ""

    static func bump(_ counter: Counter) {
        guard isEnabled else { return }
        lock.lock()
        counts[counter, default: 0] += 1
        lock.unlock()
    }

    /// Records what the glass slabs currently are, so a report can show whether
    /// their frames are genuinely moving or only jittering in the low bits — an
    /// exact-equality guard treats those the same, and one of them is a loop.
    static func noteSlabs(_ description: String) {
        guard isEnabled else { return }
        lock.lock()
        lastSlabDescription = description
        lock.unlock()
    }

    static func startReporting() {
        guard isEnabled, timer == nil else { return }
        reset()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in report() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSLog("[SwitcherDiag] panel shown — reporting once per second")
    }

    static func stopReporting() {
        guard isEnabled else { return }
        timer?.invalidate()
        timer = nil
        report()
        NSLog("[SwitcherDiag] panel hidden")
    }

    private static func reset() {
        lock.lock()
        counts.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private static func report() {
        lock.lock()
        let snapshot = counts
        let slabs = lastSlabDescription
        counts.removeAll(keepingCapacity: true)
        lock.unlock()

        let lines = Counter.allCases
            .compactMap { counter -> String? in
                guard let value = snapshot[counter], value > 0 else { return nil }
                return "\(counter.rawValue)=\(value)"
            }
        if lines.isEmpty {
            NSLog("[SwitcherDiag] 1s: idle (no work) | slabs \(slabs)")
        } else {
            NSLog("[SwitcherDiag] 1s: \(lines.joined(separator: "  ")) | slabs \(slabs)")
        }
    }
}
