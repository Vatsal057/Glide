[← Back to manual](../USAGE.md)

# Trackpad Edge Controls

Trackpad Edge Controls turns the physical outer rim of your trackpad into precision hardware sliders. Sliding a single finger along any edge allows smooth adjustment of system volume, display brightness, keyboard backlight, microphone gain, Night Shift warmth, or application scrub.

Configure edge bindings in **Preferences → Edge Controls**.

## How It Works

1. **Physical Rim Sliders:** Each of the four edges (Left, Right, Top, Bottom) can be mapped to a dedicated action:
   - **Right Edge** *(default: System Volume):* Slide up to raise volume; slide down to lower volume.
   - **Left Edge** *(default: Display Brightness):* Slide up to brighten the display; slide down to dim it.
   - **Top / Bottom Edges** *(optional):* Assign to Keyboard Backlight, Microphone Input Gain, Night Shift, or App Switcher scrub.
2. **Native OSD Bezels:** Glide triggers native macOS system display bezels (identical to the overlays displayed by physical media keys). This operates with 0.0% CPU overhead and zero latency.
3. **Tactile Haptic Ticks:** Each adjustment increment delivers a subtle tactile tap via the trackpad Taptic Engine.

## Accidental Trigger Protection

Edge Controls incorporate multi-stage filtering to isolate rim gestures from standard pointer navigation:

- **Edge-Origin Only:** Touches must originate directly on the outer perimeter of the trackpad. Contacts originating within the primary trackpad surface are permanently excluded from edge actions.
- **Strict Rim Proximity:** Fingers must stay within the outer border zone (configurable, default 10 mm). Moving inward disengages edge control immediately.
- **Directional Gating:** Swipes must travel along the edge vector (vertically on left/right borders; horizontally on top/bottom borders). Inward perpendicular motions are filtered out.
- **Single-Contact Isolation:** Edge detection tracks single-finger touches. Registering two or more fingers immediately returns touch handling to native macOS gestures.

---
[← Previous: Troubleshooting](11-troubleshooting.md) · [Back to manual](../USAGE.md)
