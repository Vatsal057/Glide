import SwiftUI

struct TuningTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                TuningSection(title: "Recognition", icon: "waveform.path") {
                    SliderRow(
                        label: "Activation Threshold",
                        value: $settings.activationThreshold,
                        range: 4...40,
                        format: "%.0f pt",
                        hint: "How far fingers must travel before registering as a swipe."
                    )
                    SliderRow(
                        label: "Switcher Step Distance",
                        value: $settings.switcherStepDistance,
                        range: 10...100,
                        format: "%.0f pt",
                        hint: "Finger travel needed to step to the next app in the switcher."
                    )
                    SliderRow(
                        label: "Switcher Debounce",
                        value: $settings.switcherDebounce,
                        range: 0.05...0.5,
                        format: "%.2f s",
                        hint: "Delay that prevents skipping multiple apps too quickly."
                    )
                }

                TuningSection(title: "Speed Classification", icon: "speedometer") {
                    SliderRow(
                        label: "Fast Velocity Threshold",
                        value: $settings.fastVelocityThreshold,
                        range: 500...3000,
                        format: "%.0f pt/s",
                        hint: "Speed above which a swipe is classified as Fast."
                    )
                    SliderRow(
                        label: "Slow Velocity Threshold",
                        value: $settings.slowVelocityThreshold,
                        range: 100...1000,
                        format: "%.0f pt/s",
                        hint: "Speed below which a swipe is classified as Slow."
                    )
                    StepperRow(
                        label: "Speed Sample Frames",
                        value: $settings.speedSampleFrames,
                        range: 2...20,
                        hint: "Number of frames averaged to compute swipe speed. Higher = smoother."
                    )
                }

                TuningSection(title: "Direction Detection", icon: "arrow.up.left.and.arrow.down.right") {
                    SliderRow(
                        label: "Angle Tolerance",
                        value: $settings.angleTolerance,
                        range: 20...45,
                        format: "%.0f°",
                        hint: "Half-width of the direction cone. 45° = equal quarters. Lower = stricter."
                    )
                }

                TuningSection(title: "Pinch Veto", icon: "hand.pinch") {
                    StepperRow(
                        label: "Candidate Frames",
                        value: $settings.candidateFrames,
                        range: 1...12,
                        hint: "Frames analyzed at touch start before committing to a swipe."
                    )
                    SliderRow(
                        label: "Pinch Spread Threshold",
                        value: $settings.pinchSpreadThreshold,
                        range: 0.01...0.2,
                        format: "%.3f",
                        hint: "Total finger spread limit. Exceeded → assume pinch, cancel swipe."
                    )
                    SliderRow(
                        label: "Pinch Frame Threshold",
                        value: $settings.pinchFrameThreshold,
                        range: 0.005...0.1,
                        format: "%.3f",
                        hint: "Per-frame spread limit. Fast pinch instantly cancels detection."
                    )
                    SliderRow(
                        label: "Swipe Coherence",
                        value: $settings.swipeCoherence,
                        range: 0.5...1.0,
                        format: "%.2f",
                        hint: "How uniformly fingers must move. 1.0 = all exactly aligned."
                    )
                }

                TuningSection(title: "Edge Margins", icon: "rectangle.inset.filled") {
                    Toggle("Enable Edge Margins", isOn: $settings.edgeMarginsEnabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    if settings.edgeMarginsEnabled {
                        SliderRow(label: "Left Margin",   value: $settings.marginLeft,   range: 0...20, format: "%.0f%%",
                                  hint: "Ignore touches starting in this left-edge zone.")
                        SliderRow(label: "Right Margin",  value: $settings.marginRight,  range: 0...20, format: "%.0f%%",
                                  hint: "Ignore touches starting in this right-edge zone.")
                        SliderRow(label: "Top Margin",    value: $settings.marginTop,    range: 0...20, format: "%.0f%%",
                                  hint: "Ignore touches starting in this top-edge zone.")
                        SliderRow(label: "Bottom Margin", value: $settings.marginBottom, range: 0...20, format: "%.0f%%",
                                  hint: "Ignore touches starting in this bottom-edge zone.")

                        TrackpadPreview(
                            marginLeft: settings.marginLeft,
                            marginRight: settings.marginRight,
                            marginTop: settings.marginTop,
                            marginBottom: settings.marginBottom
                        )
                        .frame(height: 160)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }

                resetSection
            }
            .padding()
        }
    }

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset All to Defaults") {
                withAnimation {
                    settings.activationThreshold = 12
                    settings.switcherStepDistance = 40
                    settings.switcherDebounce = 0.15
                    settings.fastVelocityThreshold = 1200
                    settings.slowVelocityThreshold = 400
                    settings.speedSampleFrames = 6
                    settings.angleTolerance = 45
                    settings.candidateFrames = 4
                    settings.pinchSpreadThreshold = 0.06
                    settings.pinchFrameThreshold = 0.03
                    settings.swipeCoherence = 0.80
                    settings.edgeMarginsEnabled = false
                    settings.marginLeft = 5
                    settings.marginRight = 5
                    settings.marginTop = 5
                    settings.marginBottom = 5
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

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .frame(width: 190, alignment: .leading)
                Slider(value: $value, in: range)
                    .frame(maxWidth: 260)
                Text(String(format: format, value))
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

// MARK: - Trackpad Preview

struct TrackpadPreview: View {
    let marginLeft, marginRight, marginTop, marginBottom: Double
    @State private var dotPosition: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Trackpad body
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))

                // Margin zones
                let l = geo.size.width  * marginLeft   / 100
                let r = geo.size.width  * marginRight  / 100
                let t = geo.size.height * marginTop    / 100
                let b = geo.size.height * marginBottom / 100

                // Left
                Rectangle().fill(Color.orange.opacity(0.15))
                    .frame(width: l).frame(maxHeight: .infinity, alignment: .leading)
                    .offset(x: -(geo.size.width / 2 - l / 2))

                // Right
                Rectangle().fill(Color.orange.opacity(0.15))
                    .frame(width: r).frame(maxHeight: .infinity, alignment: .trailing)
                    .offset(x: (geo.size.width / 2 - r / 2))

                // Top
                Rectangle().fill(Color.orange.opacity(0.15))
                    .frame(height: t).frame(maxWidth: .infinity, alignment: .top)
                    .offset(y: -(geo.size.height / 2 - t / 2))

                // Bottom
                Rectangle().fill(Color.orange.opacity(0.15))
                    .frame(height: b).frame(maxWidth: .infinity, alignment: .bottom)
                    .offset(y: (geo.size.height / 2 - b / 2))

                // Corner radius clip
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Dot
                if let pos = dotPosition {
                    let inMargin = pos.x < l || pos.x > geo.size.width - r
                                || pos.y < t || pos.y > geo.size.height - b
                    Circle()
                        .fill(inMargin ? Color.orange : Color.green)
                        .frame(width: 14, height: 14)
                        .offset(x: pos.x - geo.size.width / 2,
                                y: pos.y - geo.size.height / 2)
                }

                // Label
                VStack {
                    Spacer()
                    Text("Move your cursor here to preview")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): dotPosition = location
                case .ended: dotPosition = nil
                }
            }
        }
    }
}
