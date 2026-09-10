import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - GestureAnimationView
//
// A macOS native-styled animated preview for trackpad gestures, matching
// the visual language of System Settings → Trackpad.
//
// Displays:
//   - An authentic trackpad glass surface with subtle borders and depth
//   - Active zone indicators for restricted sectors (.topLeft, .bottomEdge, etc.)
//   - Natural ergonomic finger dot clusters (3, 4, or 5 fingers)
//   - Speed variations (.slow, .normal, .fast) with variable velocities, cycle
//     durations, and high-speed motion blur / ghost trails
//   - Continuous back-and-forth scrub mode for continuous gesture rules
//   - Click and force-click tactile ripple pulses
//   - Animated modifier keycaps (⇧, ⌃, ⌥, ⌘) when required
//   - Associated destination action pill with icon and title
//   - Accessibility support: respects Reduce Motion
// ─────────────────────────────────────────────────────────────────────────────

struct GestureAnimationView: View {
    var direction: GestureDirection
    var fingerCount: Int
    var zone: TrackpadZone
    var modifierFilter: ModifierFilter
    var speed: GestureSpeed
    var continuous: Bool
    var action: GestureAction
    var showLabel: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Dimensions calibrated to match macOS System Settings preview aspect ratio
    private let trackpadWidth: CGFloat = 218
    private let trackpadHeight: CGFloat = 138

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Initializers
    // ─────────────────────────────────────────────────────────────────────────

    init(
        rule: GestureRule,
        showLabel: Bool = true
    ) {
        self.direction = rule.direction
        self.fingerCount = rule.fingers
        self.zone = rule.zone
        self.modifierFilter = rule.modifierFilter
        self.speed = rule.speed
        self.continuous = rule.continuous
        self.action = rule.action
        self.showLabel = showLabel
    }

    init(
        direction: GestureDirection,
        fingerCount: Int,
        zone: TrackpadZone = .any,
        modifierFilter: ModifierFilter = .any,
        speed: GestureSpeed = .normal,
        continuous: Bool = false,
        action: GestureAction = .doNothing,
        showLabel: Bool = true
    ) {
        self.direction = direction
        self.fingerCount = fingerCount
        self.zone = zone
        self.modifierFilter = modifierFilter
        self.speed = speed
        self.continuous = continuous
        self.action = action
        self.showLabel = showLabel
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Cycle Duration & Speed
    // ─────────────────────────────────────────────────────────────────────────

    private var cycleDuration: Double {
        guard direction.hasSpeed else { return 2.4 }
        switch speed {
        case .slow:   return 3.4
        case .normal: return 2.2
        case .fast:   return 1.35
        case .any:    return 2.2
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background trackpad container card
                trackpadChassis

                // Active zone highlight overlay (when restricted to a sector)
                if zone != .any {
                    zoneOverlay
                }

                // Animated finger cluster and ripples
                if reduceMotion {
                    staticGestureContent
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                        let time = context.date.timeIntervalSinceReferenceDate
                        let progress = (time.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
                        animatedGestureContent(progress: progress)
                    }
                }

                // Top badges overlay (speed badge and modifier keycap)
                topBadgesOverlay
            }
            .frame(width: trackpadWidth, height: trackpadHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if showLabel {
                gestureSummaryLabel
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Top Badges Overlay
    // ─────────────────────────────────────────────────────────────────────────

    private var topBadgesOverlay: some View {
        HStack(alignment: .top) {
            HStack(spacing: 4) {
                if continuous && (direction == .swipeLeftRight || direction == .swipeUpDown) {
                    continuousBadge
                }
                if direction.hasSpeed {
                    speedBadge
                }
            }

            Spacer()

            // Modifier keycap badge (when modifier key is required)
            if modifierFilter.requiresModifierHeld, let mod = modifierInfo {
                modifierKeycap(symbol: mod.symbol, name: mod.name)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var speedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: speedIconName)
                .font(.system(size: 8.5, weight: .bold))
            Text(speed.rawValue.capitalized)
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(speedColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(speedColor.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(speedColor.opacity(0.25), lineWidth: 0.8)
        )
    }

    private var continuousBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 8.5, weight: .bold))
            Text("Continuous")
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.8))
    }

    private var speedIconName: String {
        switch speed {
        case .slow:   return "tortoise.fill"
        case .normal: return "gauge.with.needle"
        case .fast:   return "bolt.fill"
        case .any:    return "gauge.with.needle"
        }
    }

    private var speedColor: Color {
        switch speed {
        case .slow:   return .indigo
        case .normal: return .secondary
        case .fast:   return .orange
        case .any:    return .secondary
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Trackpad Chassis
    // ─────────────────────────────────────────────────────────────────────────

    private var trackpadChassis: some View {
        ZStack {
            // Trackpad glass surface with subtle native gradient
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(0.85),
                            Color(nsColor: .windowBackgroundColor).opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Inner surface depth shadow
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)

            // Top highlight reflection
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                Spacer()
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1.5)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Zone Overlay
    // ─────────────────────────────────────────────────────────────────────────

    private var zoneOverlay: some View {
        let size = CGSize(width: trackpadWidth, height: trackpadHeight)
        let rect = zoneRect(in: size)

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Zone tag anchored in bottom-leading corner of zone
            VStack {
                Spacer()
                HStack {
                    Text(zone.rawValue)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    Spacer()
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .padding(4)
        }
    }

    private func zoneRect(in size: CGSize) -> CGRect {
        let reachX: CGFloat = size.width * 0.46
        let reachY: CGFloat = size.height * 0.48

        switch zone {
        case .any:
            return CGRect(origin: .zero, size: size)
        case .topLeft:
            return CGRect(x: 5, y: 5, width: reachX, height: reachY)
        case .topRight:
            return CGRect(x: size.width - reachX - 5, y: 5, width: reachX, height: reachY)
        case .bottomLeft:
            return CGRect(x: 5, y: size.height - reachY - 5, width: reachX, height: reachY)
        case .bottomRight:
            return CGRect(x: size.width - reachX - 5, y: size.height - reachY - 5, width: reachX, height: reachY)
        case .topEdge:
            return CGRect(x: 5, y: 5, width: size.width - 10, height: size.height * 0.40)
        case .bottomEdge:
            return CGRect(x: 5, y: size.height - size.height * 0.40 - 5, width: size.width - 10, height: size.height * 0.40)
        case .leftEdge:
            return CGRect(x: 5, y: 5, width: size.width * 0.40, height: size.height - 10)
        case .rightEdge:
            return CGRect(x: size.width - size.width * 0.40 - 5, y: 5, width: size.width * 0.40, height: size.height - 10)
        }
    }

    private var zoneCenterOffset: CGSize {
        let size = CGSize(width: trackpadWidth, height: trackpadHeight)
        let rect = zoneRect(in: size)
        return CGSize(
            width: rect.midX - size.width / 2,
            height: rect.midY - size.height / 2
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Animated Gesture Rendering
    // ─────────────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func animatedGestureContent(progress: Double) -> some View {
        let state = computeMotionState(progress: progress)

        ZStack {
            // Ripple effects for clicks and taps
            if state.rippleRadius > 0 && state.rippleOpacity > 0 {
                Circle()
                    .stroke(Color.accentColor.opacity(state.rippleOpacity), lineWidth: 1.5)
                    .frame(width: state.rippleRadius * 2, height: state.rippleRadius * 2)
                    .offset(x: state.clusterOffset.width + zoneCenterOffset.width,
                            y: state.clusterOffset.height + zoneCenterOffset.height)
            }

            if state.secondaryRippleRadius > 0 && state.secondaryRippleOpacity > 0 {
                Circle()
                    .stroke(Color.accentColor.opacity(state.secondaryRippleOpacity), lineWidth: 2)
                    .frame(width: state.secondaryRippleRadius * 2, height: state.secondaryRippleRadius * 2)
                    .offset(x: state.clusterOffset.width + zoneCenterOffset.width,
                            y: state.clusterOffset.height + zoneCenterOffset.height)
            }

            // High-speed ghost trails when moving fast
            if speed == .fast && state.isMoving && direction.hasSpeed {
                ghostTrail(offset: state.clusterOffset, velocityVector: state.velocityVector, opacity: state.opacity)
                    .offset(x: zoneCenterOffset.width, y: zoneCenterOffset.height)
            }

            // Finger dot cluster
            fingerCluster(scale: state.dotScale, opacity: state.opacity)
                .offset(x: state.clusterOffset.width + zoneCenterOffset.width,
                        y: state.clusterOffset.height + zoneCenterOffset.height)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Motion State Computation
    // ─────────────────────────────────────────────────────────────────────────

    private struct MotionState {
        var clusterOffset: CGSize = .zero
        var velocityVector: CGSize = .zero
        var isMoving: Bool = false
        var dotScale: CGFloat = 1.0
        var opacity: Double = 1.0
        var rippleRadius: CGFloat = 0.0
        var rippleOpacity: Double = 0.0
        var secondaryRippleRadius: CGFloat = 0.0
        var secondaryRippleOpacity: Double = 0.0
    }

    private func computeMotionState(progress: Double) -> MotionState {
        var state = MotionState()

        let isZoned = zone != .any
        let swipeSpan: CGFloat = isZoned ? 16.0 : 36.0
        let verticalSpan: CGFloat = isZoned ? 10.0 : 22.0

        switch direction {
        case .click:
            if progress < 0.15 {
                let p = progress / 0.15
                state.opacity = p
                state.dotScale = 0.8 + 0.2 * p
            } else if progress < 0.35 {
                let p = (progress - 0.15) / 0.20
                state.dotScale = 1.0 - 0.15 * sin(p * .pi)
            } else if progress < 0.75 {
                let p = (progress - 0.35) / 0.40
                state.dotScale = 1.0
                state.rippleRadius = 14 + 28 * CGFloat(p)
                state.rippleOpacity = 0.7 * (1.0 - p)
            } else if progress < 0.90 {
                let p = (progress - 0.75) / 0.15
                state.opacity = 1.0 - p
                state.dotScale = 1.0 + 0.1 * p
            } else {
                state.opacity = 0
            }

        case .forceClick:
            if progress < 0.12 {
                let p = progress / 0.12
                state.opacity = p
                state.dotScale = 0.8 + 0.2 * p
            } else if progress < 0.30 {
                let p = (progress - 0.12) / 0.18
                state.dotScale = 1.0 - 0.12 * sin(p * .pi)
                state.rippleRadius = 12 + 18 * CGFloat(p)
                state.rippleOpacity = 0.5 * (1.0 - p)
            } else if progress < 0.45 {
                let p = (progress - 0.30) / 0.15
                state.dotScale = 1.0 - 0.25 * sin(p * .pi)
            } else if progress < 0.80 {
                let p = (progress - 0.45) / 0.35
                state.dotScale = 0.85 + 0.15 * p
                state.secondaryRippleRadius = 16 + 36 * CGFloat(p)
                state.secondaryRippleOpacity = 0.85 * (1.0 - p)
            } else if progress < 0.92 {
                let p = (progress - 0.80) / 0.12
                state.opacity = 1.0 - p
            } else {
                state.opacity = 0
            }

        case .tapHold:
            if progress < 0.15 {
                let p = progress / 0.15
                state.opacity = p
            } else if progress < 0.80 {
                state.opacity = 1.0
                let p = (progress - 0.15) / 0.65
                let breathe = sin(p * .pi * 4)
                state.dotScale = 1.0 + 0.05 * breathe
                state.rippleRadius = 20 + 6 * CGFloat(breathe)
                state.rippleOpacity = 0.25 + 0.15 * breathe
            } else if progress < 0.92 {
                let p = (progress - 0.80) / 0.12
                state.opacity = 1.0 - p
            } else {
                state.opacity = 0
            }

        case .swipeLeft:
            applyUnidirectionalSwipe(progress: progress, span: -swipeSpan, isHorizontal: true, state: &state)

        case .swipeRight:
            applyUnidirectionalSwipe(progress: progress, span: swipeSpan, isHorizontal: true, state: &state)

        case .swipeUp:
            applyUnidirectionalSwipe(progress: progress, span: -verticalSpan, isHorizontal: false, state: &state)

        case .swipeDown:
            applyUnidirectionalSwipe(progress: progress, span: verticalSpan, isHorizontal: false, state: &state)

        case .swipeLeftRight:
            if continuous {
                // Unbroken continuous scrub: left -> pause -> right -> pause
                state.opacity = 1.0
                let cycle = progress.truncatingRemainder(dividingBy: 1.0)
                if cycle < 0.44 {
                    let p = cycle / 0.44
                    let ease = smoothStep(p)
                    let x = swipeSpan * 0.85 * (1.0 - 2 * CGFloat(ease))
                    state.clusterOffset = CGSize(width: x, height: 0)
                    state.isMoving = true
                    state.velocityVector = CGSize(width: -1, height: 0)
                } else if cycle < 0.50 {
                    state.clusterOffset = CGSize(width: -swipeSpan * 0.85, height: 0)
                } else if cycle < 0.94 {
                    let p = (cycle - 0.50) / 0.44
                    let ease = smoothStep(p)
                    let x = -swipeSpan * 0.85 * (1.0 - 2 * CGFloat(ease))
                    state.clusterOffset = CGSize(width: x, height: 0)
                    state.isMoving = true
                    state.velocityVector = CGSize(width: 1, height: 0)
                } else {
                    state.clusterOffset = CGSize(width: swipeSpan * 0.85, height: 0)
                }
            } else {
                // Discrete two-way swipe cycle
                applyUnidirectionalSwipe(progress: progress, span: swipeSpan, isHorizontal: true, state: &state)
            }

        case .swipeUpDown:
            if continuous {
                // Unbroken continuous scrub: up -> pause -> down -> pause
                state.opacity = 1.0
                let cycle = progress.truncatingRemainder(dividingBy: 1.0)
                if cycle < 0.44 {
                    let p = cycle / 0.44
                    let ease = smoothStep(p)
                    let y = verticalSpan * 0.85 * (1.0 - 2 * CGFloat(ease))
                    state.clusterOffset = CGSize(width: 0, height: y)
                    state.isMoving = true
                    state.velocityVector = CGSize(width: 0, height: -1)
                } else if cycle < 0.50 {
                    state.clusterOffset = CGSize(width: 0, height: -verticalSpan * 0.85)
                } else if cycle < 0.94 {
                    let p = (cycle - 0.50) / 0.44
                    let ease = smoothStep(p)
                    let y = -verticalSpan * 0.85 * (1.0 - 2 * CGFloat(ease))
                    state.clusterOffset = CGSize(width: 0, height: y)
                    state.isMoving = true
                    state.velocityVector = CGSize(width: 0, height: 1)
                } else {
                    state.clusterOffset = CGSize(width: 0, height: verticalSpan * 0.85)
                }
            } else {
                applyUnidirectionalSwipe(progress: progress, span: -verticalSpan, isHorizontal: false, state: &state)
            }
        }

        return state
    }

    /// Calculates trajectory, velocity curve, and timing windows calibrated to the speed setting
    private func applyUnidirectionalSwipe(
        progress: Double,
        span: CGFloat,
        isHorizontal: Bool,
        state: inout MotionState
    ) {
        // Speed parameters:
        // Slow:   long glide window (0.08 .. 0.85)
        // Normal: standard window   (0.12 .. 0.70)
        // Fast:   rapid flick window (0.10 .. 0.45) followed by quick lift
        let startMotion: Double
        let endMotion: Double

        switch speed {
        case .slow:
            startMotion = 0.08
            endMotion   = 0.85
        case .normal, .any:
            startMotion = 0.12
            endMotion   = 0.70
        case .fast:
            startMotion = 0.10
            endMotion   = 0.44
        }

        let fadeWindow: Double = (speed == .fast) ? 0.12 : 0.14
        let startPos = -span
        let endPos = span

        if progress < startMotion {
            let p = progress / startMotion
            state.opacity = p
            let offset = startPos
            state.clusterOffset = isHorizontal ? CGSize(width: offset, height: 0) : CGSize(width: 0, height: offset)
        } else if progress < endMotion {
            let p = (progress - startMotion) / (endMotion - startMotion)
            let curve: Double
            switch speed {
            case .slow:
                // Steady, gradual glide
                curve = smoothStep(p)
            case .normal, .any:
                curve = smoothStep(p)
            case .fast:
                // Snappy flick: rapid acceleration with deceleration
                curve = 1.0 - pow(1.0 - p, 3.8)
            }

            let currentPos = startPos + (endPos - startPos) * CGFloat(curve)
            state.opacity = 1.0
            state.isMoving = true
            state.clusterOffset = isHorizontal ? CGSize(width: currentPos, height: 0) : CGSize(width: 0, height: currentPos)

            let sign: CGFloat = span > 0 ? 1 : -1
            state.velocityVector = isHorizontal ? CGSize(width: sign, height: 0) : CGSize(width: 0, height: sign)
        } else if progress < endMotion + fadeWindow {
            let p = (progress - endMotion) / fadeWindow
            state.opacity = 1.0 - p
            state.clusterOffset = isHorizontal ? CGSize(width: endPos, height: 0) : CGSize(width: 0, height: endPos)
        } else {
            state.opacity = 0
            state.clusterOffset = isHorizontal ? CGSize(width: endPos, height: 0) : CGSize(width: 0, height: endPos)
        }
    }

    private func smoothStep(_ x: Double) -> Double {
        let clamped = max(0.0, min(1.0, x))
        return clamped * clamped * (3.0 - 2.0 * clamped)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - High-Speed Ghost Trail
    // ─────────────────────────────────────────────────────────────────────────

    private func ghostTrail(offset: CGSize, velocityVector: CGSize, opacity: Double) -> some View {
        let trail1Lag: CGFloat = 8.0
        let trail2Lag: CGFloat = 16.0

        return ZStack {
            fingerCluster(scale: 0.88, opacity: opacity * 0.28)
                .offset(
                    x: offset.width - velocityVector.width * trail1Lag,
                    y: offset.height - velocityVector.height * trail1Lag
                )

            fingerCluster(scale: 0.76, opacity: opacity * 0.14)
                .offset(
                    x: offset.width - velocityVector.width * trail2Lag,
                    y: offset.height - velocityVector.height * trail2Lag
                )
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Finger Dot Cluster
    // ─────────────────────────────────────────────────────────────────────────

    private func fingerCluster(scale: CGFloat, opacity: Double) -> some View {
        let positions = fingerOffsets(count: fingerCount)

        return ZStack {
            ForEach(0..<positions.count, id: \.self) { idx in
                let pos = positions[idx]
                singleFingerDot
                    .scaleEffect(scale)
                    .offset(x: pos.x, y: pos.y)
            }
        }
        .opacity(opacity)
    }

    private var singleFingerDot: some View {
        ZStack {
            // Soft outer halo
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 22, height: 22)

            // Tactile dot body
            Circle()
                .fill(Color.accentColor.opacity(0.40))
                .frame(width: 15, height: 15)

            // Crisp perimeter stroke
            Circle()
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                .frame(width: 15, height: 15)

            // Inner touch center
            Circle()
                .fill(Color.white)
                .frame(width: 3.5, height: 3.5)
        }
        .shadow(color: Color.accentColor.opacity(0.3), radius: 2, x: 0, y: 1)
    }

    /// Ergonomic finger placement arcs resembling natural hand postures
    private func fingerOffsets(count: Int) -> [CGPoint] {
        switch count {
        case 3:
            return [
                CGPoint(x: -18, y: 2),   // Index
                CGPoint(x: 0, y: -4),    // Middle (slightly elevated)
                CGPoint(x: 18, y: 2)     // Ring
            ]
        case 4:
            return [
                CGPoint(x: -26, y: 2),   // Index
                CGPoint(x: -9, y: -4),   // Middle
                CGPoint(x: 9, y: -3),    // Ring
                CGPoint(x: 26, y: 4)     // Pinky
            ]
        case 5:
            return [
                CGPoint(x: -34, y: 14),  // Thumb (lower left)
                CGPoint(x: -19, y: 0),   // Index
                CGPoint(x: -4, y: -6),   // Middle
                CGPoint(x: 12, y: -3),   // Ring
                CGPoint(x: 28, y: 4)     // Pinky
            ]
        default:
            return [
                CGPoint(x: -18, y: 2),
                CGPoint(x: 0, y: -4),
                CGPoint(x: 18, y: 2)
            ]
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Reduce Motion Static Fallback
    // ─────────────────────────────────────────────────────────────────────────

    private var staticGestureContent: some View {
        ZStack {
            fingerCluster(scale: 1.0, opacity: 1.0)
                .offset(x: zoneCenterOffset.width, y: zoneCenterOffset.height)

            // Directional glyph overlay when motion is reduced
            Image(systemName: direction.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .offset(x: zoneCenterOffset.width, y: zoneCenterOffset.height + 26)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Modifier Keycap
    // ─────────────────────────────────────────────────────────────────────────

    private var modifierInfo: (symbol: String, name: String)? {
        switch modifierFilter {
        case .shiftHeld:   return ("⇧", "Shift")
        case .controlHeld: return ("⌃", "Control")
        case .optionHeld:  return ("⌥", "Option")
        case .commandHeld: return ("⌘", "Command")
        default:           return nil
        }
    }

    private func modifierKeycap(symbol: String, name: String) -> some View {
        HStack(spacing: 3) {
            Text(symbol)
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Text(name)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Gesture Summary Label
    // ─────────────────────────────────────────────────────────────────────────

    private var gestureSummaryLabel: some View {
        HStack(spacing: 6) {
            // Trigger summary
            HStack(spacing: 4) {
                if modifierFilter.requiresModifierHeld, let mod = modifierInfo {
                    Text(mod.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text("\(fingerCount)-finger \(direction.rawValue.lowercased())")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if direction.hasSpeed {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(speed.rawValue.capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(speedColor)
                }

                if zone != .any {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(zone.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Destination action indicator
            if action != .doNothing {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 3) {
                    Image(systemName: action.iconName)
                        .font(.system(size: 10))
                    Text(action.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
