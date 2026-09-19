import Cocoa
import Combine
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeControlsController
//
// Lifecycle owner and observable model for Trackpad Edge Controls.
// Bridges user preferences, MT callback frames, and the EdgeGestureEngine.
// ─────────────────────────────────────────────────────────────────────────────

final class EdgeControlsController: ObservableObject {
    static let shared = EdgeControlsController()

    @Published var isEnabled: Bool = true
    @Published var topEdge: EdgeAction = .none
    @Published var bottomEdge: EdgeAction = .none
    @Published var leftEdge: EdgeAction = .brightness
    @Published var rightEdge: EdgeAction = .volume
    @Published var marginMm: Double = 8.0
    @Published var activeEdge: TrackpadPhysicalEdge?

    private let engine = EdgeGestureEngine()

    var hasActiveEdgeControls: Bool {
        isEnabled && (topEdge != .none || bottomEdge != .none || leftEdge != .none || rightEdge != .none)
    }

    private init() {
        applySettings()
    }

    // MARK: - Settings Synchronization

    func applySettings() {
        let settings = Settings.shared.edgeControls
        self.isEnabled  = settings.enabled
        self.topEdge    = settings.topEdge
        self.bottomEdge = settings.bottomEdge
        self.leftEdge   = settings.leftEdge
        self.rightEdge  = settings.rightEdge
        self.marginMm   = settings.marginMm

        engine.config = EdgeGestureEngine.Configuration(
            isEnabled: settings.enabled,
            topAction: settings.topEdge,
            bottomAction: settings.bottomEdge,
            leftAction: settings.leftEdge,
            rightAction: settings.rightEdge,
            marginMm: settings.marginMm,
            activationTravelMm: settings.activationTravelMm,
            trackPointCornerZone: Self.trackPointCornerZone()
        )

        TouchTracker.updateEdgeControlsCache(enabled: hasActiveEdgeControls)
        MultitouchBridge.shared.updateMinimumContactCount()
        refreshSurfaceSize()

        if !settings.enabled {
            reset()
        }
    }

    /// Re-measures the trackpad. Only answers once the device is open, so it is worth
    /// asking again on every settings pass rather than caching a first, failed guess.
    func refreshSurfaceSize() {
        let measured = TrackpadSurfaceSize.measured()
        guard measured != engine.surfaceSize else { return }
        engine.surfaceSize = measured
        AppLogger.debug("[Edge] trackpad surface \(measured.width) x \(measured.height) mm")
    }

    /// The surface the engine is working against, for the preferences diagram and the
    /// diagnostics to report honestly.
    var surfaceSize: TrackpadSurfaceSize { engine.surfaceSize }

    func saveSettings() {
        var settings = Settings.shared.edgeControls
        settings.enabled    = isEnabled
        settings.topEdge    = topEdge
        settings.bottomEdge = bottomEdge
        settings.leftEdge   = leftEdge
        settings.rightEdge  = rightEdge
        settings.marginMm   = marginMm
        Settings.shared.edgeControls = settings

        engine.config = EdgeGestureEngine.Configuration(
            isEnabled: isEnabled,
            topAction: topEdge,
            bottomAction: bottomEdge,
            leftAction: leftEdge,
            rightAction: rightEdge,
            marginMm: marginMm,
            activationTravelMm: Settings.shared.edgeControls.activationTravelMm,
            trackPointCornerZone: Self.trackPointCornerZone()
        )

        TouchTracker.updateEdgeControlsCache(enabled: hasActiveEdgeControls)
        MultitouchBridge.shared.updateMinimumContactCount()
    }

    func reset() {
        engine.reset()
        activeEdge = nil
    }

    /// Whether a committed edge gesture currently holds the pointer frozen.
    /// Exposed so `--diag-edges` can observe the live pipeline rather than a copy.
    var isSuppressingPointer: Bool { engine.isSuppressingPointer }

    /// How much of each axis the TrackPoint's corner zone occupies, or 0 when it
    /// isn't corner-activated. Edge gestures steer clear of it so a corner touch
    /// can't be claimed by both features at once.
    private static func trackPointCornerZone() -> Double {
        let trackPoint = Settings.shared.trackPoint
        guard trackPoint.enabled, trackPoint.activationMode == .cornerZone else { return 0 }
        return Double(trackPoint.zoneSize)
    }

    // MARK: - Ingestion

    func ingest(touch: GLDTouchPoint?, contacts: Int, timestamp: TimeInterval) {
        guard isEnabled else { return }
        engine.consume(touch: touch, contacts: contacts, timestamp: timestamp)
        if activeEdge != engine.activeEdge {
            activeEdge = engine.activeEdge
        }
    }
}
