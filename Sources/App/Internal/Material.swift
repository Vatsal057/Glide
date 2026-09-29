import Foundation

// ─────────────────────────────────────────────
// MARK: - Material
// ─────────────────────────────────────────────

/// A haptic "surface material": converts millimetres of finger travel into
/// actuator pulses. The grain (`toothMM`), the feel (`strengths`), the
/// ceiling (`maxTickRate`), and the irregularity (`jitter`, `burst`).
struct Material: Codable, Equatable {
    /// mm of finger travel per tick — the texture's grain.
    var toothMM: Double
    /// Pulse strengths, cycled one per tick (e.g. [.weak, .weak, .medium]).
    /// Empty is treated as [.weak].
    var strengths: [HapticStrength]
    /// Ticks-per-second ceiling (anti-buzz).
    var maxTickRate: Double
    /// 0...1 randomisation of tooth spacing (sand/bouclé feel irregular).
    var jitter: Double
    /// Ticks per cluster; <= 1 disables (even spacing).
    var burst: Int
    /// Silent teeth skipped after each burst cluster (bouclé lumpiness).
    var burstGapTeeth: Int

    /// The strength cycle actually played; never empty.
    var effectiveStrengths: [HapticStrength] {
        strengths.isEmpty ? [.weak] : strengths
    }

    init(toothMM: Double, strengths: [HapticStrength], maxTickRate: Double,
         jitter: Double = 0, burst: Int = 0, burstGapTeeth: Int = 0) {
        self.toothMM = toothMM
        self.strengths = strengths
        self.maxTickRate = maxTickRate
        self.jitter = jitter
        self.burst = burst
        self.burstGapTeeth = burstGapTeeth
    }

    /// Clamps every field to a sane range (protects hand-edited YAML).
    func clamped() -> Material {
        Material(
            toothMM: min(max(toothMM, 0.5), 20),
            strengths: strengths.isEmpty ? [.weak] : strengths,
            maxTickRate: min(max(maxTickRate, 1), 120),
            jitter: min(max(jitter, 0), 1),
            burst: min(max(burst, 0), 32),
            burstGapTeeth: min(max(burstGapTeeth, 0), 32)
        )
    }
}

// ─────────────────────────────────────────────
// MARK: - Presets
// ─────────────────────────────────────────────

extension Material {
    /// Sparse whisper — a polished surface.
    static let glass = Material(toothMM: 6.0, strengths: [.weak],
                                maxTickRate: 12)
    /// Dense and soft — the default.
    static let felt = Material(toothMM: 2.5, strengths: [.weak, .weak, .medium],
                               maxTickRate: 24, jitter: 0.1)
    /// Dry rasp.
    static let paper = Material(toothMM: 3.5, strengths: [.weak, .medium],
                                maxTickRate: 20, jitter: 0.15)
    /// Regular grain with a knot every ~8th tick.
    static let wood = Material(
        toothMM: 5.0,
        strengths: [.medium, .medium, .medium, .medium, .medium, .medium, .medium, .strong],
        maxTickRate: 16, jitter: 0.05)
    /// Coarse and irregular.
    static let sand = Material(toothMM: 4.0, strengths: [.weak, .medium, .strong],
                               maxTickRate: 14, jitter: 0.4)
    /// Lumpy — clusters of ticks with gaps between.
    static let boucle = Material(toothMM: 3.0, strengths: [.weak],
                                 maxTickRate: 18, jitter: 0.2,
                                 burst: 4, burstGapTeeth: 2)

    /// (config key, material), in UI order.
    static let presets: [(name: String, material: Material)] = [
        ("glass",  .glass),
        ("felt",   .felt),
        ("paper",  .paper),
        ("wood",   .wood),
        ("sand",   .sand),
        ("boucle", .boucle),
    ]

    /// Case-insensitive lookup; nil for unknown names.
    static func preset(named name: String) -> Material? {
        let key = name.lowercased()
        return presets.first { $0.name == key }?.material
    }
}

// ─────────────────────────────────────────────
// MARK: - SurfaceFeelSettings
// ─────────────────────────────────────────────

/// The `surface_feel:` config section. Pure value type; `Settings` owns the
/// canonical copy and `TouchTracker` holds an MT-thread-safe snapshot.
struct SurfaceFeelSettings: Equatable {
    /// Master switch for the continuous texture layer. P0 default is off —
    /// opt in via config until feel + CPU are validated.
    var enabled: Bool = false
    /// Global surface material: a preset name ("felt", "glass", …).
    var material: String = "felt"
    /// 0...1 — caps how strong texture pulses may get.
    var intensity: Double = 0.8
    /// Whether contact size (press) biases pulse strength (decided: yes).
    var pressSizeScaling: Bool = true
    /// Per-gesture overrides: gesture key → preset name, "global", or "off".
    /// Absent key → global material. Parsed and round-tripped in P0; the
    /// engine consults it per claimed contact in P1.
    var gestureMaterials: [String: String] = [:]
    /// Preset name → user-tuned material. Applied over the built-in preset.
    var materialOverrides: [String: Material] = [:]

    /// The material that plays for unclaimed contacts.
    func resolvedGlobalMaterial() -> Material {
        let key = material.lowercased()
        let base = Material.preset(named: key) ?? .felt
        return materialOverrides[key] ?? base
    }

    static func normalized(_ s: SurfaceFeelSettings) -> SurfaceFeelSettings {
        var n = s
        n.intensity = min(max(n.intensity, 0), 1)
        if Material.preset(named: n.material) == nil { n.material = "felt" }
        n.gestureMaterials = n.gestureMaterials.filter { !$0.key.isEmpty }
        n.materialOverrides = Dictionary(
            uniqueKeysWithValues:
                n.materialOverrides.compactMap { key, material in
                    let k = key.lowercased()
                    guard Material.preset(named: k) != nil else { return nil }
                    return (k, material.clamped())
                }
        )
        return n
    }
}
