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
            print("[MT] Failed to start C-Bridge. Status: \(GLDTGetLastStartStatus())")
        }
    }

    // MARK: Stop

    func stop() {
        guard isRunning else { return }
        GLDTStop()
        isRunning = false
        AppLogger.debug("[MT] Stopped C-Bridge")
    }
}
