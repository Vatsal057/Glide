import Foundation

// ─────────────────────────────────────────────
// MARK: - MultitouchBridge
// ─────────────────────────────────────────────

final class MultitouchBridge {

    static let shared = MultitouchBridge()
    private init() {}

    private(set) var isRunning = false

    // MARK: Start

    func start(callback: @escaping GLDTFrameCallback) {
        guard !isRunning else { return }
        if GLDTStart(callback, nil) {
            isRunning = true
            AppLogger.debug("[MT] Started C-Bridge")
        } else {
            AppLogger.debug("[MT] Failed to start C-Bridge. Status: \(GLDTGetLastStartStatus())")
        }
    }

    // MARK: Stop

    func stop() {
        guard isRunning else { return }
        GLDTStop()
        isRunning = false
        AppLogger.debug("[MT] Stopped C-Bridge")
    }

    // MARK: Frame gating

    /// Fewest contacts a frame must carry to reach Swift. Defaults to 3 — every
    /// gesture rule's floor — so one- and two-finger cursor work never crosses
    /// the bridge. The corner TrackPoint and Edge Controls lower it to 1 while enabled.
    func setMinimumContactCount(_ count: Int) {
        GLDTSetMinimumContactCount(Int32(count))
    }

    /// Coordinates TrackPoint and Edge Controls requirements so neither overrides the other.
    func updateMinimumContactCount() {
        let trackPointActive = Settings.shared.trackPoint.enabled
        let edgeControlsActive = Settings.shared.edgeControls.enabled && (
            Settings.shared.edgeControls.topEdge != .none ||
            Settings.shared.edgeControls.bottomEdge != .none ||
            Settings.shared.edgeControls.leftEdge != .none ||
            Settings.shared.edgeControls.rightEdge != .none
        )
        setMinimumContactCount((trackPointActive || edgeControlsActive) ? 1 : 3)
    }
}
