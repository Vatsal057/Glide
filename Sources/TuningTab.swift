import SwiftUI

struct TuningTab: View {
    @EnvironmentObject var store: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                TuningSection(title: "Recognition", icon: "waveform.path") {
                    SliderRow(
                        label: "Initial Threshold",
                        value: binding(\.initialThreshold),
                        range: 0.005...0.05,
                        format: "%.3f",
                        hint: "How far fingers must travel before registering as a swipe."
                    )
                    SliderRow(
                        label: "Continuous Step Distance",
                        value: binding(\.continuousStepThreshold),
                        range: 0.005...0.08,
                        format: "%.3f",
                        hint: "How far a continuous swipe must travel before repeating another action."
                    )
                    SliderRow(
                        label: "Continuous Debounce",
                        value: binding(\.continuousDebounce),
                        range: 0.0...0.25,
                        format: "%.2fs",
                        hint: "Minimum time between repeated continuous actions."
                    )
                }

                TuningSection(title: "Speed Classification", icon: "speedometer") {
                    SliderRow(
                        label: "Fast Velocity Threshold",
                        value: binding(\.fastVelocityThreshold),
                        range: 0.004...0.02,
                        format: "%.3f",
                        hint: "Speed above which a swipe is classified as Fast."
                    )
                    SliderRow(
                        label: "Slow Velocity Threshold",
                        value: binding(\.slowVelocityThreshold),
                        range: 0.001...0.008,
                        format: "%.3f",
                        hint: "Speed below which a swipe is classified as Slow."
                    )
                    StepperRow(
                        label: "Speed Sample Frames",
                        value: binding(\.speedSampleCount),
                        range: 2...20,
                        hint: "Number of frames averaged to compute swipe speed. Higher = smoother."
                    )
                }

                TuningSection(title: "Direction Detection", icon: "arrow.up.left.and.arrow.down.right") {
                    SliderRow(
                        label: "Angle Tolerance",
                        value: binding(\.swipeAngleTolerance),
                        range: 20...45,
                        format: "%.0f°",
                        hint: "Half-width of the direction cone. 45° = equal quarters. Lower = stricter."
                    )

                    AngleToleranceCompass(angleDegrees: Double(store.tuning.swipeAngleTolerance))
                        .frame(height: 200)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }

                TuningSection(title: "Pinch Veto", icon: "hand.pinch") {
                    StepperRow(
                        label: "Candidate Frames",
                        value: binding(\.candidateFrames),
                        range: 1...12,
                        hint: "Frames analyzed at touch start before committing to a swipe."
                    )
                    SliderRow(
                        label: "Pinch Spread Threshold",
                        value: binding(\.pinchSpreadThreshold),
                        range: 0.01...0.2,
                        format: "%.3f",
                        hint: "Total finger spread limit. Exceeded → assume pinch, cancel swipe."
                    )
                    SliderRow(
                        label: "Pinch Frame Spread Threshold",
                        value: binding(\.pinchFrameSpreadThreshold),
                        range: 0.005...0.1,
                        format: "%.3f",
                        hint: "Per-frame spread limit. Fast pinch instantly cancels detection."
                    )
                    SliderRow(
                        label: "Swipe Coherence",
                        value: binding(\.swipeCoherenceThreshold),
                        range: 0.5...1.0,
                        format: "%.2f",
                        hint: "How uniformly fingers must move. 1.0 = all exactly aligned."
                    )
                }

                TuningSection(title: "Trackpad Edge Margins", icon: "rectangle.inset.filled") {
                    Toggle("Enable Edge Margins", isOn: binding(\.edgeMarginEnabled))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    if store.tuning.edgeMarginEnabled {
                        // EdgeMargin stores 0.0–0.20 fractions; display/edit as 0–20 %
                        marginSlider(label: "Left Margin",   keyPath: \.edgeMargin.left)
                        marginSlider(label: "Right Margin",  keyPath: \.edgeMargin.right)
                        marginSlider(label: "Top Margin",    keyPath: \.edgeMargin.top)
                        marginSlider(label: "Bottom Margin", keyPath: \.edgeMargin.bottom)

                        TrackpadPreview(
                            marginLeft:   Double(store.tuning.edgeMargin.left),
                            marginRight:  Double(store.tuning.edgeMargin.right),
                            marginTop:    Double(store.tuning.edgeMargin.top),
                            marginBottom: Double(store.tuning.edgeMargin.bottom)
                        )
                        .frame(height: 180)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }

                resetSection
            }
            .padding()
        }
    }

    // MARK: - Bindings

    private func binding<T>(_ keyPath: WritableKeyPath<GestureTuning, T>) -> Binding<T> {
        Binding(
            get: { store.tuning[keyPath: keyPath] },
            set: { newValue in store.updateTuning { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// Margin stored as fraction 0.0–0.20, slider displays 0–20 %.
    @ViewBuilder
    private func marginSlider(label: String, keyPath: WritableKeyPath<GestureTuning, Float>) -> some View {
        let percentBinding = Binding<Double>(
            get: { Double(store.tuning[keyPath: keyPath]) * 100 },
            set: { newValue in store.updateTuning { $0[keyPath: keyPath] = Float(newValue / 100) } }
        )
        SliderRow(
            label: label,
            value: percentBinding,
            range: 0...20,
            format: "%.0f%%",
            hint: "Ignore touches starting in this edge zone (0 – 20 %)."
        )
    }

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset All to Defaults") {
                withAnimation {
                    store.resetTuning()
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Tuning Section

struct TuningSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.headline)
                .padding(.bottom, 2)

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Slider Row

struct SliderRow<T: BinaryFloatingPoint>: View {
    let label: String
    @Binding var value: T
    let range: ClosedRange<T>
    let format: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .frame(width: 190, alignment: .leading)
                Slider(value: Binding(get: { Double(value) }, set: { value = T($0) }), in: Double(range.lowerBound)...Double(range.upperBound))
                    .frame(maxWidth: 260)
                Text(String(format: format, Double(value)))
                    .monospacedDigit()
                    .frame(width: 75, alignment: .trailing)
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 194)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Stepper Row

struct StepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .frame(width: 190, alignment: .leading)
                Stepper(value: $value, in: range) {
                    Text("\(value)")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 194)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Angle Tolerance Compass

struct AngleToleranceCompass: View {
    let angleDegrees: Double   // half-width of each cone (20–45)

    private struct DirectionInfo {
        let angle: Double   // math angle in radians (0=right, CCW positive)
        let label: String
        let color: Color
    }

    private var directions: [DirectionInfo] {
        [
            DirectionInfo(angle:  .pi / 2, label: "Up",    color: .blue),
            DirectionInfo(angle: -.pi / 2, label: "Down",  color: .purple),
            DirectionInfo(angle:  .pi,     label: "Left",  color: .green),
            DirectionInfo(angle:  0,       label: "Right", color: .orange),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let size   = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.40
            let rad    = angleDegrees * .pi / 180
            let halfDead = (.pi / 2 - 2 * rad) / 2   // dead zone half-arc per diagonal

            ZStack {
                // Outer circle background
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .frame(width: size * 0.84, height: size * 0.84)

                // Direction cones
                ForEach(Array(directions.enumerated()), id: \.offset) { _, dir in
                    coneSlice(center: center, radius: radius,
                               midAngle: dir.angle, halfArc: rad,
                               color: dir.color.opacity(0.30))
                }

                // Dead zone diagonals
                if halfDead > 0.01 {
                    let diagonals: [Double] = [45, 135, -45, -135].map { $0 * .pi / 180 }
                    ForEach(diagonals, id: \.self) { mid in
                        coneSlice(center: center, radius: radius,
                                   midAngle: mid, halfArc: halfDead,
                                   color: Color.secondary.opacity(0.10))
                    }
                }

                // Crosshair
                Path { p in
                    p.move(to: CGPoint(x: center.x - radius, y: center.y))
                    p.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: center.y - radius))
                    p.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                }
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)

                // Cone boundary arc lines
                ForEach(Array(directions.enumerated()), id: \.offset) { _, dir in
                    Path { p in
                        let a1 = dir.angle - rad
                        let a2 = dir.angle + rad
                        let p1 = CGPoint(x: center.x + radius * cos(a1), y: center.y - radius * sin(a1))
                        let p2 = CGPoint(x: center.x + radius * cos(a2), y: center.y - radius * sin(a2))
                        p.move(to: center); p.addLine(to: p1)
                        p.move(to: center); p.addLine(to: p2)
                    }
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                }

                // Direction labels
                ForEach(Array(directions.enumerated()), id: \.offset) { _, dir in
                    let labelR = radius + 16.0
                    Text(dir.label)
                        .font(.caption2.bold())
                        .foregroundStyle(dir.color)
                        .position(
                            x: center.x + labelR * cos(dir.angle),
                            y: center.y - labelR * sin(dir.angle)
                        )
                }

                // "Dead Zone" text in top-right diagonal if there's room
                if halfDead > 0.06 {
                    let dzAngle = 45.0 * .pi / 180
                    let dzR = radius * 0.62
                    Text("Dead\nZone")
                        .font(.system(size: 8))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .position(
                            x: center.x + dzR * cos(dzAngle),
                            y: center.y - dzR * sin(dzAngle)
                        )
                }

                // Center dot
                Circle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 5, height: 5)
                    .position(center)
            }
            .animation(.easeInOut(duration: 0.2), value: angleDegrees)
        }
    }

    @ViewBuilder
    private func coneSlice(center: CGPoint, radius: Double, midAngle: Double, halfArc: Double, color: Color) -> some View {
        // SwiftUI canvas angles: 0 = right, clockwise positive; math: CCW positive, so negate
        let start = -(midAngle + halfArc)
        let end   = -(midAngle - halfArc)
        Path { path in
            path.move(to: center)
            path.addArc(center: center, radius: radius,
                        startAngle: .radians(start),
                        endAngle:   .radians(end),
                        clockwise: false)
            path.closeSubpath()
        }
        .fill(color)
    }
}

// MARK: - Trackpad Preview

struct TrackpadPreview: View {
    /// All values are fractions in 0.0–0.20 (same as EdgeMargin storage).
    let marginLeft, marginRight, marginTop, marginBottom: Double

    @State private var dotPosition: CGPoint? = nil
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let l = w * marginLeft
            let r = w * marginRight
            let t = h * marginTop
            let b = h * marginBottom

            ZStack {
                // Trackpad body — mimics a real glass trackpad
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color(nsColor: .windowBackgroundColor).opacity(0.7),
                                     Color(nsColor: .controlBackgroundColor)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.35), lineWidth: 1))

                // Left margin zone
                if l > 0 {
                    Rectangle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: l)
                        .frame(maxHeight: .infinity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            Rectangle()
                                .fill(Color.orange.opacity(0.6))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                            , alignment: .trailing
                        )
                }
                // Right margin zone
                if r > 0 {
                    Rectangle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: r)
                        .frame(maxHeight: .infinity)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .overlay(
                            Rectangle()
                                .fill(Color.orange.opacity(0.6))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                            , alignment: .leading
                        )
                }
                // Top margin zone
                if t > 0 {
                    Rectangle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(height: t)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .overlay(
                            Rectangle()
                                .fill(Color.orange.opacity(0.6))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                            , alignment: .bottom
                        )
                }
                // Bottom margin zone
                if b > 0 {
                    Rectangle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(height: b)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .overlay(
                            Rectangle()
                                .fill(Color.orange.opacity(0.6))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                            , alignment: .top
                        )
                }

                // Hover dot
                if let pos = dotPosition {
                    let inMargin = pos.x < l || pos.x > w - r
                                || pos.y < t || pos.y > h - b
                    Circle()
                        .fill(inMargin ? Color.orange : Color.green)
                        .shadow(color: (inMargin ? Color.orange : Color.green).opacity(0.5), radius: 4)
                        .frame(width: 12, height: 12)
                        .offset(x: pos.x - w / 2, y: pos.y - h / 2)
                        .animation(.easeOut(duration: 0.05), value: pos)
                }

                // Margin labels
                Group {
                    if l > 24 { Text(String(format: "%.0f%%", marginLeft * 100))
                        .font(.system(size: 9)).foregroundStyle(.orange.opacity(0.8))
                        .frame(maxHeight: .infinity, alignment: .center)
                        .frame(width: l)
                        .frame(maxWidth: .infinity, alignment: .leading) }
                    if r > 24 { Text(String(format: "%.0f%%", marginRight * 100))
                        .font(.system(size: 9)).foregroundStyle(.orange.opacity(0.8))
                        .frame(maxHeight: .infinity, alignment: .center)
                        .frame(width: r)
                        .frame(maxWidth: .infinity, alignment: .trailing) }
                }

                // Helper label at bottom
                VStack {
                    Spacer()
                    Text("Move cursor here to preview")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): dotPosition = loc
                case .ended:           dotPosition = nil
                }
            }
        }
    }
}
