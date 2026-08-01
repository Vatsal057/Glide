import Cocoa
import CoreGraphics

// ─────────────────────────────────────────────
// MARK: - CursorDriver
// ─────────────────────────────────────────────

/// Moves the system cursor by synthesizing mouse events.
///
/// Position is kept here in floating point rather than read back from the
/// system each tick: a 120 Hz driver at low speed produces sub-pixel steps,
/// and re-reading a rounded cursor position every tick would discard the
/// remainder and stall slow movement entirely.
///
/// Absolute `mouseMoved`/`mouseDragged` events are posted (rather than
/// `CGWarpMouseCursorPosition`) so apps see hover, tracking areas, and drags
/// exactly as they would from a real pointer.
final class CursorDriver {

    static let shared = CursorDriver()
    private init() {}

    /// Stamped into `eventSourceUserData` on everything we post, so Glide's own
    /// suppression tap can recognise these events and let them through. Without
    /// it the tap would swallow the very motion it asked for.
    static let syntheticMarker: Int64 = 0x476C_6964   // 'Glid'

    private lazy var eventSource = CGEventSource(stateID: .hidSystemState)
    private var displayFrames: [CGRect] = []
    private var position: CGPoint = .zero

    /// Latches onto wherever the cursor currently is. Call once per session.
    func begin() {
        displayFrames = Self.currentDisplayFrames()
        position = CGEvent(source: nil)?.location ?? .zero
    }

    /// Offsets the cursor in Core Graphics coordinates (y grows downward).
    func move(dx: CGFloat, dy: CGFloat) {
        let previous = position
        let target = CGPoint(x: previous.x + dx, y: previous.y + dy)
        position = resolve(target, from: previous)
        guard position != previous else { return }

        let (type, button) = Self.currentDragState()
        guard let source = eventSource ?? CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source,
                                  mouseType: type,
                                  mouseCursorPosition: position,
                                  mouseButton: button) else { return }
        // Apps that read deltas instead of absolute position (games, canvases,
        // custom scroll views) need these to see any movement at all.
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64((position.x - previous.x).rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((position.y - previous.y).rounded()))
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Screen geometry

    /// Keeps the cursor on a real display. A target that lands in the dead space
    /// of a staggered multi-monitor layout is retried one axis at a time, which
    /// both stops the cursor at the outer edge and still lets it slide along a
    /// shared border onto the neighbouring screen.
    private func resolve(_ target: CGPoint, from current: CGPoint) -> CGPoint {
        if displayFrames.isEmpty { displayFrames = Self.currentDisplayFrames() }
        if contains(target) { return target }

        let horizontalOnly = CGPoint(x: target.x, y: current.y)
        if contains(horizontalOnly) { return horizontalOnly }

        let verticalOnly = CGPoint(x: current.x, y: target.y)
        if contains(verticalOnly) { return verticalOnly }

        guard let frame = displayFrames.first(where: { $0.contains(current) }) else { return current }
        return CGPoint(x: min(max(target.x, frame.minX), frame.maxX - 1),
                       y: min(max(target.y, frame.minY), frame.maxY - 1))
    }

    private func contains(_ point: CGPoint) -> Bool {
        displayFrames.contains { $0.contains(point) }
    }

    /// `CGDisplayBounds` is already in the top-left origin space CGEvent uses,
    /// so no flipping against `NSScreen.frame` is needed.
    private static func currentDisplayFrames() -> [CGRect] {
        let frames = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }
        return frames.isEmpty ? [CGDisplayBounds(CGMainDisplayID())] : frames
    }

    /// Movement with a button held has to be posted as a drag or the drag ends.
    private static func currentDragState() -> (CGEventType, CGMouseButton) {
        if CGEventSource.buttonState(.combinedSessionState, button: .left)   { return (.leftMouseDragged, .left) }
        if CGEventSource.buttonState(.combinedSessionState, button: .right)  { return (.rightMouseDragged, .right) }
        if CGEventSource.buttonState(.combinedSessionState, button: .center) { return (.otherMouseDragged, .center) }
        return (.mouseMoved, .left)
    }
}
