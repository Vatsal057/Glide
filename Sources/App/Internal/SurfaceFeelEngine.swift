import Foundation

// ─────────────────────────────────────────────
// MARK: - SurfaceFeelSnapshot
// ─────────────────────────────────────────────

/// MT-thread-safe copy of the surface-feel settings. Resolved once on the
/// main thread when settings change; `TouchTracker` holds the copy the
/// multitouch thread reads (same pattern as the TrackPoint/Edge caches).
struct SurfaceFeelSnapshot: Equatable {
    var enabled: Bool = false
    var material: Material = .felt
    var intensity: Double = 0.8
    var pressSizeScaling: Bool = true
}

// ─────────────────────────────────────────────
// MARK: - SurfaceFeelEngine
// ─────────────────────────────────────────────

/// Continuous surface texture — the FeelMyMac layer.
///
/// Called from `glideMTCallback` on the multitouch thread, right after the
/// TrackPoint and Edge Controls feeds. Unclaimed contacts play the global
/// material through the shared `MaterialPlayer`; contacts owned by another
/// feature are skipped so pulses never double up — one owner per contact
/// per frame (the blend rule).
///
/// P0 ownership:
/// - TrackPoint anchor → muted (decided Q2).
/// - Lone contact inside an active Edge Controls band → skipped; the edge
///   slider already ticks through its own accumulator.
/// - Everything else, including ordinary 1–2 finger moves and system scroll
///   (decided Q3) → the global material.
enum SurfaceFeelEngine {

    private static let player = MaterialPlayer()

    /// mm per normalised unit, cached — the pad's physical size never changes
    /// while the device is open.
    private static var mmPerUnitX: Double = 0
    private static var mmPerUnitY: Double = 0

    /// Re-resolves the MT-thread snapshot from `Settings`. Called from
    /// `Settings.apply(_:)` and the `surfaceFeel` / `hapticFeedbackEnabled`
    /// setters — i.e. wherever the cached value can go stale.
    static func settingsDidChange() {
        let s = Settings.shared
        TouchTracker.updateSurfaceFeelCache(SurfaceFeelSnapshot(
            enabled: s.surfaceFeel.enabled && s.hapticFeedbackEnabled,
            material: s.surfaceFeel.resolvedGlobalMaterial(),
            intensity: s.surfaceFeel.intensity,
            pressSizeScaling: s.surfaceFeel.pressSizeScaling
        ))
        MultitouchBridge.shared.updateMinimumContactCount()
    }

    /// Feeds one raw MT frame. Early-outs cost nothing when disabled.
    static func feed(points: UnsafePointer<GLDTouchPoint>?,
                     count: Int32,
                     timestamp: Double) {
        let ctx = TouchTracker.surfaceFeelFrameContext()
        guard ctx.snapshot.enabled else {
            // Disabled mid-touch: drop contact state so a re-enable starts clean.
            player.reset()
            return
        }

        guard let points, count > 0 else {
            player.reset()
            return
        }

        if mmPerUnitX == 0 {
            var w: Double = 0
            var h: Double = 0
            if GLDTGetSurfaceDimensions(&w, &h), w > 0, h > 0 {
                mmPerUnitX = w
                mmPerUnitY = h
            }
        }
        guard mmPerUnitX > 0 else { return }

        let n = Int(count)
        var active = 0
        for i in 0..<n {
            let t = points[i]
            if t.state >= 3 && t.state <= 4 { active += 1 }
        }
        // A lone contact while Edge Controls streams is the slider's finger
        // candidate — but only inside an active edge band; a lone finger
        // elsewhere on the pad is ordinary cursor work and keeps its texture.
        let edgeCandidate = ctx.edgeControlsStreaming && active == 1

        let snapshot = ctx.snapshot
        player.beginFrame()
        for i in 0..<n {
            let t = points[i]
            guard t.state >= 3 && t.state <= 4 else { continue }
            if t.identifier == ctx.trackPointAnchoredID { continue }
            if edgeCandidate && inActiveEdgeBand(t, zone: ctx.edgeZone) { continue }
            player.consume(contactID: t.identifier, x: t.x, y: t.y, size: t.size,
                           mmPerUnitX: mmPerUnitX, mmPerUnitY: mmPerUnitY,
                           material: snapshot.material, intensity: snapshot.intensity,
                           pressSizeScaling: snapshot.pressSizeScaling,
                           timestamp: timestamp)
        }
        player.endFrame()
    }

    /// Whether a touch sits inside the engagement band of an edge that
    /// currently hosts an Edge Controls action.
    private static func inActiveEdgeBand(_ t: GLDTouchPoint,
                                         zone: TouchTracker.EdgeControlsZone) -> Bool {
        guard zone.marginMm > 0 else { return false }
        if zone.left   && Double(t.x) * mmPerUnitX < zone.marginMm { return true }
        if zone.right  && Double(1 - t.x) * mmPerUnitX < zone.marginMm { return true }
        if zone.bottom && Double(t.y) * mmPerUnitY < zone.marginMm { return true }
        if zone.top    && Double(1 - t.y) * mmPerUnitY < zone.marginMm { return true }
        return false
    }
}
