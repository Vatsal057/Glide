// Self-check for the drag-anchor filter semantics (TouchTracker.filterDragAnchors).
// Run from repo root:
//   swiftc -o /tmp/drag_check Tests/drag_anchor_check.swift && /tmp/drag_check
//
// TouchTracker can't compile standalone (whole-module deps), so this mirrors the
// exact algorithm: fingers present at mouse-down are "anchors"; while the left
// button stays down they're removed from each frame so a swipe made with the
// OTHER fingers still reads at full count; anchors clear on button release.

struct Touch { let id: Int32 }

final class Filter {
    private var anchors: Set<Int32> = []

    func armDragAnchors(present: [Int32]) { anchors = Set(present) }
    var dragAnchorsActive: Bool { !anchors.isEmpty }

    func filter(_ touches: inout [Touch], leftButtonDown: Bool) {
        guard !anchors.isEmpty else { return }
        if leftButtonDown {
            touches.removeAll { anchors.contains($0.id) }
        } else {
            anchors.removeAll()
        }
    }
}

func ids(_ t: [Touch]) -> [Int32] { t.map(\.id) }

// Drag starts: one finger (id 1) down, left button pressed.
let f = Filter()
f.armDragAnchors(present: [1])
assert(f.dragAnchorsActive, "anchors armed")

// User adds a 3-finger swipe (ids 2,3,4) while dragging → anchor 1 removed,
// swipe still reads 3 fingers.
var frame = [Touch(id: 1), Touch(id: 2), Touch(id: 3), Touch(id: 4)]
f.filter(&frame, leftButtonDown: true)
assert(ids(frame) == [2, 3, 4], "drag finger filtered, swipe intact: \(ids(frame))")

// Drag-lock case: original finger lifted, only the swipe fingers remain.
var frame2 = [Touch(id: 2), Touch(id: 3), Touch(id: 4)]
f.filter(&frame2, leftButtonDown: true)
assert(ids(frame2) == [2, 3, 4], "no anchors left to strip: \(ids(frame2))")

// Button released → anchors clear, later frames untouched.
var frame3 = [Touch(id: 1), Touch(id: 2)]
f.filter(&frame3, leftButtonDown: false)
assert(!f.dragAnchorsActive, "anchors cleared on release")
f.filter(&frame3, leftButtonDown: true)
assert(ids(frame3) == [1, 2], "no filtering without anchors: \(ids(frame3))")

// No anchors armed → plain 3-finger swipe passes through untouched.
let g = Filter()
var plain = [Touch(id: 5), Touch(id: 6), Touch(id: 7)]
g.filter(&plain, leftButtonDown: false)
assert(ids(plain) == [5, 6, 7], "unarmed passthrough: \(ids(plain))")

print("drag-anchor self-check passed")
