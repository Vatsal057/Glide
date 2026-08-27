import SwiftUI

// ─────────────────────────────────────────────
// MARK: - TrackPointTab
//
// Same two-layer shape as TuningTab: plain-language sliders over the raw
// TrackPointSettings fields, with the exact numbers under Advanced.
// ─────────────────────────────────────────────

struct TrackPointTab: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var showAdvanced = false

    private var settings: TrackPointSettings { store.trackPoint }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                introCard

                if settings.enabled {
                    anchorSection
                    feelSection
                    scrollSection
                    engageSection
                    advancedSection

                    HStack {
                        Spacer()
                        Button("Reset TrackPoint to Defaults") {
                            withAnimation { store.resetTrackPoint() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: settings.enabled)
        }
    }

    // MARK: - Intro

    private var introCard: some View {
        TuningSection(title: "TrackPoint", icon: "dot.circle.and.hand.point.up.left.fill") {
            Toggle("Use a corner of the trackpad as a pointing stick", isOn: binding(\.enabled))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            explainer("Rest one finger in the corner, hold for a moment, then push. How far you push sets how fast the cursor moves — so you can cross the whole screen from a patch of trackpad the size of your fingertip, without ever lifting your finger.\n\nPress the trackpad to click as usual.")
        }
    }

    // MARK: - Anchor

    private var anchorSection: some View {
        TuningSection(title: "Anchor", icon: "square.dashed.inset.filled") {
            explainer("Pick the corner. Leave a little room between your finger and the rim so you can push in every direction.")

            TrackPointZonePicker(
                selection: settings.zone,
                reach: Double(settings.zoneSize),
                onSelect: { zone in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        store.updateTrackPoint { $0.zone = zone }
                    }
                }
            )
            .frame(height: 190)
            .padding(.horizontal, 12)
            .padding(.top, 4)

            FriendlySlider(
                title: "Zone size",
                subtitle: "How much of the corner counts. Bigger is easier to find; smaller leaves more of the trackpad for normal use.",
                leftLabel: "Snug", rightLabel: "Generous",
                value: mapped(\.zoneSize, from: TrackPointSettings.zoneSizeRange)
            )
        }
    }

    // MARK: - Feel

    private var feelSection: some View {
        TuningSection(title: "Feel", icon: "speedometer") {
            FriendlySlider(
                title: "Top speed",
                subtitle: "How fast the cursor travels at full push.",
                leftLabel: "Strolling", rightLabel: "Flying",
                value: mapped(\.maxSpeed, from: TrackPointSettings.maxSpeedRange)
            )
            Divider().padding(.horizontal, 12)
            FriendlySlider(
                title: "Push distance",
                subtitle: "How far your finger travels to reach top speed.",
                leftLabel: "Long push", rightLabel: "Slight nudge",
                value: mapped(\.pushRange, left: 0.12, right: 0.025)
            )
            Divider().padding(.horizontal, 12)
            FriendlySlider(
                title: "Fine control",
                subtitle: "Higher keeps small pushes slow, so you can land on a pixel and still reach top speed when you lean into it.",
                leftLabel: "Even", rightLabel: "Delicate",
                value: mapped(\.acceleration, from: TrackPointSettings.accelerationRange)
            )
            Divider().padding(.horizontal, 12)
            FriendlySlider(
                title: "Steadiness",
                subtitle: "Push this small is ignored, so a resting finger doesn't drift.",
                leftLabel: "Twitchy", rightLabel: "Planted",
                value: mapped(\.deadZone, from: TrackPointSettings.deadZoneRange)
            )
        }
    }

    // MARK: - Scrolling

    private var scrollSection: some View {
        TuningSection(title: "Scrolling", icon: "arrow.up.and.down") {
            Toggle("Rest a second finger on the pad to scroll", isOn: binding(\.scrollEnabled))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if settings.scrollEnabled {
                explainer("With the stick engaged, put a second finger down anywhere on the trackpad — the same push now scrolls instead of moving the pointer. Lift it and you're back to pointing. You'll feel a tick each time it switches.\n\nEngage the stick first, then add the second finger. The pointer stays where it is, so you scroll whatever it's resting on.")

                FriendlySlider(
                    title: "Scroll speed",
                    subtitle: "How fast the page moves at full push.",
                    leftLabel: "Measured", rightLabel: "Racing",
                    value: mapped(\.scrollSpeed, from: TrackPointSettings.scrollSpeedRange)
                )

                Divider().padding(.horizontal, 12)

                Toggle("Reverse scroll direction", isOn: binding(\.invertScroll))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                explainer(settings.invertScroll
                          ? "Pushing up moves down the page, matching how dragging content feels."
                          : "Pushing up moves up the page, the way a scrollbar or arrow key does.")
            }
        }
    }

    // MARK: - Engaging

    private var engageSection: some View {
        TuningSection(title: "Engaging", icon: "timer") {
            explainer("A short hold is what separates the stick from an ordinary drag. Move before the hold is up and Glide steps aside, letting macOS handle the touch normally.")

            SliderRow(
                label: "Hold to engage",
                value: binding(\.activationDelay),
                range: TrackPointSettings.activationDelayRange,
                format: "%.2f s",
                hint: "Zero engages the instant a finger lands in the corner — fastest, but it will hijack drags that start there."
            )

            Divider().padding(.horizontal, 12)

            Toggle("Tap the Taptic Engine when the stick engages and releases", isOn: binding(\.hapticFeedback))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 0) {
                percentRow(\.zoneSize, label: "Zone Size",
                           range: TrackPointSettings.zoneSizeRange,
                           hint: "Zone depth along each axis, as a share of the trackpad.")
                percentRow(\.pushRange, label: "Push Range",
                           range: TrackPointSettings.pushRangeRange,
                           hint: "Finger travel that maps to top speed.")
                percentRow(\.deadZone, label: "Dead Zone",
                           range: TrackPointSettings.deadZoneRange,
                           hint: "Push ignored around the anchor. Capped at 60% of the push range.")
                percentRow(\.activationMovement, label: "Activation Movement",
                           range: 0.004...0.05,
                           hint: "Push that cancels engagement during the hold.")
                SliderRow(label: "Max Speed", value: binding(\.maxSpeed),
                          range: TrackPointSettings.maxSpeedRange,
                          format: "%.0f pt/s",
                          hint: "Cursor speed at full push.")
                SliderRow(label: "Scroll Speed", value: binding(\.scrollSpeed),
                          range: TrackPointSettings.scrollSpeedRange,
                          format: "%.0f pt/s",
                          hint: "Scroll speed at full push, with a second finger down.")
                SliderRow(label: "Acceleration Curve", value: binding(\.acceleration),
                          range: TrackPointSettings.accelerationRange,
                          format: "%.2f",
                          hint: "Exponent applied to the push. 1.00 is linear.")
            }
        } label: {
            Label("Advanced", systemImage: "slider.horizontal.below.rectangle")
                .font(.headline)
        }
    }

    // MARK: - Bindings

    private func binding<T>(_ keyPath: WritableKeyPath<TrackPointSettings, T>) -> Binding<T> {
        Binding(
            get: { store.trackPoint[keyPath: keyPath] },
            set: { newValue in store.updateTrackPoint { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// Raw fraction stored 0–1, displayed 0–100 %.
    @ViewBuilder
    private func percentRow(_ keyPath: WritableKeyPath<TrackPointSettings, Float>,
                            label: String,
                            range: ClosedRange<Float>,
                            hint: String) -> some View {
        let percent = Binding<Double>(
            get: { Double(store.trackPoint[keyPath: keyPath]) * 100 },
            set: { newValue in store.updateTrackPoint { $0[keyPath: keyPath] = Float(newValue / 100) } }
        )
        SliderRow(label: label, value: percent,
                  range: Double(range.lowerBound * 100)...Double(range.upperBound * 100),
                  format: "%.1f%%", hint: hint)
    }

    /// Maps a raw field onto a 0–1 slider, `left`/`right` being the values at the
    /// slider's ends (which may descend, so "more" always reads left to right).
    private func mapped(_ keyPath: WritableKeyPath<TrackPointSettings, Float>,
                        left: Float, right: Float) -> Binding<Double> {
        Binding<Double>(
            get: {
                let fraction = (store.trackPoint[keyPath: keyPath] - left) / (right - left)
                return Double(min(max(fraction, 0), 1))
            },
            set: { fraction in
                let value = left + (right - left) * Float(fraction)
                store.updateTrackPoint { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func mapped(_ keyPath: WritableKeyPath<TrackPointSettings, Float>,
                        from range: ClosedRange<Float>) -> Binding<Double> {
        mapped(keyPath, left: range.lowerBound, right: range.upperBound)
    }

    private func explainer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
}

// ─────────────────────────────────────────────
// MARK: - TrackPointZonePicker
// ─────────────────────────────────────────────

/// Corner picker drawn as the trackpad itself, with the live zone size. Clicking
/// a corner selects it, so the control and the preview are the same object.
struct TrackPointZonePicker: View {
    let selection: TrackpadZone
    let reach: Double
    let onSelect: (TrackpadZone) -> Void

    var body: some View {
        GeometryReader { geo in
            let pad = padRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary.opacity(0.4))
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.tertiary, lineWidth: 1)

                ForEach(TrackpadZone.cornerCases, id: \.self) { zone in
                    corner(zone, in: pad.size)
                }
            }
            .frame(width: pad.width, height: pad.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TrackPoint corner")
    }

    @ViewBuilder
    private func corner(_ zone: TrackpadZone, in bounds: CGSize) -> some View {
        let size = CGSize(width: bounds.width * reach, height: bounds.height * reach)
        let active = zone == selection

        Button {
            onSelect(zone)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary.opacity(0.7)))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(active ? Color.clear : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: active ? [] : [3, 3]))
                if active {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: min(size.width, size.height) * 0.42))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(zone.rawValue)
        .accessibilityLabel(zone.rawValue)
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .position(center(for: zone, in: bounds, zoneSize: size))
    }

    private func center(for zone: TrackpadZone, in bounds: CGSize, zoneSize: CGSize) -> CGPoint {
        let onLeft = zone == .topLeft || zone == .bottomLeft
        let onTop  = zone == .topLeft || zone == .topRight
        return CGPoint(x: onLeft ? zoneSize.width / 2 : bounds.width - zoneSize.width / 2,
                       y: onTop  ? zoneSize.height / 2 : bounds.height - zoneSize.height / 2)
    }

    /// Apple trackpads are roughly 1.6:1, and the picker only reads correctly if
    /// the drawing has the same proportions as the hardware.
    private func padRect(in available: CGSize) -> CGRect {
        let aspect: CGFloat = 1.6
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}
