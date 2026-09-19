import ApplicationServices
import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeDiagnostics
//
// Answers one question: while an edge gesture is running, does the pointer
// actually hold still?
//
// It observes the live pipeline rather than driving a private engine of its own.
// That distinction matters — an earlier version injected touches into its own
// EdgeGestureEngine, which meant TrackPoint, the gesture engine and the real
// event taps never participated, so it happily reported everything healthy while
// the pointer misbehaved in normal use. Anything that can only go wrong with the
// whole system running has to be measured with the whole system running.
//
// Run with `--diag-edges [--diag-seconds=N]`.
// ─────────────────────────────────────────────────────────────────────────────

enum EdgeDiagnostics {

    private struct Observation {
        var samples = 0
        /// Samples where Edge Controls held the pointer for the edge under test.
        var held = 0
        /// Of those, samples where the suppression tap was actually enabled.
        /// A gap between this and `held` means the engine asked and nothing happened.
        var tapEnabled = 0
        /// Pixels the cursor moved while held. This is the reported symptom, measured.
        var driftPx = 0.0
        var worstJumpPx = 0.0
        /// Samples where the TrackPoint was also engaged. It drives the cursor with
        /// events marked synthetic, which the suppression tap passes through by
        /// design — so if it engages during an edge slide the pointer moves and
        /// suppression is entirely innocent.
        var trackPointEngaged = 0
        var releases = 0
    }

    static func run(seconds: Double) {
        let settings = Settings.shared.edgeControls
        let trackPoint = Settings.shared.trackPoint

        print("""
        ─────────────────────────────────────────────────────────────
         Glide — Edge Controls pointer diagnostics
        ─────────────────────────────────────────────────────────────
         Margin / activation : \(String(format: "%.1f mm / %.1f mm", settings.marginMm, settings.activationTravelMm))
         Edge assignments    : top=\(settings.topEdge.rawValue) bottom=\(settings.bottomEdge.rawValue) \
        left=\(settings.leftEdge.rawValue) right=\(settings.rightEdge.rawValue)
         TrackPoint          : \(trackPoint.enabled ? "ENABLED" : "off"), \
        mode=\(trackPoint.activationMode.rawValue), zone=\(trackPoint.zone.rawValue)
         Trackpad surface    : measured after the device opens (see below)
        ─────────────────────────────────────────────────────────────
        """)

        guard AXIsProcessTrusted() else {
            print(" Accessibility permission missing — cannot install taps. Grant it to this")
            print(" binary, or run the diagnostic from the app you already granted.")
            return
        }

        // The real pipeline, exactly as normal use runs it.
        GestureEngine.shared.start()
        guard GestureEngine.shared.isRunning else {
            print(" Gesture engine failed to start.")
            return
        }
        EdgeControlsController.shared.refreshSurfaceSize()
        let reported = TrackpadSurfaceSize.measuredOrNil()
        let surface = EdgeControlsController.shared.surfaceSize
        print(String(format: " Trackpad surface: %.1f x %.1f mm (%@)",
                     surface.width, surface.height,
                     reported == nil ? "NOMINAL — device would not report" : "measured from the device"))
        print(" Live pipeline running. Only edges you have assigned will engage.")
        print(" NOTE: quit the menu-bar Glide first — two instances fight over the taps.\n")

        var results: [TrackpadPhysicalEdge: Observation] = [:]
        let order: [TrackpadPhysicalEdge] = [.bottom, .top, .left, .right]
        let perEdge = max(seconds / Double(order.count), 3.0)

        for edge in order {
            let action = assignment(for: edge, settings)
            print(" ▶︎ Slide ONE finger along the \(edge.displayName.uppercased()) "
                  + "(\(action.displayName)) — \(Int(perEdge))s")
            if action == .none {
                print("   (unassigned — skipping)")
                results[edge] = Observation()
                Thread.sleep(forTimeInterval: 0.6)
                continue
            }
            results[edge] = observe(edge: edge, seconds: perEdge)
            let o = results[edge]!
            print("   held \(o.held)/\(o.samples) samples, tap on \(o.tapEnabled), "
                  + "cursor moved \(Int(o.driftPx)) px while held"
                  + (o.trackPointEngaged > 0 ? ", TRACKPOINT ENGAGED \(o.trackPointEngaged)x" : ""))
        }

        GestureEngine.shared.stop()
        report(results, settings: settings)
    }

    // MARK: - Sampling

    private static func observe(edge: TrackpadPhysicalEdge, seconds: Double) -> Observation {
        var o = Observation()
        let controller = EdgeControlsController.shared
        let manager = GestureEngine.shared.inputManager
        var lastCursor: CGPoint?
        var wasHeld = false

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.008))

            o.samples += 1
            let held = controller.isSuppressingPointer && controller.activeEdge == edge
            let cursor = CGEvent(source: nil)?.location

            if held {
                o.held += 1
                if manager?.trackPointSuppressionEnabled == true { o.tapEnabled += 1 }
                if TrackPointController.shared.isEngaged { o.trackPointEngaged += 1 }
                // Only across consecutive held samples, so the deliberate restore-warp
                // fired on commit is not counted as drift.
                if wasHeld, let now = cursor, let prev = lastCursor {
                    let jump = hypot(now.x - prev.x, now.y - prev.y)
                    o.driftPx += jump
                    o.worstJumpPx = max(o.worstJumpPx, jump)
                }
            }
            if wasHeld && !held { o.releases += 1 }
            wasHeld = held
            lastCursor = cursor
        }
        return o
    }

    // MARK: - Report

    private static func report(_ results: [TrackpadPhysicalEdge: Observation],
                               settings: EdgeControlsSettings) {
        print("""

        ─────────────────────────────────────────────────────────────
         Results
        ─────────────────────────────────────────────────────────────
         edge     action              held   tap    rel  cursor drift   verdict
         ------   -----------------   ----   ----   ---  ------------   ----------------------
        """)

        for edge in [TrackpadPhysicalEdge.bottom, .top, .left, .right] {
            guard let o = results[edge] else { continue }
            let action = assignment(for: edge, settings)

            let verdict: String
            if action == .none {
                verdict = "unassigned"
            } else if o.held == 0 {
                verdict = "NEVER ENGAGED"
            } else if o.tapEnabled < o.held {
                verdict = "TAP NOT ACTIVE while held"
            } else if o.trackPointEngaged > 0 {
                verdict = "TRACKPOINT is driving the cursor"
            } else if o.driftPx > 12 {
                verdict = String(format: "POINTER MOVED %.0f px anyway", o.driftPx)
            } else {
                verdict = "pointer held still"
            }

            print(" " + pad(edge.rawValue, 9)
                  + pad(action.rawValue, 20)
                  + pad("\(o.held)", 7)
                  + pad("\(o.tapEnabled)", 7)
                  + pad("\(o.releases)", 5)
                  + pad(String(format: "%.0f px", o.driftPx), 15)
                  + verdict)
        }

        let engaged = [TrackpadPhysicalEdge.bottom, .top, .left, .right]
            .compactMap { results[$0] }.filter { $0.held > 0 }
        let tpEdges = [TrackpadPhysicalEdge.bottom, .top, .left, .right]
            .filter { (results[$0]?.trackPointEngaged ?? 0) > 0 }
        let driftEdges = [TrackpadPhysicalEdge.bottom, .top, .left, .right]
            .filter { (results[$0]?.driftPx ?? 0) > 12 && (results[$0]?.trackPointEngaged ?? 0) == 0 }
        let tapGap = [TrackpadPhysicalEdge.bottom, .top, .left, .right]
            .filter { let o = results[$0]; return (o?.held ?? 0) > 0 && (o?.tapEnabled ?? 0) < (o?.held ?? 0) }
        let flapping = [TrackpadPhysicalEdge.bottom, .top, .left, .right]
            .filter { (results[$0]?.releases ?? 0) > 4 }

        print("\n Diagnosis:")
        if engaged.isEmpty {
            print(" • Nothing engaged at all — check the edges are assigned and enabled.")
        }
        if !tapGap.isEmpty {
            print(" • \(tpEdges.isEmpty ? "" : "")Suppression was requested but the tap was off on: "
                  + tapGap.map(\.rawValue).joined(separator: ", "))
            print("   → the tap is failing to enable, not the gesture failing to commit.")
        }
        if !tpEdges.isEmpty {
            print(" • TrackPoint engaged during: " + tpEdges.map(\.rawValue).joined(separator: ", "))
            print("   → it drives the cursor with events the suppression tap passes on purpose,")
            print("     so it moves the pointer straight through the freeze. This is the cause.")
        }
        if !driftEdges.isEmpty {
            print(" • Pointer moved despite an active tap on: "
                  + driftEdges.map(\.rawValue).joined(separator: ", "))
            print("   → something is posting synthetic motion, or the tap is being bypassed.")
        }
        if !flapping.isEmpty {
            print(" • Gesture released and re-took the pointer repeatedly on: "
                  + flapping.map(\.rawValue).joined(separator: ", "))
            print("   → each release frees the cursor briefly; likely the contact being")
            print("     re-identified mid-slide, or the gesture restarting.")
        }
        if tapGap.isEmpty && tpEdges.isEmpty && driftEdges.isEmpty && !engaged.isEmpty {
            print(" • Every engaged edge held the pointer still. The problem is not here.")
        }
        print("─────────────────────────────────────────────────────────────")
    }

    // MARK: - Helpers

    private static func assignment(for edge: TrackpadPhysicalEdge,
                                   _ s: EdgeControlsSettings) -> EdgeAction {
        switch edge {
        case .top:    return s.topEdge
        case .bottom: return s.bottomEdge
        case .left:   return s.leftEdge
        case .right:  return s.rightEdge
        }
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s + " " : s + String(repeating: " ", count: width - s.count)
    }
}
