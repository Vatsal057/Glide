[← Back to manual](../USAGE.md)

# Trackpad Edge Controls

Trackpad Edge Controls turns the physical outer rim of your trackpad into physical hardware sliders. By sliding a single finger along any edge of the trackpad, you can smoothly adjust system volume, display brightness, keyboard backlight, microphone gain, Night Shift warmth, or scrub through your open apps.

Configure it in **Preferences → Edge Controls**.

## How It Works

1. **Physical Rim Sliders**: Each of the four edges (Left, Right, Top, Bottom) can be mapped to an action:
   - **Right Edge** *(default: System Volume)*: Slide up to raise volume, slide down to lower volume.
   - **Left Edge** *(default: Display Brightness)*: Slide up to brighten the display, slide down to dim it.
   - **Top / Bottom Edges** *(optional)*: Map to Keyboard Backlight, Microphone Input Gain, Night Shift, or App Switcher scrub.
2. **Native OSD Bezels**: Glide triggers macOS's native system display bezels (the same overlay you see when pressing the physical F-keys). This requires 0% CPU overhead, has zero latency, and does not require running custom transparent HUD overlay processes.
3. **Subtle Haptic Ticks**: Each step or notch triggers a gentle haptic tap on the trackpad's Taptic Engine, giving you tactile feedback as you adjust values.

## Accidental Trigger Protection

Edge Controls are designed so you never trigger them by accident during normal cursor work:

- **Edge-Origin Only**: A touch must *originate* directly on the outer rim of the trackpad. If a finger lands in the center and moves toward the edge during a normal cursor drag, it is permanently disqualified from triggering an edge control.
- **Strict Rim Proximity**: The finger must remain touching the outer edge. If your finger moves inward into the trackpad surface beyond the edge zone width (configurable, default 8 mm), the control immediately disengages.
- **Directional Gating**: Swiping must occur *along* the edge (e.g. vertically on the left/right edges). Inward perpendicular motions are ignored.
- **Single-Contact Isolation**: Edge controls strictly monitor 1-finger touches. Placing 2 or more fingers on the trackpad immediately hands control back to macOS scrolling, pinching, or multi-finger gestures.

---
[← Previous: Troubleshooting](11-troubleshooting.md) · [Back to manual](../USAGE.md)
