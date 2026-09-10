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
            marginMm: settings.marginMm
        )

        TouchTracker.updateEdgeControlsCache(enabled: hasActiveEdgeControls)
        MultitouchBridge.shared.updateMinimumContactCount()

        if !settings.enabled {
            reset()
        }
    }

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
            marginMm: marginMm
        )

        TouchTracker.updateEdgeControlsCache(enabled: hasActiveEdgeControls)
        MultitouchBridge.shared.updateMinimumContactCount()
    }

    func reset() {
        engine.reset()
        activeEdge = nil
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
