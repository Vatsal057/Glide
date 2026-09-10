[← Back to manual](../USAGE.md)

# App Switcher

The App Switcher is a hold-and-swipe interface to browse and switch between active applications. It is reserved on **3-finger left/right swipes** by default. Toggle and configure it in **Preferences → App Switcher**.

**How it works:** Swipe left or right with 3 fingers to browse apps, and release to switch. Lift fingers away from the surface to cancel. In the **Newer** presentation style, swiping up or down selects specific windows within multi-window applications.

<p align="center">
  <img src="../assets/gesture_app_switcher.svg" alt="App Switcher 2D Spatial Navigation Gesture" width="680">
</p>

### Why Vertical Swipes for Window Switching?

Standard macOS app switching (`⌘Tab`) operates strictly at the application level. When an application has multiple open windows (such as multiple browser windows, terminal sessions, or project documents), targeting a specific window requires secondary shortcuts (such as `⌘\``) or Mission Control.

Glide introduces **2D spatial navigation**:
- **Horizontal swipes (left/right):** Cycle through running applications.
- **Vertical swipes (up/down):** Navigate the window deck of the currently highlighted app.

This enables direct switching to any active window in a single trackpad motion.

### How to Use Window Switching

1. Verify that **Newer** presentation style is selected in **Preferences → App Switcher** (default setting).
2. **Initiate the switcher:** Swipe left or right with 3 fingers and keep fingers in contact with the trackpad.
3. **Select an app:** Swipe horizontally to highlight the target application.
4. **Select a window:** If the application has multiple open windows, swipe **up or down** with 3 fingers to cycle through its window deck. Live window previews appear when Screen Recording permission is active; application icons display otherwise.
<br><img src="../assets/gestures/app_switcher.svg" width="320">
5. **Commit:** Release all fingers to focus the selected window immediately.
6. **Cancel:** Lift all fingers without making a selection.

**Presentation styles:**
- **Newer:** Custom overlay featuring 2D navigation (horizontal app browsing and vertical window selection) with live window thumbnails or app icons.
- **Legacy:** Converts swipes directly into native `⌘Tab` events handled by macOS. Operates with minimal permissions across all macOS versions.

Because the switcher reserves 3-finger horizontal swipes, custom gestures on this trigger require a modifier key (such as Shift). The editor indicates when this applies.

Additional configuration options include skipping windowless Finder processes, auto-restoring minimized windows on selection, toggling selection animations (disabled by default to maintain minimal CPU usage during swipes), and adjusting step distance thresholds.

---
[← Previous: Global keyboard shortcuts](04-keyboard-shortcuts.md) · [Back to manual](../USAGE.md) · [Next: TrackPoint →](06-trackpoint.md)
