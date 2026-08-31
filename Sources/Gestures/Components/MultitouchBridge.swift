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
    /// the bridge. The corner TrackPoint lowers it to 1 while it is enabled.
    func setMinimumContactCount(_ count: Int) {
        GLDTSetMinimumContactCount(Int32(count))
    }
}
