[← Back to manual](../USAGE.md)

# Core concepts

Glide lets you control your Mac using fluid trackpad movements alongside global keyboard shortcuts. Open **Preferences → Gestures** to inspect and edit them. Every gesture is built from a few foundational elements:

- **Finger count:** Gestures use **3**, **4**, or **5** fingers.
  <br><img src="../assets/gestures/four_finger_swipe.svg" width="220">
- **Gesture type:**
  - **Swipe:** Sliding your fingers in a direction (**Up**, **Down**, **Left**, or **Right**).
    <br><img src="../assets/gestures/swipe_up.svg" width="220"> <img src="../assets/gestures/swipe_down.svg" width="220">
    <br><img src="../assets/gestures/swipe_left.svg" width="220"> <img src="../assets/gestures/swipe_right.svg" width="220">
  - **Click:** Pressing down on the trackpad with all fingers in place, similar to a standard click with multiple touch contacts.
    <br><img src="../assets/gestures/click.svg" width="220">
  - **Force Click:** Pressing down harder on a Force Touch trackpad past the primary click, triggering a secondary action.
    <br><img src="../assets/gestures/force_click.svg" width="220">
  - **Tap & Hold:** Resting fingers motionless on the trackpad surface.
    <br><img src="../assets/gestures/tap_hold.svg" width="220">
- **Swipe speed:** The same swipe direction can map to two distinct actions based on movement velocity: **Slow**, **Normal**, or **Fast**. For example, a slow 3-finger swipe right can switch to the next window, while a fast flick right launches your terminal. Speed applies exclusively to swipes. Clicks and holds maintain immediate triggering.

<p align="center">
  <img src="../assets/gesture_window_management.svg" alt="Gesture Controls Diagram" width="680">
</p>

Add a gesture with the **+** button in the Gestures list, then set its finger count, type, and action in the editor. New gestures start as an inactive draft (marked with a pause icon) until an action is selected.

If two gestures share the identical trigger (same fingers, direction, speed, and filters), the rule lower in the list takes precedence. The interface marks shadowed gestures with a warning indicator.

---
[← Back to manual](../USAGE.md) · [Next: Smart filters & conditions →](02-filters-and-conditions.md)
