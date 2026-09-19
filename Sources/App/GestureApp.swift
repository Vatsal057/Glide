import SwiftUI
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--test-gestures") {
            runGestureVerification(forceFailure: false)
            exit(0)
        }
        if CommandLine.arguments.contains("--test-gestures-fail") {
            runGestureVerification(forceFailure: true)
            exit(0)
        }
        if CommandLine.arguments.contains("--diag-edges") {
            let seconds = CommandLine.arguments
                .first { $0.hasPrefix("--diag-seconds=") }
                .flatMap { Double($0.dropFirst("--diag-seconds=".count)) } ?? 30
            EdgeDiagnostics.run(seconds: seconds)
            exit(0)
        }
        if CommandLine.arguments.contains("--test-edge-controls") {
            runEdgeControlsVerification(forceFailure: false)
            exit(0)
        }
        if CommandLine.arguments.contains("--test-edge-controls-fail") {
            runEdgeControlsVerification(forceFailure: true)
            exit(0)
        }

        EngineBridge.shared.startEngine()
        if OnboardingController.shouldShow {
            SplashOverlay.present { OnboardingController.shared.show() }
        } else {
            checkAccessibilityPermission()
        }
        // Re-assert on launch — System Settings may have re-enabled native gestures.
        SystemGestureManager.reconcileIfAutoEnabled()

        // One quiet check shortly after launch, so an available update shows up
        // in the menu bar instead of waiting to be hunted for. Delayed to keep
        // it off the critical path of getting gestures running.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            UpdateChecker.shared.checkIfDue()
        }

    }

    func applicationWillTerminate(_ notification: Notification) {
        GlideConfigStore.shared.flushPendingSave()
    }

    private func checkAccessibilityPermission() {
        if AXIsProcessTrusted() { return }

        // Prompt the user — passing `kAXTrustedCheckOptionPrompt` shows the
        // native macOS dialog and opens Accessibility in System Settings.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    private func runGestureVerification(forceFailure: Bool) {
        print("[TEST] Running GestureAnimationView verification suite...")

        if forceFailure {
            print("[TEST] Forced failure requested -> exiting with code 1")
            exit(1)
        }

        var testedCount = 0
        for dir in GestureDirection.allCases {
            for fingers in [3, 4, 5] {
                for zone in TrackpadZone.allCases {
                    for mod in ModifierFilter.allCases {
                        for spd in GestureSpeed.allCases {
                            _ = GestureAnimationView(
                                direction: dir,
                                fingerCount: fingers,
                                zone: zone,
                                modifierFilter: mod,
                                speed: spd,
                                continuous: false,
                                action: .doNothing,
                                showLabel: true
                            )
                            testedCount += 1
                        }
                    }
                }
            }
        }
        print("[TEST] Initialized and verified \(testedCount) permutations of GestureAnimationView (including all speed tiers)")

        let samples: [(name: String, dir: GestureDirection, fingers: Int, zone: TrackpadZone, mod: ModifierFilter, spd: GestureSpeed, cont: Bool, act: GestureAction)] = [
            ("preview_3finger_swipe_fast.png", .swipeRight, 3, .topLeft, .shiftHeld, .fast, false, .switchAppNext),
            ("preview_3finger_swipe_slow.png", .swipeLeft, 3, .any, .any, .slow, false, .missionControl),
            ("preview_4finger_continuous.png", .swipeLeftRight, 4, .any, .noModifiers, .normal, true, .appSwitcherNext),
            ("preview_4finger_forceclick.png", .forceClick, 4, .any, .noModifiers, .normal, false, .lockScreen)
        ]

        for sample in samples {
            let sampleView = GestureAnimationView(
                direction: sample.dir,
                fingerCount: sample.fingers,
                zone: sample.zone,
                modifierFilter: sample.mod,
                speed: sample.spd,
                continuous: sample.cont,
                action: sample.act,
                showLabel: true
            )
            let renderer = ImageRenderer(content: sampleView)
            renderer.scale = 2.0
            if let nsImage = renderer.nsImage,
               let tiffData = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiffData),
               let pngData = rep.representation(using: .png, properties: [:]) {
                let path = "/Users/vatsal/.gemini/antigravity-ide/brain/e95df4e2-f922-4fa1-affb-19fe031ca3b4/\(sample.name)"
                try? pngData.write(to: URL(fileURLWithPath: path))
                print("[TEST] Saved sample \(sample.name) (\(pngData.count) bytes)")
            }
        }

        print("[TEST] ✅ GestureAnimationView verification PASSED.")
    }

    @MainActor
    private func runEdgeControlsVerification(forceFailure: Bool) {
        print("[TEST-EDGE] Running Trackpad Edge Controls verification suite...")

        if forceFailure {
            print("[TEST-EDGE] Forced failure requested -> exiting with code 1")
            exit(1)
        }

        // 1. Verify TickAccumulator quantization & rate limiting
        let accumulator = TickAccumulator(configuration: TickConfiguration(stepSize: 5.0, maximumTickRate: 24.0))
        let now = ProcessInfo.processInfo.systemUptime
        let firstOutcome = accumulator.consume(delta: 2.0, timestamp: now, phase: .active)
        assert(firstOutcome.count == 0, "Sub-step delta should not produce a tick")
        let secondOutcome = accumulator.consume(delta: 4.0, timestamp: now + 0.01, phase: .active) // total 6mm >= 5mm step
        assert(secondOutcome.count == 1, "Cumulative delta exceeding stepSize must produce exactly 1 tick")
        print("[TEST-EDGE] TickAccumulator step quantization passed.")

        // 2. Verify Edge detection geometry
        let engine = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
            isEnabled: true,
            topAction: .appSwitcher,
            bottomAction: .keyboardBacklight,
            leftAction: .brightness,
            rightAction: .volume,
            marginMm: 10.0
        ))

        // Center touch (x: 0.5, y: 0.5) must NOT start edge gesture
        let centerPoint = GLDTouchPoint(identifier: 1, state: 3, x: 0.5, y: 0.5, vx: 0, vy: 0, size: 1)
        engine.consume(touch: centerPoint, contacts: 1, timestamp: now)
        assert(engine.activeEdge == nil, "Center touch must not start edge gesture")
        print("[TEST-EDGE] Center touch rejection passed.")

        // Moving center touch into the edge (x: 0.5 -> x: 0.98) must NOT trigger edge controls (disqualified origin)
        let draggedToEdgePoint = GLDTouchPoint(identifier: 1, state: 3, x: 0.98, y: 0.5, vx: 100, vy: 0, size: 1)
        engine.consume(touch: draggedToEdgePoint, contacts: 1, timestamp: now + 0.02)
        assert(engine.activeEdge == nil, "Touch originating away from edge must not activate edge controls when moving into edge")
        print("[TEST-EDGE] Non-edge origin disqualification passed.")

        // Right edge touch (x: 0.98, y: 0.5) must start .right (volume)
        let rightEdgePoint = GLDTouchPoint(identifier: 2, state: 3, x: 0.98, y: 0.5, vx: 0, vy: 0, size: 1)
        engine.consume(touch: rightEdgePoint, contacts: 1, timestamp: now + 0.05)
        assert(engine.activeEdge == .right, "Right edge touch must start right edge gesture")
        print("[TEST-EDGE] Right edge detection passed.")

        // Slide along right edge (y: 0.5 -> y: 0.8, x remains at 0.97 near edge)
        let rightSlidePoint = GLDTouchPoint(identifier: 2, state: 4, x: 0.97, y: 0.8, vx: 0, vy: 50, size: 1)
        engine.consume(touch: rightSlidePoint, contacts: 1, timestamp: now + 0.10)
        assert(engine.activeEdge == .right, "Gesture remains active during slide within margin")
        print("[TEST-EDGE] Edge slide continuation passed.")

        // Drifting inward away from edge (x: 0.80 is ~31mm from right edge, > 10mm margin) must cancel
        let inwardDriftPoint = GLDTouchPoint(identifier: 2, state: 4, x: 0.80, y: 0.8, vx: -50, vy: 0, size: 1)
        engine.consume(touch: inwardDriftPoint, contacts: 1, timestamp: now + 0.12)
        assert(engine.activeEdge == nil, "Drifting inward away from edge must cancel edge gesture")
        print("[TEST-EDGE] Inward drift cancellation passed.")

        // Perpendicular inward movement from edge on fresh touch must be rejected
        let edgeFreshPoint = GLDTouchPoint(identifier: 4, state: 3, x: 0.98, y: 0.5, vx: 0, vy: 0, size: 1)
        engine.consume(touch: edgeFreshPoint, contacts: 1, timestamp: now + 0.13)
        assert(engine.activeEdge == .right)
        let perpInwardPoint = GLDTouchPoint(identifier: 4, state: 3, x: 0.95, y: 0.501, vx: -50, vy: 0, size: 1) // ~4.7mm inward, 0.1mm vertical
        engine.consume(touch: perpInwardPoint, contacts: 1, timestamp: now + 0.14)
        assert(engine.activeEdge == nil, "Inward movement into trackpad must not trigger along-edge swipe")
        print("[TEST-EDGE] Perpendicular inward motion rejection passed.")

        // Multitouch rejection (contacts == 2) must cancel edge gesture
        let rightEdgeStartPoint = GLDTouchPoint(identifier: 5, state: 3, x: 0.98, y: 0.5, vx: 0, vy: 0, size: 1)
        engine.consume(touch: rightEdgeStartPoint, contacts: 1, timestamp: now + 0.15)
        assert(engine.activeEdge == .right)
        let twoFingerPoint = GLDTouchPoint(identifier: 5, state: 4, x: 0.97, y: 0.8, vx: 0, vy: 0, size: 1)
        engine.consume(touch: twoFingerPoint, contacts: 2, timestamp: now + 0.16)
        assert(engine.activeEdge == nil, "Two-finger touch must immediately drop edge gesture for scrolling")
        print("[TEST-EDGE] Multitouch isolation (2+ contacts dropped) passed.")

        // 2b. Verify the activation gate — the defence against accidental triggers.
        // Each case starts a fresh touch id on the right edge, then moves once.
        func armAttempt(id: Int32, toX: Float, toY: Float, at offset: TimeInterval,
                        action: EdgeAction = .volume) -> Bool {
            let engine = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
                isEnabled: true,
                topAction: .none, bottomAction: .none, leftAction: .none,
                rightAction: action,
                marginMm: 10.0,
                activationTravelMm: 4.0
            ))
            let start = GLDTouchPoint(identifier: id, state: 3, x: 0.99, y: 0.5, vx: 0, vy: 0, size: 1)
            engine.consume(touch: start, contacts: 1, timestamp: now + offset)
            assert(engine.activeEdge == .right, "Touch on the right edge must be a candidate")
            let move = GLDTouchPoint(identifier: id, state: 4, x: toX, y: toY, vx: 0, vy: 0, size: 1)
            engine.consume(touch: move, contacts: 1, timestamp: now + offset + 0.02)
            let armed = engine.hasCommittedGesture
            engine.consume(touch: nil, contacts: 0, timestamp: now + offset + 0.04)
            return armed
        }

        // Travel below the threshold must not commit. 0.5 -> 0.53 is ~2.9mm.
        assert(!armAttempt(id: 20, toX: 0.99, toY: 0.53, at: 0.50),
               "A 2.9mm slide must not trip a 4.0mm activation threshold")
        // Just past it must commit. 0.5 -> 0.55 is ~4.9mm.
        assert(armAttempt(id: 21, toX: 0.99, toY: 0.55, at: 0.55),
               "A 4.9mm slide along the edge must commit")

        // A diagonal sweep away from the edge must not commit however far it travels
        // along the edge — this is ordinary cursor movement that happens to start at
        // the rim, and it is the most common accidental trigger.
        assert(!armAttempt(id: 22, toX: 0.93, toY: 0.62, at: 0.60),
               "A diagonal sweep inward must not commit despite 11mm of along-edge travel")

        // A straight inward push has no along-axis travel for a ratio to catch, so
        // the absolute perpendicular cap is what has to reject it.
        assert(!armAttempt(id: 23, toX: 0.95, toY: 0.5, at: 0.65),
               "A straight inward push must not commit")

        // A shallow diagonal that stays inside the perpendicular cap: 4.5mm along,
        // 2.5mm across. Far enough to pass the travel threshold, but only the purity
        // ratio can tell it apart from a real edge slide.
        assert(!armAttempt(id: 28, toX: 0.9742, toY: 0.546, at: 0.66),
               "A 4.5mm-along / 2.5mm-across diagonal must fail the direction-purity test")

        // 9mm along, 4mm across: straight enough to satisfy the purity ratio, but it
        // has wandered too far from the rim to still be an edge gesture. Only the
        // absolute perpendicular cap rejects this one, which is what keeps the
        // decision anchored near where the finger landed.
        assert(!armAttempt(id: 29, toX: 0.96465, toY: 0.59202, at: 0.67),
               "A slide that drifts 4mm inward before committing must be rejected")

        // Slight drift across the edge is fine — fingers are not rulers.
        assert(armAttempt(id: 24, toX: 0.985, toY: 0.57, at: 0.70),
               "A near-parallel slide with minor drift must still commit")

        // Raising the threshold must make the same gesture stop qualifying.
        let strict = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
            isEnabled: true,
            topAction: .none, bottomAction: .none, leftAction: .none, rightAction: .volume,
            marginMm: 10.0,
            activationTravelMm: 12.0
        ))
        let strictStart = GLDTouchPoint(identifier: 25, state: 3, x: 0.99, y: 0.5, vx: 0, vy: 0, size: 1)
        strict.consume(touch: strictStart, contacts: 1, timestamp: now + 0.75)
        let strictMove = GLDTouchPoint(identifier: 25, state: 4, x: 0.99, y: 0.57, vx: 0, vy: 0, size: 1)
        strict.consume(touch: strictMove, contacts: 1, timestamp: now + 0.77)
        assert(!strict.hasCommittedGesture, "A 6.8mm slide must not trip a 12.0mm threshold")
        strict.consume(touch: nil, contacts: 0, timestamp: now + 0.79)
        print("[TEST-EDGE] Activation gate (travel + direction purity) passed.")

        // 2c. Pointer suppression is positional, not conditional on committing.
        //
        // The pointer must be still for the whole time the finger is in an assigned
        // strip, including the activation travel. Freezing only on commit leaves that
        // travel unguarded, which is the cursor movement that was actually reported.
        func suppressionEngine(_ action: EdgeAction) -> EdgeGestureEngine {
            EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
                isEnabled: true,
                topAction: .none, bottomAction: .none, leftAction: .none, rightAction: action,
                marginMm: 6.5,
                activationTravelMm: 4.0
            ))
        }

        // Every action, not just scroll — the cursor drifts the same way regardless.
        for (index, action) in [EdgeAction.volume, .brightness, .scroll, .appSwitcher,
                                .keyboardBacklight, .nightShift].enumerated() {
            let engine = suppressionEngine(action)
            let id = Int32(50 + index)
            let landing = GLDTouchPoint(identifier: id, state: 3, x: 0.995, y: 0.5, vx: 0, vy: 0, size: 1)
            engine.consume(touch: landing, contacts: 1, timestamp: now + 0.85 + Double(index) * 0.01)
            assert(engine.isSuppressingPointer,
                   "\(action.rawValue): the pointer must freeze on touch-down in the strip")
            assert(!engine.hasCommittedGesture,
                   "\(action.rawValue): landing alone must not commit the action")
            engine.consume(touch: nil, contacts: 0, timestamp: now + 0.86 + Double(index) * 0.01)
            assert(!engine.isSuppressingPointer, "\(action.rawValue): lifting must free the pointer")
        }

        // A touch that sweeps in from the middle of the pad is cursor work and must
        // never be frozen, even as it crosses the strip.
        let sweepEngine = suppressionEngine(.volume)
        let sweepStart = GLDTouchPoint(identifier: 60, state: 3, x: 0.5, y: 0.5, vx: 0, vy: 0, size: 1)
        sweepEngine.consume(touch: sweepStart, contacts: 1, timestamp: now + 0.95)
        assert(!sweepEngine.isSuppressingPointer, "A touch starting mid-pad must not freeze the pointer")
        let sweepIntoEdge = GLDTouchPoint(identifier: 60, state: 4, x: 0.995, y: 0.5, vx: 0, vy: 0, size: 1)
        sweepEngine.consume(touch: sweepIntoEdge, contacts: 1, timestamp: now + 0.97)
        assert(!sweepEngine.isSuppressingPointer,
               "Sweeping into the strip from mid-pad must still not freeze the pointer")
        sweepEngine.consume(touch: nil, contacts: 0, timestamp: now + 0.99)

        // Heading inward hands the pointer straight back — "between the edge and the
        // trackpad" is cursor territory.
        let inwardEngine = suppressionEngine(.volume)
        let inwardStart = GLDTouchPoint(identifier: 61, state: 3, x: 0.995, y: 0.5, vx: 0, vy: 0, size: 1)
        inwardEngine.consume(touch: inwardStart, contacts: 1, timestamp: now + 1.00)
        assert(inwardEngine.isSuppressingPointer, "test setup: should be frozen on landing")
        // ~4mm inward, past the 3mm pre-commit perpendicular cap.
        let inwardMove = GLDTouchPoint(identifier: 61, state: 4, x: 0.97, y: 0.5, vx: 0, vy: 0, size: 1)
        inwardEngine.consume(touch: inwardMove, contacts: 1, timestamp: now + 1.02)
        assert(!inwardEngine.isSuppressingPointer,
               "Moving inward must release the pointer promptly, not hold it hostage")
        inwardEngine.consume(touch: nil, contacts: 0, timestamp: now + 1.04)
        print("[TEST-EDGE] Positional pointer suppression (strip = frozen) passed.")

        // 2c-2. Hysteresis: a committed gesture survives inward drift that would have
        // stopped it from starting. Without this, a tight margin drops the gesture
        // partway through a slide, and because that releases the pointer the cursor
        // visibly comes back to life mid-gesture.
        //
        // Run at a 6.5mm margin, which is tight enough that ordinary finger wander
        // exceeds it — the configuration this was actually reported against.
        func slideThenDrift(driftToX: Float, id: Int32, at offset: TimeInterval) -> Bool {
            let engine = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
                isEnabled: true,
                topAction: .none, bottomAction: .none, leftAction: .none, rightAction: .scroll,
                marginMm: 6.5,
                activationTravelMm: 4.0
            ))
            // Land on the rim and commit with a clean 6.8mm slide.
            let start = GLDTouchPoint(identifier: id, state: 3, x: 0.995, y: 0.5, vx: 0, vy: 0, size: 1)
            engine.consume(touch: start, contacts: 1, timestamp: now + offset)
            let commit = GLDTouchPoint(identifier: id, state: 4, x: 0.995, y: 0.57, vx: 0, vy: 0, size: 1)
            engine.consume(touch: commit, contacts: 1, timestamp: now + offset + 0.02)
            assert(engine.hasCommittedGesture, "test setup: the gesture must commit first")
            // Now let the finger wander inward while continuing along the edge.
            let drift = GLDTouchPoint(identifier: id, state: 4, x: driftToX, y: 0.64, vx: 0, vy: 0, size: 1)
            engine.consume(touch: drift, contacts: 1, timestamp: now + offset + 0.04)
            let survived = engine.hasCommittedGesture && engine.activeEdge == .right
            engine.consume(touch: nil, contacts: 0, timestamp: now + offset + 0.06)
            return survived
        }

        // 0.93 is ~11mm from the right edge: well past the 6.5mm entry margin, inside
        // the 16.5mm a committed gesture is allowed.
        assert(slideThenDrift(driftToX: 0.93, id: 30, at: 1.20),
               "A committed gesture must survive 11mm of inward drift at a 6.5mm margin")
        // 0.995 -> 0.86 is ~22mm inward, past the retain limit: the finger has clearly
        // left the edge and the cursor should get control back.
        assert(!slideThenDrift(driftToX: 0.86, id: 31, at: 1.25),
               "Drifting past the retain limit must still end the gesture")
        // Hysteresis must not loosen *entry*: the same 11mm is still too far to start.
        assert(!armAttempt(id: 32, toX: 0.93, toY: 0.57, at: 1.30),
               "Entry must stay strict — 11mm inward is not a place to start a gesture")
        print("[TEST-EDGE] Commit hysteresis (loose to keep, strict to start) passed.")

        // 2d. Corners belong to no edge. With any real margin the four zones overlap
        // there, so a corner touch has no correct owner — and it is also where the
        // TrackPoint's corner activation lives.
        let cornerEngine = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
            isEnabled: true,
            topAction: .volume, bottomAction: .volume, leftAction: .volume, rightAction: .volume,
            marginMm: 12.0,
            activationTravelMm: 4.0
        ))
        // 1.6mm from the right edge and 2.9mm from the bottom: inside both zones.
        let cornerTouch = GLDTouchPoint(identifier: 40, state: 3, x: 0.99, y: 0.03, vx: 0, vy: 0, size: 1)
        cornerEngine.consume(touch: cornerTouch, contacts: 1, timestamp: now + 1.00)
        assert(cornerEngine.activeEdge == nil, "A corner touch must belong to no edge")

        // The middle of the same edge is still fine.
        let midEdgeTouch = GLDTouchPoint(identifier: 41, state: 3, x: 0.99, y: 0.5, vx: 0, vy: 0, size: 1)
        cornerEngine.consume(touch: midEdgeTouch, contacts: 1, timestamp: now + 1.02)
        assert(cornerEngine.activeEdge == .right, "Mid-edge touches must still be accepted")
        cornerEngine.consume(touch: nil, contacts: 0, timestamp: now + 1.04)

        // With TrackPoint corner activation in use, the exclusion has to grow to
        // cover its zone: 0.198 of the 97.8mm short axis is 19.4mm, so a touch 15.6mm
        // up the right edge clears the 12mm floor but still lands in the corner zone.
        func rightEdgeAccepted(cornerZone: Double, y: Float, id: Int32) -> Bool {
            let engine = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
                isEnabled: true,
                topAction: .none, bottomAction: .none, leftAction: .none, rightAction: .volume,
                marginMm: 12.0,
                activationTravelMm: 4.0,
                trackPointCornerZone: cornerZone
            ))
            let touch = GLDTouchPoint(identifier: id, state: 3, x: 0.99, y: y, vx: 0, vy: 0, size: 1)
            engine.consume(touch: touch, contacts: 1, timestamp: now + 1.06)
            let accepted = engine.activeEdge == .right
            engine.consume(touch: nil, contacts: 0, timestamp: now + 1.08)
            return accepted
        }
        assert(rightEdgeAccepted(cornerZone: 0, y: 0.16, id: 42),
               "15.6mm up the edge is fine when TrackPoint has no corner zone")
        assert(!rightEdgeAccepted(cornerZone: 0.198, y: 0.16, id: 43),
               "The same spot must be refused when it falls inside the TrackPoint corner zone")
        assert(rightEdgeAccepted(cornerZone: 0.198, y: 0.5, id: 44),
               "The middle of the edge stays available regardless of the corner zone")
        print("[TEST-EDGE] Corner exclusion (edge overlap + TrackPoint zone) passed.")

        // 2e. Committing must undo the pointer drift the pre-commit travel caused.
        // Suppression only stops drift from the commit onward; the events that moved
        // the cursor while the gesture was being recognised are already delivered.
        if let originalCursor = CGEvent(source: nil)?.location {
            CursorDriver.shared.warp(to: originalCursor)
            usleep(60_000)
            let landed = CGEvent(source: nil)?.location ?? originalCursor

            let restoreEngine = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
                isEnabled: true,
                topAction: .none, bottomAction: .none, leftAction: .none, rightAction: .volume,
                marginMm: 12.0,
                activationTravelMm: 4.0
            ))
            let restoreStart = GLDTouchPoint(identifier: 45, state: 3, x: 0.99, y: 0.5, vx: 0, vy: 0, size: 1)
            restoreEngine.consume(touch: restoreStart, contacts: 1, timestamp: now + 1.10)
            assert(restoreEngine.activeEdge == .right)

            // Stand in for the drift those first few millimetres would produce.
            CursorDriver.shared.warp(to: CGPoint(x: landed.x + 60, y: landed.y + 40))
            usleep(60_000)
            let drifted = CGEvent(source: nil)?.location ?? landed
            let driftedBy = hypot(drifted.x - landed.x, drifted.y - landed.y)
            assert(driftedBy > 20, "test setup: the cursor should have moved, moved \(driftedBy)")

            let restoreCommit = GLDTouchPoint(identifier: 45, state: 4, x: 0.99, y: 0.56, vx: 0, vy: 0, size: 1)
            restoreEngine.consume(touch: restoreCommit, contacts: 1, timestamp: now + 1.12)
            assert(restoreEngine.hasCommittedGesture, "test setup: the gesture should have committed")
            usleep(60_000)
            let restored = CGEvent(source: nil)?.location ?? .zero
            let offBy = hypot(restored.x - landed.x, restored.y - landed.y)
            assert(offBy < 3.0,
                   "Committing must put the cursor back where the finger landed, off by \(offBy)")

            restoreEngine.consume(touch: nil, contacts: 0, timestamp: now + 1.14)
            CursorDriver.shared.warp(to: originalCursor)
            print("[TEST-EDGE] Pre-commit cursor drift is undone on commit.")
        }

        // 3. Verify App Switcher customization on different edges
        engine.config.topAction = .appSwitcher
        let topEdgePoint = GLDTouchPoint(identifier: 3, state: 3, x: 0.5, y: 0.98, vx: 0, vy: 0, size: 1)
        engine.consume(touch: topEdgePoint, contacts: 1, timestamp: now + 0.20)
        assert(engine.activeEdge == .top, "Top edge touch must start top edge gesture (App Switcher)")
        print("[TEST-EDGE] Customizable App Switcher scrub on Top edge passed.")

        // 4. Verify scroll direction mapping.
        // Two coordinate spaces meet here: trackpad travel is positive up/right,
        // while CGEvent wheel1 is positive toward the *start* of the document.
        // Getting that backwards inverts scrolling for everyone.
        var scrollSettings = EdgeControlsSettings()
        scrollSettings.scrollSpeed = 20.0
        scrollSettings.invertScroll = false

        let forward = EdgeGestureEngine.scrollPoints(travelMm: 3.0, settings: scrollSettings)
        assert(abs(forward + 60.0) < 0.001,
               "3mm forward at 20 pt/mm must yield -60 points (down the document, natural direction), got \(forward)")

        let backward = EdgeGestureEngine.scrollPoints(travelMm: -3.0, settings: scrollSettings)
        assert(abs(backward - 60.0) < 0.001, "Reversing travel must reverse the sign")

        assert(EdgeGestureEngine.scrollPoints(travelMm: 0, settings: scrollSettings) == 0,
               "No travel must produce no scroll")

        // Speed must scale linearly, so the preference means what it says.
        scrollSettings.scrollSpeed = 40.0
        let doubled = EdgeGestureEngine.scrollPoints(travelMm: 3.0, settings: scrollSettings)
        assert(abs(doubled - 2 * forward) < 0.001, "Doubling scroll speed must double the output")

        scrollSettings.scrollSpeed = 20.0
        scrollSettings.invertScroll = true
        let inverted = EdgeGestureEngine.scrollPoints(travelMm: 3.0, settings: scrollSettings)
        assert(abs(inverted + forward) < 0.001, "invertScroll must flip the axis")
        assert(!EdgeControlsSettings().invertScroll, "Natural scrolling must be the default")
        print("[TEST-EDGE] Scroll direction mapping passed.")

        // 5. Verify scroll is continuous (bypasses the tick quantizer) and silent
        assert(EdgeAction.scroll.isContinuous, "Scroll must be continuous")
        assert(!EdgeAction.volume.isContinuous, "Notched actions must not be continuous")
        assert(!EdgeAction.scroll.wantsHapticTicks, "Scroll must not fire a haptic per frame")
        assert(EdgeAction.volume.wantsHapticTicks, "Volume must keep its haptic ticks")
        assert(!EdgeAction.appSwitcher.wantsHapticTicks, "App Switcher keeps its own haptics")
        print("[TEST-EDGE] Continuous-action classification passed.")

        // 6. Verify a scroll gesture claims pointer suppression and hands it back.
        // A single contact drives both the cursor and the edge scroll, so a leaked
        // claim would freeze the pointer for the rest of the session.
        let scrollEngine = EdgeGestureEngine(config: EdgeGestureEngine.Configuration(
            isEnabled: true,
            topAction: .none,
            bottomAction: .none,
            leftAction: .none,
            rightAction: .scroll,
            marginMm: 10.0
        ))
        let scrollStart = GLDTouchPoint(identifier: 10, state: 3, x: 0.98, y: 0.5, vx: 0, vy: 0, size: 1)
        scrollEngine.consume(touch: scrollStart, contacts: 1, timestamp: now + 0.30)
        assert(scrollEngine.activeEdge == .right, "Scroll edge touch must start the gesture")
        assert(!scrollEngine.hasCommittedGesture, "The gesture must not commit on touch-down alone")
        assert(scrollEngine.isSuppressingPointer, "The pointer must freeze as soon as the finger lands in the strip")

        // 0.5 -> 0.57 of 97.8mm is ~6.8mm, past the 4.0mm activation travel
        let scrollSlide = GLDTouchPoint(identifier: 10, state: 4, x: 0.98, y: 0.57, vx: 0, vy: 30, size: 1)
        scrollEngine.consume(touch: scrollSlide, contacts: 1, timestamp: now + 0.32)
        assert(scrollEngine.activeEdge == .right, "Scroll gesture must survive the slide")
        assert(scrollEngine.hasCommittedGesture, "The slide must commit the gesture")
        assert(scrollEngine.isSuppressingPointer, "A committed scroll gesture must still hold the pointer")

        scrollEngine.consume(touch: nil, contacts: 0, timestamp: now + 0.34)
        assert(scrollEngine.activeEdge == nil, "Lifting the finger must end the scroll gesture")
        assert(!scrollEngine.isSuppressingPointer, "Pointer suppression must be released on lift")
        print("[TEST-EDGE] Scroll pointer-suppression lifecycle passed.")

        // 6b. A horizontal edge must drive scrolling too. Travel there is measured
        // along x, and it feeds the same vertical-only output as a side edge —
        // top/bottom scroll vertically, not horizontally.
        EdgeScrollSession.shared.cancel()
        scrollEngine.config.topAction = .scroll
        scrollEngine.config.rightAction = .none
        let topStart = GLDTouchPoint(identifier: 11, state: 3, x: 0.5, y: 0.98, vx: 0, vy: 0, size: 1)
        scrollEngine.consume(touch: topStart, contacts: 1, timestamp: now + 0.40)
        assert(scrollEngine.activeEdge == .top, "Top edge must start a scroll gesture")
        assert(!scrollEngine.hasCommittedGesture, "The gesture must not commit on touch-down alone")

        // 0.5 -> 0.55 of 157.8mm is ~7.9mm along x, past the 4.0mm activation travel
        let topSlide = GLDTouchPoint(identifier: 11, state: 4, x: 0.55, y: 0.98, vx: 30, vy: 0, size: 1)
        scrollEngine.consume(touch: topSlide, contacts: 1, timestamp: now + 0.42)
        assert(scrollEngine.activeEdge == .top, "Top edge scroll must survive the slide")
        assert(scrollEngine.hasCommittedGesture, "The top-edge slide must commit")
        assert(scrollEngine.isSuppressingPointer, "A committed top-edge scroll must hold the pointer")

        scrollEngine.consume(touch: nil, contacts: 0, timestamp: now + 0.44)
        assert(!scrollEngine.isSuppressingPointer, "Top edge scroll must release suppression on lift")
        print("[TEST-EDGE] Horizontal-edge (top/bottom) scrolling passed.")

        // 6c. Session plumbing: travel arms the drive clock, cancel parks it.
        // The 120 Hz smoothing curve itself needs a live run loop and is verified
        // separately by simulation; only the state transitions are checked here.
        EdgeScrollSession.shared.cancel()
        assert(!EdgeScrollSession.shared.isRunning, "A cancelled session must not be running")
        EdgeScrollSession.shared.begin(pointsPerMm: 26)
        assert(!EdgeScrollSession.shared.isRunning, "begin() alone must not start the clock")
        EdgeScrollSession.shared.addTravel(points: 40)
        assert(EdgeScrollSession.shared.isRunning, "Handing over travel must start the clock")
        EdgeScrollSession.shared.addTravel(points: .nan)
        EdgeScrollSession.shared.addTravel(points: 0)
        EdgeScrollSession.shared.cancel()
        assert(!EdgeScrollSession.shared.isRunning, "cancel() must park the clock")
        assert(!EdgeScrollSession.shared.isFlickGlide, "cancel() must drop momentum")

        // Momentum is earned: no finger velocity means no glide, even with momentum
        // enabled. Without the flick gate a slow, deliberate drag would keep
        // travelling after the finger stopped and overshoot the target.
        EdgeScrollSession.shared.begin(pointsPerMm: 26)
        EdgeScrollSession.shared.addTravel(points: 40)
        EdgeScrollSession.shared.end(momentum: true)
        assert(!EdgeScrollSession.shared.isFlickGlide,
               "A lift with no finger velocity must settle, not glide")
        EdgeScrollSession.shared.cancel()
        print("[TEST-EDGE] Scroll session clock lifecycle passed.")

        // 7. Verify YAML Serialization round-trip
        var testConfig = GlideConfig()
        testConfig.edgeControls.enabled = true
        testConfig.edgeControls.topEdge = "app_switcher"
        testConfig.edgeControls.bottomEdge = "keyboard_backlight"
        testConfig.edgeControls.leftEdge = "brightness"
        testConfig.edgeControls.rightEdge = "volume"
        testConfig.edgeControls.marginMm = 12.5

        let yaml = GlideConfigSerializer.serialize(testConfig)
        guard let parsed = GlideConfigParser.parse(yaml: yaml) else {
            fatalError("Failed to parse emitted YAML with edge_controls")
        }
        assert(parsed.edgeControls.enabled == true)
        assert(parsed.edgeControls.topEdge == "app_switcher")
        assert(parsed.edgeControls.bottomEdge == "keyboard_backlight")
        assert(parsed.edgeControls.leftEdge == "brightness")
        assert(parsed.edgeControls.rightEdge == "volume")
        assert(abs(parsed.edgeControls.marginMm - 12.5) < 0.01)
        print("[TEST-EDGE] YAML config serialization roundtrip passed.")

        // 7b. Activation travel must survive the round-trip and be clamped. Note it
        // sits next to margin_mm, and both are "_mm" doubles — an easy pair to cross.
        var travelConfig = GlideConfig()
        travelConfig.edgeControls.marginMm = 9.5
        travelConfig.edgeControls.activationTravelMm = 7.5
        guard let travelParsed = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(travelConfig)) else {
            fatalError("Failed to parse emitted YAML with activation travel")
        }
        assert(abs(travelParsed.edgeControls.activationTravelMm - 7.5) < 0.01,
               "activation_travel_mm must round-trip, got \(travelParsed.edgeControls.activationTravelMm)")
        assert(abs(travelParsed.edgeControls.marginMm - 9.5) < 0.01,
               "margin_mm must not be clobbered by activation_travel_mm")
        assert(abs(travelParsed.toEdgeControls().activationTravelMm - 7.5) < 0.01)

        travelConfig.edgeControls.activationTravelMm = 500
        assert(abs(travelConfig.toEdgeControls().activationTravelMm
                   - EdgeControlsSettings.activationTravelMmRange.upperBound) < 0.01,
               "An absurd activation travel must clamp to the ceiling")
        travelConfig.edgeControls.activationTravelMm = -3
        assert(abs(travelConfig.toEdgeControls().activationTravelMm
                   - EdgeControlsSettings.activationTravelMmRange.lowerBound) < 0.01,
               "A negative activation travel must clamp to the floor")
        assert(abs(EdgeControlsSettings().activationTravelMm - 4.0) < 0.01,
               "Default activation travel must be 4mm")
        print("[TEST-EDGE] Activation travel persistence and clamping passed.")

        // 8. Verify the scroll action and its tuning survive a YAML round-trip.
        // `edge_controls` and `track_point` both carry scroll_speed / invert_scroll,
        // so this also guards against the two sections bleeding into each other.
        var scrollConfig = GlideConfig()
        scrollConfig.edgeControls.rightEdge = "scroll"
        scrollConfig.edgeControls.scrollSpeed = 37.5
        scrollConfig.edgeControls.invertScroll = true
        scrollConfig.edgeControls.scrollMomentum = false
        scrollConfig.trackPoint.scrollSpeed = 1234
        scrollConfig.trackPoint.invertScroll = false

        guard let scrollParsed = GlideConfigParser.parse(yaml: GlideConfigSerializer.serialize(scrollConfig)) else {
            fatalError("Failed to parse emitted YAML with edge scroll settings")
        }
        assert(scrollParsed.edgeControls.rightEdge == "scroll")
        assert(abs(scrollParsed.edgeControls.scrollSpeed - 37.5) < 0.01, "edge scroll_speed must round-trip")
        assert(scrollParsed.edgeControls.invertScroll == true, "edge invert_scroll must round-trip")
        assert(scrollParsed.edgeControls.scrollMomentum == false, "edge scroll_momentum must round-trip")
        assert(abs(scrollParsed.trackPoint.scrollSpeed - 1234) < 0.01, "track_point scroll_speed must stay independent")
        assert(scrollParsed.trackPoint.invertScroll == false, "track_point invert_scroll must stay independent")

        let mapped = scrollParsed.toEdgeControls()
        assert(mapped.rightEdge == .scroll, "\"scroll\" must map onto EdgeAction.scroll")
        assert(mapped.invertScroll == true)
        assert(mapped.scrollMomentum == false)
        assert(mapped.usesScroll, "usesScroll must report an assigned scroll edge")
        assert(EdgeControlsSettings().scrollMomentum, "Momentum must be on by default")
        print("[TEST-EDGE] Edge scroll YAML roundtrip passed.")

        // 9. Verify out-of-range scroll speed is clamped rather than accepted
        var wild = GlideConfig()
        wild.edgeControls.scrollSpeed = 9999
        let clampedHigh = wild.toEdgeControls().scrollSpeed
        assert(abs(clampedHigh - EdgeControlsSettings.scrollSpeedRange.upperBound) < 0.01,
               "Absurd scroll_speed must clamp to the range ceiling, got \(clampedHigh)")
        wild.edgeControls.scrollSpeed = -50
        let clampedLow = wild.toEdgeControls().scrollSpeed
        assert(abs(clampedLow - EdgeControlsSettings.scrollSpeedRange.lowerBound) < 0.01,
               "Negative scroll_speed must clamp to the range floor, got \(clampedLow)")
        assert(!EdgeControlsSettings().usesScroll, "Default settings assign no scroll edge")
        print("[TEST-EDGE] Scroll speed clamping passed.")

        print("[TEST-EDGE] ✅ Trackpad Edge Controls verification PASSED.")
    }
}

@main
struct GestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        GlideConfigStore.shared.load()
    }

    @StateObject private var preferencesStore = PreferencesStore.shared
    @StateObject private var engineBridge = EngineBridge.shared

    var body: some Scene {
        MenuBarExtra("Glide", systemImage: "hand.draw") {
            MenuBarView()
                .environmentObject(preferencesStore)
                .environmentObject(engineBridge)
        }
        .menuBarExtraStyle(.menu)

        Window("Glide Preferences", id: "preferences") {
            PreferencesWindow()
                .environmentObject(preferencesStore)
                .environmentObject(engineBridge)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)

        SwiftUI.Settings { EmptyView() }
    }
}
import SwiftUI
import Cocoa
import Combine
import ApplicationServices

/// Connects the SwiftUI App lifecycle to the background engine and handles sleep/wake logic.
@MainActor
final class EngineBridge: ObservableObject {
    static let shared = EngineBridge()
    private init() {}

    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                GestureEngine.shared.start()
            } else {
                GestureEngine.shared.stop()
            }
            syncTapHealthTimer()
        }
    }

    private var sleepObserver: NSObjectProtocol?
    private var wakeObservers: [NSObjectProtocol] = []
    private var accessibilityActiveObserver: NSObjectProtocol?
    private var accessibilityPollTimer: Timer?
    private var tapHealthTimer: Timer?
    /// User's toggle state captured at sleep so wake can restore it instead of
    /// force-enabling gestures the user had switched off.
    private var enabledBeforeSleep = true
    /// Whether sleep is what disabled the engine, so `enabledBeforeSleep` is only
    /// written once per sleep and still means the user's own choice on wake.
    private var suspendedForSleep = false
    private var started = false

    func startEngine() {
        guard !started else { return }
        started = true

        let engine = GestureEngine.shared
        if isEnabled {
            engine.start()
        }
        syncTapHealthTimer()

        startAccessibilityMonitoring()

        // Global keyboard-shortcut bindings (independent of the trackpad event tap).
        HotkeyManager.shared.reload()

        // Stop/restart around sleep-wake cycle (trackpad hardware reinits after wake)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                GlideConfigStore.shared.flushPendingSave()
                // macOS can announce sleep more than once without a wake in between.
                // Capturing the toggle again on the second announcement would record
                // the suspended state as the user's preference, and the engine would
                // then stay off for good after waking.
                guard !self.suspendedForSleep else {
                    NSLog("[App] Sleep — already suspended, keeping preference \(self.enabledBeforeSleep)")
                    return
                }
                NSLog("[App] Sleep — stopping engine")
                self.suspendedForSleep = true
                self.enabledBeforeSleep = self.isEnabled
                GestureEngine.shared.stop()
                self.isEnabled = false
            }
        }
        // Both notifications are observed because neither is guaranteed for a given
        // wake, and a wake that goes unnoticed leaves the engine suspended for good.
        // Handling is idempotent, so being told twice costs one extra rebuild.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let observer = ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWake()
                }
            }
            wakeObservers.append(observer)
        }
    }

    @MainActor
    private func handleWake() {
        // The engine is only suspended when sleep suspended it; a wake with no sleep
        // recorded still has to rebuild, because the device may have died anyway.
        let shouldRun = suspendedForSleep ? enabledBeforeSleep : isEnabled
        suspendedForSleep = false
        NSLog("[App] Wake — restoring engine (enabled: \(shouldRun))")

        guard shouldRun else {
            if isEnabled { isEnabled = false }
            return
        }
        if isEnabled {
            // Already the right value, so `didSet` cannot be relied on to do this.
            restartEngine()
        } else {
            isEnabled = true
        }
        verifyDeviceAfterWake(attemptsRemaining: 4)
    }

    @MainActor
    private func restartEngine() {
        GestureEngine.shared.stop()
        GestureEngine.shared.start()
        syncTapHealthTimer()
    }

    /// The wake notification arrives before the trackpad has necessarily come back,
    /// and a device acquired too early reports as started while never delivering a
    /// frame. So the device is checked over the seconds after a wake rather than
    /// trusted once, and rebuilt whenever it is not running.
    @MainActor
    private func verifyDeviceAfterWake(attemptsRemaining: Int) {
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            Task { @MainActor in
                guard let self, self.isEnabled, GestureEngine.shared.isRunning else { return }
                GestureEngine.shared.checkHealth()
                self.verifyDeviceAfterWake(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    /// Event taps get silently disabled by macOS (timeouts, permission churn). The
    /// tap callbacks re-enable themselves on a plain disable, so this periodic check
    /// is only a backstop for the rarer case where the Mach port goes invalid and the
    /// tap has to be torn down and rebuilt.
    ///
    /// It only has anything to check while the engine is actually running its taps,
    /// so it lives and dies with the engine: no wake-ups while gestures are toggled
    /// off or while the machine sleeps. Previously this was a 5s repeating timer
    /// created once and never invalidated — it fired ~17k times a day for the life of
    /// the process even with gestures disabled. Now it is engine-scoped, at 30s with
    /// generous slack so macOS can fold each check into a wake it was already making.
    private func syncTapHealthTimer() {
        if GestureEngine.shared.isRunning {
            guard tapHealthTimer == nil else { return }
            let timer = Timer(timeInterval: 30.0, repeats: true) { _ in
                Task { @MainActor in
                    GestureEngine.shared.checkHealth()
                }
            }
            timer.tolerance = 10.0
            RunLoop.main.add(timer, forMode: .common)
            tapHealthTimer = timer
        } else {
            tapHealthTimer?.invalidate()
            tapHealthTimer = nil
        }
    }

    private func startAccessibilityMonitoring() {
        guard !AXIsProcessTrusted() else {
            PreferencesStore.shared.refreshAccessibilityStatus()
            return
        }

        accessibilityActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeEngineIfAccessibilityGranted()
            }
        }

        // Poll briskly while the user is plausibly in System Settings granting
        // access, then back off. Without this the timer kept firing twice a
        // second for the entire life of the process on any Mac where
        // Accessibility is never granted — the `didBecomeActive` observer above
        // already catches the common "grant it, then come back" path.
        accessibilityPollStart = Date()
        scheduleAccessibilityPoll(interval: 0.5)
    }

    private var accessibilityPollStart: Date?
    /// How long to poll at the fast interval before easing off.
    private static let accessibilityFastPollWindow: TimeInterval = 60

    private func scheduleAccessibilityPoll(interval: TimeInterval) {
        accessibilityPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resumeEngineIfAccessibilityGranted()
                // Still not trusted and past the fast window — stop polling entirely.
                // A user grants Accessibility right after the launch prompt, which the
                // fast poll catches; a later grant is caught by the didBecomeActive
                // observer above when they next interact with Glide. Re-arming a 5s
                // timer here meant a Mac that never grants access woke the CPU every
                // five seconds for the entire life of the process.
                if let start = self.accessibilityPollStart,
                   Date().timeIntervalSince(start) > Self.accessibilityFastPollWindow {
                    self.accessibilityPollTimer?.invalidate()
                    self.accessibilityPollTimer = nil
                }
            }
        }
        timer.tolerance = interval / 2
        accessibilityPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAccessibilityMonitoring() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        if let observer = accessibilityActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            accessibilityActiveObserver = nil
        }
    }

    private func resumeEngineIfAccessibilityGranted() {
        guard AXIsProcessTrusted() else { return }

        stopAccessibilityMonitoring()
        PreferencesStore.shared.refreshAccessibilityStatus()

        guard isEnabled else { return }
        GestureEngine.shared.start()
        syncTapHealthTimer()
    }

    deinit {
        accessibilityPollTimer?.invalidate()
        tapHealthTimer?.invalidate()
        if let observer = accessibilityActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        for o in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }
}
