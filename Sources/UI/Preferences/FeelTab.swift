import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FeelTab
//
// Preferences tab for Surface Feel — FeelMyMac-style trackpad textures.
// Master toggle, global material picker with haptic preview, intensity and
// pressure-scaling controls, per-gesture material overrides, and collapsed
// per-material tuning. Follows the EdgeControlsTab card pattern.
// ─────────────────────────────────────────────────────────────────────────────

struct FeelTab: View {
    @EnvironmentObject var store: PreferencesStore

    private var settings: SurfaceFeelSettings { store.surfaceFeel }
    private var masterHapticsOn: Bool { store.hapticFeedbackEnabled }
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Gesture rules worth an override row: configured (non-draft) rules.
    private var overridableRules: [GestureRule] {
        store.rules.filter { !$0.isDraft }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introCard

                if settings.enabled {
                    materialCard
                    feelCard
                    overridesCard
                    advancedCard

                    HStack {
                        Spacer()
                        Button("Reset Surface Feel to Defaults") {
                            withAnimation { store.resetSurfaceFeel() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                       value: settings.enabled)
        }
    }

    // MARK: - Intro Card

    private var introCard: some View {
        TuningSection(title: "Surface Feel", icon: "waveform") {
            Toggle("Enable trackpad surface textures", isOn: Binding(
                get: { settings.enabled },
                set: { val in store.updateSurfaceFeel { $0.enabled = val } }
            ))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            explainer("Plays a continuous haptic texture under your finger as it moves across the trackpad — like running it over felt, wood, or sand.\n\nIt never stacks on Glide's gesture haptics: contacts owned by TrackPoint or Edge Controls keep their own feel, and everything else — including two-finger scrolling — gets the surface material.")
        }
    }

    // MARK: - Material Card

    private var materialCard: some View {
        TuningSection(title: "Surface Material", icon: "square.grid.3x3") {
            VStack(spacing: 0) {
                ForEach(Material.presets, id: \.name) { preset in
                    materialRow(name: preset.name, base: preset.material)
                    if preset.name != Material.presets.last?.name {
                        Divider().padding(.leading, 96)
                    }
                }
            }
            .padding(.vertical, 4)

            if !masterHapticsOn {
                explainer("Haptic feedback is turned off in General, so previews are silent.")
            }
        }
    }

    private func materialRow(name: String, base: Material) -> some View {
        let material = tunedMaterial(name: name, base: base)
        let isSelected = settings.material.lowercased() == name
        let isTuned = settings.materialOverrides[name] != nil

        return HStack(spacing: 12) {
            TextureStrip(material: material)
                .frame(width: 76, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName(for: name))
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if isTuned {
                        Text("tuned")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                Text(blurb(for: name))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.1f", material.toothMM)) mm grain · up to \(Int(material.maxTickRate)) ticks/s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? .accent : .secondary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        // Tap = select + preview the newly selected global material.
        // (A separate preview button here would also trip this gesture,
        // so per-material preview-without-select lives in Advanced below.)
        .onTapGesture {
            store.updateSurfaceFeel { $0.material = name }
            playPreview(material: store.surfaceFeel.resolvedGlobalMaterial())
        }
    }

    // MARK: - Feel Card

    private var feelCard: some View {
        TuningSection(title: "Feel", icon: "hand.tap") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Intensity")
                            .font(.body)
                        Spacer()
                        Text("\(Int(settings.intensity * 100))%")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { settings.intensity },
                            set: { val in store.updateSurfaceFeel { $0.intensity = val } }
                        ),
                        in: 0...1,
                        step: 0.01
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                explainer("Caps how strong texture pulses may get. Lower is a whisper under the finger; higher lets the material's full strength cycle through.")

                Divider().padding(.horizontal, 12)

                Toggle("Press harder for a stronger texture", isOn: Binding(
                    get: { settings.pressSizeScaling },
                    set: { val in store.updateSurfaceFeel { $0.pressSizeScaling = val } }
                ))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                explainer(settings.pressSizeScaling
                          ? "Your touch size is calibrated per finger: a firm press drifts toward the stronger end of the material, a light touch toward the weaker end."
                          : "Texture strength ignores how hard you press — every tick plays the material's strength cycle as written.")
                    .padding(.bottom, 2)
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Per-Gesture Overrides Card

    private var overridesCard: some View {
        TuningSection(title: "Per-Gesture Materials", icon: "hand.draw") {
            VStack(spacing: 0) {
                if overridableRules.isEmpty {
                    explainer("No gestures configured yet — add some in the Gestures tab, then give each its own texture here.")
                } else {
                    ForEach(overridableRules) { rule in
                        gestureRow(for: rule)
                        if rule.id != overridableRules.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            explainer("Give individual gestures their own texture. \"Use global\" follows the surface material above; \"Off\" silences texture while that gesture owns the contact.")
        }
    }

    private func gestureRow(for rule: GestureRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.action.iconName)
                .foregroundStyle(.accent)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(rule.direction.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: gestureBinding(for: rule.id.uuidString)) {
                Text("Use global").tag("global")
                Text("Off").tag("off")
                ForEach(Material.presets, id: \.name) { preset in
                    Text(displayName(for: preset.name)).tag(preset.name)
                }
            }
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func gestureBinding(for ruleID: String) -> Binding<String> {
        Binding(
            get: { settings.gestureMaterials[ruleID] ?? "global" },
            set: { val in
                store.updateSurfaceFeel {
                    if val == "global" {
                        $0.gestureMaterials.removeValue(forKey: ruleID)
                    } else {
                        $0.gestureMaterials[ruleID] = val
                    }
                }
            }
        )
    }

    // MARK: - Advanced Card

    private var advancedCard: some View {
        TuningSection(title: "Advanced", icon: "slider.horizontal.3") {
            DisclosureGroup("Tune individual materials") {
                VStack(spacing: 0) {
                    ForEach(Material.presets, id: \.name) { preset in
                        materialTuningBlock(name: preset.name, base: preset.material)
                        if preset.name != Material.presets.last?.name {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            explainer("Grain is millimetres of finger travel per tick; tick rate caps pulses per second; irregularity randomises the spacing. Changes are saved as overrides — the built-in presets stay untouched.")
        }
    }

    private func materialTuningBlock(name: String, base: Material) -> some View {
        let isTuned = settings.materialOverrides[name] != nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayName(for: name))
                    .font(.body)
                    .fontWeight(.medium)
                if isTuned {
                    Text("customized")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Spacer()
                if isTuned {
                    Button("Reset") {
                        store.updateSurfaceFeel { $0.materialOverrides.removeValue(forKey: name) }
                    }
                    .buttonStyle(.link)
                }
                Button("Preview") {
                    playPreview(material: tunedMaterial(name: name, base: base))
                }
                .buttonStyle(.link)
                .disabled(!masterHapticsOn)
            }

            tuningSlider(label: "Grain",
                         value: doubleField(name: name, \.toothMM),
                         range: 0.5...10,
                         format: "%.1f mm")
            tuningSlider(label: "Tick rate",
                         value: doubleField(name: name, \.maxTickRate),
                         range: 4...60,
                         format: "%.0f /s")
            tuningSlider(label: "Irregularity",
                         value: doubleField(name: name, \.jitter),
                         range: 0...1,
                         format: "%.2f")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func tuningSlider(label: String, value: Binding<Double>,
                              range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.body)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    /// Per-material field binding. Reading falls back to the built-in preset;
    /// writing creates a user override entry (clamped by normalization).
    private func doubleField(name: String, _ keyPath: WritableKeyPath<Material, Double>) -> Binding<Double> {
        Binding(
            get: {
                let m = settings.materialOverrides[name]
                    ?? Material.preset(named: name) ?? .felt
                return m[keyPath: keyPath]
            },
            set: { val in
                store.updateSurfaceFeel {
                    var m = $0.materialOverrides[name]
                        ?? Material.preset(named: name) ?? .felt
                    m[keyPath: keyPath] = val
                    $0.materialOverrides[name] = m
                }
            }
        )
    }

    // MARK: - Helpers

    private func tunedMaterial(name: String, base: Material) -> Material {
        settings.materialOverrides[name] ?? base
    }

    private func displayName(for name: String) -> String {
        name == "boucle" ? "Bouclé" : name.capitalized
    }

    private func blurb(for name: String) -> String {
        switch name {
        case "glass":  return "Sparse whisper — a polished surface"
        case "felt":   return "Dense and soft — the default"
        case "paper":  return "Dry rasp"
        case "wood":   return "Regular grain, a knot every 8th tick"
        case "sand":   return "Coarse and irregular"
        case "boucle": return "Lumpy — tick clusters with gaps"
        default:         return ""
        }
    }

    /// Plays the material's strength cycle as a short haptic burst.
    /// Silent unless the master haptic toggle is on.
    private func playPreview(material: Material) {
        guard masterHapticsOn else { return }
        let strengths = material.effectiveStrengths
        for i in 0..<12 {
            let s = strengths[i % strengths.count]
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Double(i) * 0.07) {
                HapticEngine.shared.pulse(s)
            }
        }
    }

    private func explainer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TextureStrip
//
// Static miniature of a material's strength cycle: one bar per tick, height
// by pulse strength. Deliberately unanimated (Reduce Motion friendly).
// ─────────────────────────────────────────────────────────────────────────────

private struct TextureStrip: View {
    let material: Material

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                let s = material.effectiveStrengths[i % material.effectiveStrengths.count]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 4, height: barHeight(for: s))
            }
        }
        .frame(height: 30)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func barHeight(for s: HapticStrength) -> CGFloat {
        switch s {
        case .weak:   return 8
        case .medium: return 16
        case .strong: return 26
        }
    }
}
