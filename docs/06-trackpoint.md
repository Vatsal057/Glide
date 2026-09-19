[← Back to manual](../USAGE.md)

# TrackPoint

TrackPoint turns a zone of your trackpad into a velocity-driven pointer, similar to the pointing stick found on classic laptop keyboards. TrackPoint maps your finger's displacement from its initial contact point directly to cursor velocity. Leaning in any direction moves the cursor continuously at a speed proportional to displacement. This enables smooth navigation across expansive desktop layouts and multi-monitor displays from a compact touch zone. Enable and configure it in **Preferences → TrackPoint**.

### Activation Modes

Specify how pointer velocity mode engages:

| Mode | How to engage |
|---|---|
| Double-Tap & Hold *(default)* | Tap once, tap a second time, and hold. The deliberate double-tap sequence prevents accidental triggers during resting contacts.<br><img src="../assets/gestures/trackpoint_double_tap.svg" width="280"> |
| One-Finger Hold | Rest one finger anywhere on the pad and remain still for a brief interval.<br><img src="../assets/gestures/trackpoint_one_finger_hold.svg" width="280"> |
| Corner Hold | Rest one finger in a designated corner and hold briefly, preserving the remainder of the trackpad for standard pointer use.<br><img src="../assets/gestures/trackpoint_corner_hold.svg" width="280"> |
| Two-Finger Hold | Rest two fingers in place; lifting one finger transitions the remaining contact into pointer mode.<br><img src="../assets/gestures/trackpoint_two_finger_hold.svg" width="280"> |

A brief hold confirms engagement. Moving significantly prior to hold completion yields control back to default macOS cursor handling.

### Pointer Interaction

- Push your finger outward from the anchor point to accelerate the cursor. Moving back toward the center decelerates motion. Movement continues for the duration of the touch.
- Rest a **second finger** on the pad to transition the stick into high-speed directional scrolling.<br><img src="../assets/gestures/trackpoint_scroll_mode.svg" width="280">
- Lift your fingers to disengage and return pointer handling to macOS.
- Subtle haptic feedback confirms engagement and disengagement when haptics are enabled.

### Tunable Parameters

Adjust top speed, push distance (travel required for maximum velocity), center dead zone, smoothing, and acceleration curves in **Preferences → TrackPoint**. Corner mode includes configurable zone dimensions and visual corner selection.

**Smoothing** deserves a note, since it is what makes small pushes controllable. A stick operates over deflections of just a few millimetres, and at that scale ordinary finger tremor is a large fraction of the signal. It shows up partly as speed jitter, but mostly as *direction* wander: when the push is short, a small absolute wobble swings the aim a long way.

Glide therefore eases the push toward what your finger is actually doing rather than taking each multitouch frame at face value. The filter runs on the clock rather than per frame, so the feel is the same whether frames arrive at 60 Hz or 125 Hz.

At the 22 ms default this cuts direction wander from roughly 2.1° to 0.9° against simulated 0.3 mm tremor, costing about 28 ms to reach 63% of speed from rest. The speed a held push *settles* at is unchanged, so smoothing does not interact with the other Feel settings — it only affects how the cursor gets there. Raise it toward "Glassy" for steadier aim at the cost of immediacy; set it to zero to restore the completely unfiltered behaviour.

---
[← Previous: App Switcher](05-app-switcher.md) · [Back to manual](../USAGE.md) · [Next: Tuning & precision controls →](07-tuning.md)
