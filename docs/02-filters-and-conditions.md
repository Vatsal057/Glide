[← Back to manual](../USAGE.md)

# Smart filters & conditions

Gesture behavior can be tailored with granular criteria. Expand the **Conditions** panel in the gesture editor to configure:

- **Keyboard modifiers:** Restrict a gesture to fire only while a specific key is held (**Command ⌘**, **Shift ⇧**, **Option ⌥**, or **Control ⌃**), or require that no modifier is active. This allows stacking multiple behaviors on the same physical gesture (for example, standard 3-finger swipe left/right browses apps, while Shift + swipe triggers window snapping).
- **App filter:** Scope a gesture to a specific application. A 3-finger click can close a tab in Safari while muting audio in Spotify, using independent rules for each application.
- **Window state filter:** Adjust behavior according to the frontmost window layout:
  - *Fullscreen:* Filling the screen in native macOS fullscreen mode.
  - *Not Fullscreen.*
  - *Maximized:* Resized to fill the screen while preserving the menu bar.
  - *Not Maximized.*

  This mechanism powers gesture ladders: swiping up once maximizes a standard window; swiping up again on that maximized window transitions into native fullscreen.
- **Reciprocal (reverse) gestures:** For swipes, the opposite direction automatically undoes the action. Swiping up maximizes a window; swiping down immediately restores it. Enabled by default for natural pairs (maximize ↔ restore, volume up ↔ down, next track ↔ previous). You can disable this behavior or assign an explicit reverse action in Conditions.
- **Corner zones (Force Click):** Restrict a Force Click to fire only when pressed inside a specific corner of the trackpad (**Top-Left**, **Top-Right**, **Bottom-Left**, or **Bottom-Right**), or allow it **Anywhere**. The default profile maps a top-left force click to full screenshot and top-right to area screenshot.<br><img src="../assets/gestures/force_click_corner.svg" width="280">
- **Continuous gestures:** Left/right and up/down swipes can run continuously. They execute a continuous begin → repeat → end loop as fingers move along the surface. This powers fluid scrub controls for volume, brightness, or timeline scrubbing.

---
[← Previous: Core concepts](01-core-concepts.md) · [Back to manual](../USAGE.md) · [Next: Every action, explained →](03-actions.md)
