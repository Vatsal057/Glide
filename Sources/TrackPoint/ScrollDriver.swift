import Cocoa
import CoreGraphics

// ─────────────────────────────────────────────
// MARK: - ScrollDriver
// ─────────────────────────────────────────────

/// Emits scroll wheel events for the TrackPoint's scroll stick.
///
/// Pixel units rather than lines, so slow pushes scroll smoothly instead of
/// jumping a line at a time. Wheel deltas are integers, so the fractional part
/// of each step is carried forward — without that, any push whose per-tick
/// distance rounds below one pixel would scroll nothing at all, and the slow end
/// of the range would be dead.
final class ScrollDriver {

    static let shared = ScrollDriver()
    private init() {}

    private lazy var eventSource = CGEventSource(stateID: .hidSystemState)
    private var residualVertical = 0.0
    private var residualHorizontal = 0.0

    /// Clears carried-over fractions. Call once per session.
    func begin() {
        residualVertical = 0
        residualHorizontal = 0
    }

    /// - Parameters:
    ///   - vertical: points to scroll, positive scrolls toward the start of the document.
    ///   - horizontal: points to scroll, positive scrolls toward the left.
    func scroll(vertical: Double, horizontal: Double) {
        residualVertical += vertical
        residualHorizontal += horizontal

        let stepVertical = residualVertical.rounded(.towardZero)
        let stepHorizontal = residualHorizontal.rounded(.towardZero)
        guard stepVertical != 0 || stepHorizontal != 0 else { return }
        residualVertical -= stepVertical
        residualHorizontal -= stepHorizontal

        guard let source = eventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Int32(stepVertical),
                                  wheel2: Int32(stepHorizontal),
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: CursorDriver.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}
