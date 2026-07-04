import SwiftUI

// ─────────────────────────────────────────────
// MARK: - TuningTab
//
// Two layers:
//  • Friendly controls — presets and 0–100% sliders in plain language that
//    map onto the raw GestureTuning fields underneath.
//  • Advanced disclosure — the raw values for power users. Same storage,
//    so the two stay in sync automatically.
// ─────────────────────────────────────────────

struct TuningTab: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                presetsCard

                TuningSection(title: "Swipes", icon: "hand.draw") {
                    FriendlySlider(
                        title: "Sensitivity",
                        subtitle: "How far your fingers travel before a swipe counts.",
                        leftLabel: "Deliberate", rightLabel: "Featherlight",
                        value: mapped(\.initialThreshold, range: (0.035, 0.006))
                    )
                    Divider().padding(.horizontal, 12)
                    FriendlySlider(
                        title: "Diagonal strictness",
                        subtitle: "Stricter means a swipe must be clearly up, down, left, or right — sloppy diagonals are ignored.",
                        leftLabel: "Easygoing", rightLabel: "Strict",
                        value: mapped(\.swipeAngleTolerance, range: (45, 25))
                    )
                    AngleToleranceCompass(angleDegrees: Double(store.tuning.swipeAngleTolerance))
                        .frame(height: 180)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                TuningSection(title: "Accident Protection", icon: "hand.raised.slash") {
                    FriendlySlider(
                        title: "Protection level",
                        subtitle: "Stops zooms, pinches, and resting fingers from being mistaken for swipes. Turn it up if gestures fire when you don't mean them to; turn it down if your real swipes get ignored.",
                        leftLabel: "Off-ish", rightLabel: "Paranoid",
                        value: protectionBinding
                    )
                }

                TuningSection(title: "Swipe Speed", icon: "speedometer") {
                    explainer("Only matters for gestures you've set to trigger on a Fast or Slow swipe.")
                    FriendlySlider(
                        title: "Flick detection",
                        subtitle: "How easily a quick flick counts as a “fast” swipe.",
                        leftLabel: "Needs a real flick", rightLabel: "Easily fast",
                        value: mapped(\.fastVelocityThreshold, range: (0.016, 0.005))
                    )
                    Divider().padding(.horizontal, 12)
                    FriendlySlider(
                        title: "Slow swipe detection",
                        subtitle: "How gentle a swipe can be and still count as “slow”.",
                        leftLabel: "Very gentle only", rightLabel: "Easily slow",
                        value: mapped(\.slowVelocityThreshold, range: 0.002...0.007)
                    )
                }

                TuningSection(title: "Repeating Gestures", icon: "repeat") {
                    explainer("For continuous gestures — ones that keep firing while you hold and swipe, like volume or brightness.")
                    FriendlySlider(
                        title: "Repeat rate",
                        subtitle: "How rapidly the action repeats as you keep swiping.",
                        leftLabel: "Relaxed", rightLabel: "Rapid-fire",
                        value: repeatRateBinding
                    )
                }

                TuningSection(title: "Trackpad Edges", icon: "rectangle.inset.filled") {
                    Toggle("Ignore touches that start near the edges", isOn: tuningBinding(\.edgeMarginEnabled))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if store.tuning.edgeMarginEnabled {
                        explainer("Helps when your palm or thumb brushes the trackpad rim. Fingers already inside keep working normally.")
                        FriendlySlider(
                            title: "Dead zone size",
                            subtitle: "Set each edge separately under Advanced.",
                            leftLabel: "Sliver", rightLabel: "Wide",
                            value: edgeSizeBinding
                        )
                        TrackpadPreview(
                            marginLeft:   Double(store.tuning.edgeMargin.left),
                            marginRight:  Double(store.tuning.edgeMargin.right),
                            marginTop:    Double(store.tuning.edgeMargin.top),
                            marginBottom: Double(store.tuning.edgeMargin.bottom)
                        )
                        .frame(height: 170)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }

                advancedSection

                HStack {
                    Spacer()
                    Button("Reset All to Defaults") {
                        withAnimation { store.resetTuning() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    // MARK: - Presets

    private struct Preset {
        let name: String
        let icon: String
        let blurb: String
        let apply: (inout GestureTuning) -> Void
        let matches: (GestureTuning) -> Bool
    }

    private var presets: [Preset] {
        [
            Preset(name: "Relaxed", icon: "leaf",
                   blurb: "Easy to trigger, forgiving of sloppy swipes.",
                   apply: { t in
                       t.initialThreshold = 0.010
                       t.swipeCoherenceThreshold = 0.20
                       t.pinchSpreadThreshold = 0.030
                       t.pinchFrameSpreadThreshold = 0.014
                       t.candidateFrames = 2
                       t.swipeAngleTolerance = 45
                   },
                   matches: { t in abs(t.initialThreshold - 0.010) < 0.0015 && t.candidateFrames == 2 }),
            Preset(name: "Balanced", icon: "circle.lefthalf.filled",
                   blurb: "The default. Works for most hands.",
                   apply: { t in
                       t.initialThreshold = 0.014
                       t.swipeCoherenceThreshold = 0.30
                       t.pinchSpreadThreshold = 0.015
                       t.pinchFrameSpreadThreshold = 0.008
                       t.candidateFrames = 3
                       t.swipeAngleTolerance = 45
                   },
                   matches: { t in abs(t.initialThreshold - 0.014) < 0.0015 && t.candidateFrames == 3 && abs(t.pinchSpreadThreshold - 0.015) < 0.004 }),
            Preset(name: "Precise", icon: "scope",
                   blurb: "Only deliberate, clean gestures fire.",
                   apply: { t in
                       t.initialThreshold = 0.020
                       t.swipeCoherenceThreshold = 0.45
                       t.pinchSpreadThreshold = 0.010
                       t.pinchFrameSpreadThreshold = 0.006
                       t.candidateFrames = 4
                       t.swipeAngleTolerance = 35
                   },
                   matches: { t in abs(t.initialThreshold - 0.020) < 0.0015 && t.candidateFrames == 4 }),
        ]
    }

    private var presetsCard: some View {
        TuningSection(title: "Quick Setup", icon: "wand.and.stars") {
            HStack(spacing: 10) {
                ForEach(presets, id: \.name) { preset in
                    let active = preset.matches(store.tuning)
                    Button {
                        withAnimation { store.updateTuning(preset.apply) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset.icon)
                                .font(.title3)
                            Text(preset.name)
                                .font(.headline)
                            Text(preset.blurb)
                                .font(.caption)
                                .foregroundStyle(active ? Color.white.opacity(0.85) : Color.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary.opacity(0.5)))
                        )
                        .foregroundStyle(active ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            Text("Pick a starting point — every slider below fine-tunes from there.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Bindings & mappings

    private func tuningBinding<T>(_ keyPath: WritableKeyPath<GestureTuning, T>) -> Binding<T> {
        Binding(
            get: { store.tuning[keyPath: keyPath] },
            set: { newValue in store.updateTuning { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// Maps a raw field onto a 0–1 slider. `range` runs from the value at the
    /// slider's LEFT end to the value at its RIGHT end (may be descending).
    private func mapped(_ keyPath: WritableKeyPath<GestureTuning, Float>, range: ClosedRange<Float>) -> Binding<Double> {
        mappedValue(get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 }, left: range.lowerBound, right: range.upperBound)
    }

    private func mapped(_ keyPath: WritableKeyPath<GestureTuning, Float>, range: (Float, Float)) -> Binding<Double> {
        mappedValue(get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 }, left: range.0, right: range.1)
    }

    private func mappedValue(get: @escaping (GestureTuning) -> Float,
                             set: @escaping (inout GestureTuning, Float) -> Void,
                             left: Float, right: Float) -> Binding<Double> {
        Binding<Double>(
            get: {
                let v = get(store.tuning)
                let t = (v - left) / (right - left)
                return Double(min(max(t, 0), 1))
            },
            set: { t in
                let v = left + (right - left) * Float(t)
                store.updateTuning { set(&$0, v) }
            }
        )
    }

    /// One "protection" knob drives the whole veto family proportionally.
    /// Advanced users can still pull the individual fields apart below.
    private var protectionBinding: Binding<Double> {
        Binding<Double>(
            get: {
                // Canonical field: pinch spread threshold, 0.06 (loose) → 0.008 (strict)
                let t = (0.06 - Double(store.tuning.pinchSpreadThreshold)) / (0.06 - 0.008)
                return min(max(t, 0), 1)
            },
            set: { t in
                store.updateTuning { tuning in
                    tuning.pinchSpreadThreshold      = Float(0.06 - (0.06 - 0.008) * t)
                    tuning.pinchFrameSpreadThreshold = max(0.003, tuning.pinchSpreadThreshold * 0.55)
                    tuning.swipeCoherenceThreshold   = Float(0.12 + (0.50 - 0.12) * t)
                    tuning.candidateFrames           = Int((2.0 + 3.0 * t).rounded())
                }
            }
        )
    }

    /// Repeat rate drives both the distance and the pause between repeats.
    private var repeatRateBinding: Binding<Double> {
        Binding<Double>(
            get: {
                let t = (0.06 - Double(store.tuning.continuousStepThreshold)) / (0.06 - 0.012)
                return min(max(t, 0), 1)
            },
            set: { t in
                store.updateTuning { tuning in
                    tuning.continuousStepThreshold = Float(0.06 - (0.06 - 0.012) * t)
                    tuning.continuousDebounce      = 0.20 - (0.20 - 0.03) * t
                }
            }
        )
    }

    /// One size slider sets all four margins; per-edge control lives in Advanced.
    private var edgeSizeBinding: Binding<Double> {
        Binding<Double>(
            get: {
                let m = store.tuning.edgeMargin
                let maxMargin = max(max(m.left, m.right), max(m.top, m.bottom))
                return min(max(Double(maxMargin) / 0.20, 0), 1)
            },
            set: { t in
                let v = Float(0.20 * t)
                store.updateTuning { tuning in
                    tuning.edgeMargin.left = v; tuning.edgeMargin.right = v
                    tuning.edgeMargin.top = v;  tuning.edgeMargin.bottom = v
                }
            }
        )
    }

    @ViewBuilder
    private func explainer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    SliderRow(label: "Initial Threshold", value: tuningBinding(\.initialThreshold),
                              range: 0.005...0.05, format: "%.3f",
                              hint: "How far fingers must travel before registering as a swipe.")
                    SliderRow(label: "Fast Velocity Threshold", value: tuningBinding(\.fastVelocityThreshold),
                              range: 0.004...0.02, format: "%.3f",
                              hint: "Base threshold for flick intent.")
                    SliderRow(label: "Slow Velocity Threshold", value: tuningBinding(\.slowVelocityThreshold),
                              range: 0.001...0.008, format: "%.3f",
                              hint: "Base threshold for controlled slow intent.")
                    StepperRow(label: "Speed Sample Frames", value: tuningBinding(\.speedSampleCount),
                               range: 2...20, hint: "Movement frames used for smoothed velocity.")
                    SliderRow(label: "Angle Tolerance", value: tuningBinding(\.swipeAngleTolerance),
                              range: 20...45, format: "%.0f°",
                              hint: "Half-width of the direction cone. Lower = stricter.")
                    StepperRow(label: "Candidate Frames", value: tuningBinding(\.candidateFrames),
                               range: 1...12, hint: "Frames analyzed before committing to a swipe.")
                    SliderRow(label: "Pinch Spread Threshold", value: tuningBinding(\.pinchSpreadThreshold),
                              range: 0.005...0.2, format: "%.3f",
                              hint: "Total finger-spread change that cancels a swipe as a pinch.")
                    SliderRow(label: "Pinch Frame Spread", value: tuningBinding(\.pinchFrameSpreadThreshold),
                              range: 0.003...0.1, format: "%.3f",
                              hint: "Per-frame spread change that cancels instantly.")
                    SliderRow(label: "Swipe Coherence", value: tuningBinding(\.swipeCoherenceThreshold),
                              range: 0.1...1.0, format: "%.2f",
                              hint: "How uniformly fingers must move. 1.0 = perfectly aligned.")
                    SliderRow(label: "Continuous Step", value: tuningBinding(\.continuousStepThreshold),
                              range: 0.005...0.08, format: "%.3f",
                              hint: "Distance per repeat of a continuous action.")
                    SliderRow(label: "Continuous Debounce", value: tuningBinding(\.continuousDebounce),
                              range: 0.0...0.25, format: "%.2fs",
                              hint: "Minimum time between repeats.")
                    if store.tuning.edgeMarginEnabled {
                        marginSlider(label: "Left Edge",   keyPath: \.edgeMargin.left)
                        marginSlider(label: "Right Edge",  keyPath: \.edgeMargin.right)
                        marginSlider(label: "Top Edge",    keyPath: \.edgeMargin.top)
                        marginSlider(label: "Bottom Edge", keyPath: \.edgeMargin.bottom)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } label: {
            Label("Advanced — raw values", systemImage: "gearshape.2")
                .font(.headline)
        }
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
            hint: "Ignore touches starting in this edge zone."
        )
    }
}

// MARK: - Friendly Slider

/// Plain-language 0–1 slider: a title, one sentence of context, and words
/// instead of numbers at the ends.
struct FriendlySlider: View {
    let title: String
    let subtitle: String
    let leftLabel: String
    let rightLabel: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(leftLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 90, alignment: .trailing)
                Slider(value: $value, in: 0...1)
                Text(rightLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 90, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

// MARK: - Slider Row (advanced)

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

// MARK: - Stepper Row (advanced)

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
