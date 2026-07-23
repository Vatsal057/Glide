import Cocoa

final class GestureProcessor {
    weak var engine: GestureEngine?
    
    init(engine: GestureEngine) {
        self.engine = engine
    }

    func handleTouches(_ frame: TouchFrameData, phase: GesturePhase, tuning: GestureTuning) -> GesturePhase? {
        let n = Int(frame.count)
        let now = ProcessInfo.processInfo.systemUptime

        switch phase {
        case .idle:
            guard GestureRuleResolver.hasAnySwipeRule(fingers: n) else { return nil }
            if tuning.edgeMarginEnabled {
                let m = tuning.edgeMargin
                if frame.cx < m.left || frame.cx > (1.0 - m.right) || frame.cy < m.bottom || frame.cy > (1.0 - m.top) { return nil }
            }
            return .candidate(CandidateData(
                startX: frame.cx, startY: frame.cy,
                fingers: n, startTime: now,
                initialSpread: frame.spread,
                modifiersAtStart: engine?.captureModifiers() ?? CapturedModifiers(NSEvent.modifierFlags),
                frameCount: 1, cumulativeSpreadDelta: 0,
                prevSpread: frame.spread, minCoherence: frame.coherence,
                prevCx: frame.cx, prevCy: frame.cy,
                movementStartTime: nil, lastFrameTime: now
            ))

        case .candidate(var data):
            if n > data.fingers {
                guard GestureRuleResolver.hasAnySwipeRule(fingers: n) else { return .ignored }
                return .candidate(CandidateData(
                    startX: frame.cx, startY: frame.cy,
                    fingers: n, startTime: now,
                    initialSpread: frame.spread,
                    modifiersAtStart: engine?.captureModifiers() ?? CapturedModifiers(NSEvent.modifierFlags),
                    frameCount: 1, cumulativeSpreadDelta: 0,
                    prevSpread: frame.spread, minCoherence: frame.coherence,
                    prevCx: frame.cx, prevCy: frame.cy,
                    movementStartTime: nil, lastFrameTime: now
                ))
            }
            if n < data.fingers { return .ignored }

            data.frameCount += 1
            let frameDx = frame.cx - data.prevCx
            let frameDy = frame.cy - data.prevCy
            let movedFromStart = ((frame.cx - data.startX) * (frame.cx - data.startX) + (frame.cy - data.startY) * (frame.cy - data.startY)).squareRoot()
            let frameDt = now - data.lastFrameTime
            data.lastFrameTime = now
            if movedFromStart >= max(0.002, tuning.initialThreshold * 0.12) {
                if data.movementStartTime == nil { data.movementStartTime = now }
                let frameDist = (frameDx * frameDx + frameDy * frameDy).squareRoot()
                SpeedClassifier.appendVelocitySample(frameDist / Float(max(frameDt, 0.001)), to: &data.velocitySamples)
            }
            data.prevCx = frame.cx; data.prevCy = frame.cy
            let frameDelta = abs(frame.spread - data.prevSpread)
            data.cumulativeSpreadDelta += frameDelta
            data.prevSpread = frame.spread
            if frame.coherence < data.minCoherence { data.minCoherence = frame.coherence }

            if frameDelta > tuning.pinchFrameSpreadThreshold * 1.5 { return pinchPhase(data, frame: frame, tuning: tuning, now: now) }
            let totalSpreadChange = abs(frame.spread - data.initialSpread)
            if totalSpreadChange > 0.002 && totalSpreadChange > movedFromStart * 0.8 && data.frameCount >= 2 { return pinchPhase(data, frame: frame, tuning: tuning, now: now) }

            let minFrames = max(Int(tuning.candidateFrames), 3)
            guard data.frameCount >= minFrames else { return .candidate(data) }

            if data.gestureKind == .unknown {
                data.classificationFrameDelay += 1
                if data.classificationFrameDelay >= 2 {
                    data.gestureKind = totalSpreadChange > movedFromStart * 0.8 ? .pinch : .swipe
                }
            }
            if data.gestureKind == .pinch { return pinchPhase(data, frame: frame, tuning: tuning, now: now) }
            if totalSpreadChange > 0.002 && totalSpreadChange > movedFromStart * 0.5 { return pinchPhase(data, frame: frame, tuning: tuning, now: now) }
            if data.cumulativeSpreadDelta > tuning.pinchSpreadThreshold { return pinchPhase(data, frame: frame, tuning: tuning, now: now) }
            if data.minCoherence < tuning.swipeCoherenceThreshold { return .ignored }

            if data.cumulativeSpreadDelta < tuning.pinchSpreadThreshold && movedFromStart > totalSpreadChange && data.minCoherence >= tuning.swipeCoherenceThreshold {
                data.gestureKind = .swipe
                let swipeData = SwipeTrackData(
                    startX: data.startX, startY: data.startY, lastX: frame.cx, lastY: frame.cy,
                    fingers: data.fingers, startTime: data.startTime,
                    modifiersAtStart: data.modifiersAtStart, movementStartTime: data.movementStartTime,
                    velocitySamples: data.velocitySamples, lastFrameTime: now,
                    recentDeltas: [], initialSpread: data.initialSpread, prevSpread: frame.spread,
                    cumulativeSpreadDelta: data.cumulativeSpreadDelta, continuousRefX: frame.cx, continuousRefY: frame.cy,
                    lastContinuousActionTime: 0, continuousRule: nil, lockedSpeed: nil
                )
                return .lockedSwipe(swipeData)
            } else if data.frameCount >= minFrames + 5 {
                return .ignored
            } else {
                return .candidate(data)
            }

        case .lockedSwipe(let data):
            guard n == data.fingers else { return nil }
            return processSwipeFrame(frame, data: data, tuning: tuning)

        case .continuousSwipe(let data):
            guard n == data.fingers else { return nil }
            return processContinuousSwipeFrame(frame, data: data, tuning: tuning)

        case .switchingApps(var data):
            guard n == data.fingerCount else { return nil }
            let delta = frame.cx - data.refX
            if abs(delta) > tuning.appSwitcherStepThreshold, now - (engine?.lastStepTime ?? 0) >= tuning.appSwitcherDebounce {
                if delta > 0, data.index < data.effectiveMax {
                    Haptic.switcherStep(); engine?.sendCmdTab()
                    engine?.lastStepTime = now; data.refX = frame.cx; data.index += 1
                    if let fi = data.finderIndex, data.index == fi, data.index < data.effectiveMax {
                        engine?.sendCmdTab(); data.index += 1
                    }
                    return .switchingApps(data)
                } else if delta < 0, data.index > data.effectiveMin {
                    Haptic.switcherStep(); engine?.sendCmdShiftTab()
                    engine?.lastStepTime = now; data.refX = frame.cx; data.index -= 1
                    if let fi = data.finderIndex, data.index == fi, data.index > data.effectiveMin {
                        engine?.sendCmdShiftTab(); data.index -= 1
                    }
                    return .switchingApps(data)
                }
            }
            return .switchingApps(data)

        default: return nil
        }
    }

    /// Pinch-shaped input. With no Glide pinch rule at this finger count the
    /// gesture belongs to the system (its magnify events were never swallowed —
    /// the tap's pinch set doesn't contain this count). With a rule, track
    /// spread until it crosses the pinch threshold, then fire pinch-in/out.
    private func pinchPhase(_ d: CandidateData, frame: TouchFrameData, tuning: GestureTuning, now: TimeInterval) -> GesturePhase {
        var data = d
        data.gestureKind = .pinch
        guard GestureRuleResolver.hasPinchRule(fingers: data.fingers) else {
            return .ignored
        }
        let delta = frame.spread - data.initialSpread
        guard abs(delta) >= tuning.pinchSpreadThreshold else { return .candidate(data) }
        let direction: GestureDirection = delta > 0 ? .pinchOut : .pinchIn
        if engine?.consumeReciprocalToken(fingers: data.fingers, direction: direction, now: now) == true {
            return .fired
        }
        if let rule = GestureRuleResolver.bestRule(fingers: data.fingers, direction: direction,
                                                   modifiers: data.modifiersAtStart) {
            engine?.executeSwipeRule(rule, fingers: data.fingers, direction: direction)
            return .fired
        }
        // Pinch rule exists at this count but not for this in/out direction —
        // keep tracking in case the pinch reverses before the fingers lift.
        return .candidate(data)
    }

    private func processSwipeFrame(_ frame: TouchFrameData, data: SwipeTrackData, tuning: GestureTuning) -> GesturePhase {
        var updated = data
        let now = ProcessInfo.processInfo.systemUptime
        let frameDx = frame.cx - data.lastX
        let frameDy = frame.cy - data.lastY
        let frameDist = (frameDx * frameDx + frameDy * frameDy).squareRoot()
        updated.lastX = frame.cx; updated.lastY = frame.cy
        updated.cumulativeSpreadDelta += abs(frame.spread - updated.prevSpread)
        updated.prevSpread = frame.spread

        let swipeCentroidMovement = ((frame.cx - updated.startX) * (frame.cx - updated.startX) + (frame.cy - updated.startY) * (frame.cy - updated.startY)).squareRoot()
        if abs(frame.spread - updated.initialSpread) > 0.003 && abs(frame.spread - updated.initialSpread) > swipeCentroidMovement * 0.8 {
            return .ignored
        }

        if updated.movementStartTime == nil, frameDist > 0 {
            updated.movementStartTime = now
        }
        let frameDt = now - updated.lastFrameTime
        updated.lastFrameTime = now
        SpeedClassifier.appendVelocitySample(frameDist / Float(max(frameDt, 0.001)), to: &updated.velocitySamples)
        updated.recentDeltas.insert((dx: frameDx, dy: frameDy), at: 0)

        var totalDx: Float = 0, totalDy: Float = 0
        var thresholdIndex: Int?
        for (i, d) in updated.recentDeltas.enumerated() {
            totalDx += d.dx; totalDy += d.dy
            if (totalDx * totalDx + totalDy * totalDy).squareRoot() >= tuning.initialThreshold {
                thresholdIndex = i; break
            }
        }
        guard let cutoff = thresholdIndex else { return .lockedSwipe(updated) }
        if cutoff + 1 < updated.recentDeltas.count { updated.recentDeltas.removeSubrange((cutoff + 1)...) }

        let angleDeg = atan2(totalDy, totalDx) * (180.0 / .pi)
        let angle360 = angleDeg < 0 ? angleDeg + 360 : angleDeg
        guard let direction = GestureDirection.fromAngle(angle360, tolerance: tuning.swipeAngleTolerance) else { return .lockedSwipe(updated) }

        if engine?.consumeReciprocalToken(fingers: data.fingers, direction: direction, now: now) == true {
            return .fired
        }

        let candidateRules = GestureRuleResolver.matchingRules(fingers: data.fingers, direction: direction, modifiers: updated.modifiersAtStart)
        if updated.lockedSpeed == nil {
            let configuredSpeeds = Set(candidateRules.map { $0.speed == .any ? GestureSpeed.normal : $0.speed })
            let elapsed = max(now - (updated.movementStartTime ?? updated.startTime), 0.001)
            // Per-frame tuning thresholds date from a fixed-60fps assumption; ×60 converts
            // them to widths/second so existing user settings keep their meaning.
            let slowMax = tuning.slowVelocityThreshold * 60
            let fastMin = tuning.fastVelocityThreshold * 60
            let intent: GestureSpeed?
            switch tuning.speedLogic {
            case .simple:
                intent = SpeedClassifier.classify(
                    totalDisplacement: swipeCentroidMovement,
                    elapsedSeconds: elapsed,
                    configuredSpeeds: configuredSpeeds,
                    slowMax: slowMax,
                    fastMin: fastMin
                )
            case .classic:
                intent = SpeedClassifier.classifyClassic(
                    velocitySamples: updated.velocitySamples,
                    totalDisplacement: swipeCentroidMovement,
                    elapsedSeconds: elapsed,
                    configuredSpeeds: configuredSpeeds,
                    slowMax: slowMax,
                    fastMin: fastMin,
                    initialDistance: tuning.initialThreshold
                )
            }
            guard let intent else { return .lockedSwipe(updated) }
            updated.lockedSpeed = intent
        }
        let speed = updated.lockedSpeed ?? .normal

        if abs(frame.spread - updated.initialSpread) >= tuning.pinchSpreadThreshold * 0.8 || frame.coherence < max(tuning.swipeCoherenceThreshold, 0.55) { return .ignored }

        if let rule = GestureRuleResolver.bestRule(fingers: data.fingers, direction: direction, speed: speed, modifiers: updated.modifiersAtStart) {
            if rule.continuous {
                engine?.executeGestureRuleAction(rule)
                engine?.clearReciprocalToken()
                updated.continuousRefX = frame.cx; updated.continuousRefY = frame.cy; updated.lastContinuousActionTime = now; updated.continuousRule = rule
                return .continuousSwipe(updated)
            } else {
                engine?.executeSwipeRule(rule, fingers: data.fingers, direction: direction)
                return .fired
            }
        } else if let switcherAction = GestureRuleResolver.appSwitcherAction(fingers: data.fingers, direction: direction, modifiers: updated.modifiersAtStart) {
            if let switcherData = engine?.beginAppSwitcher(for: switcherAction, refX: frame.cx, fingerCount: data.fingers) {
                return .switchingApps(switcherData)
            } else {
                return .fired
            }
        }
        return .fired
    }

    private func processContinuousSwipeFrame(_ frame: TouchFrameData, data: SwipeTrackData, tuning: GestureTuning) -> GesturePhase {
        var updated = data
        let now = ProcessInfo.processInfo.systemUptime
        updated.lastX = frame.cx; updated.lastY = frame.cy
        updated.prevSpread = frame.spread

        let swipeCentroidMovement = ((frame.cx - updated.startX) * (frame.cx - updated.startX) + (frame.cy - updated.startY) * (frame.cy - updated.startY)).squareRoot()
        if abs(frame.spread - updated.initialSpread) > 0.003 && abs(frame.spread - updated.initialSpread) > swipeCentroidMovement * 0.8 {
            engine?.executeContinuousEndAction(for: updated); return .ignored
        }

        let dx = frame.cx - updated.continuousRefX
        let dy = frame.cy - updated.continuousRefY
        guard (dx * dx + dy * dy).squareRoot() >= tuning.continuousStepThreshold else { return .continuousSwipe(updated) }

        let angleDeg = atan2(dy, dx) * (180.0 / .pi)
        let angle360 = angleDeg < 0 ? angleDeg + 360 : angleDeg
        guard let direction = GestureDirection.fromAngle(angle360, tolerance: tuning.swipeAngleTolerance) else {
            updated.continuousRefX = frame.cx; updated.continuousRefY = frame.cy; return .continuousSwipe(updated)
        }

        guard now - updated.lastContinuousActionTime >= tuning.continuousDebounce else { return .continuousSwipe(updated) }

        if let rule = updated.continuousRule, direction.matchesAxis(of: rule.direction) {
            let action = engine?.continuousUpdateAction(for: direction, in: rule) ?? .doNothing
            if action != .doNothing {
                engine?.executeContinuousAction(action, shortcut: engine?.continuousUpdateShortcut(for: direction, in: rule), keyboard: engine?.continuousUpdateKeyboard(for: direction, in: rule) ?? [])
            }
            updated.lastContinuousActionTime = now
        }
        updated.continuousRefX = frame.cx; updated.continuousRefY = frame.cy
        return .continuousSwipe(updated)
    }
}
