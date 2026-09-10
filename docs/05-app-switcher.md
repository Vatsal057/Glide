[← Back to manual](../USAGE.md)

# App Switcher

The App Switcher is a hold-and-swipe way to browse and jump between running apps — separate from the gesture rule list, and reserved on **3-finger left/right swipes** by default. Turn it on or off, and configure it, in **Preferences → App Switcher**.

**How it works:** swipe left or right with 3 fingers to browse apps, and release to switch — or lift all fingers without committing to cancel.

**Two presentation styles:**
- **Newer** — Glide's own overlay: app icons in a row, a window "deck" for the selected app if it has more than one window (swipe up or down to pick a specific one), live thumbnails of each window when Screen Recording access is granted (falls back to app icons if not — switching still works either way).
- **Legacy** — converts your swipe directly into native ⌘Tab events and lets the system's own switcher UI handle it. No extra permissions needed, works on every macOS version, but no custom overlay and no per-window selection — it's exactly what ⌘Tab already does, just triggered by a swipe.

Because it reserves the 3-finger horizontal swipe, any gesture you create on that same trigger needs a modifier key (like holding Shift) to coexist with it — the editor will tell you when this applies.

Other settings: skip Finder in the switcher when it has no open windows, restore minimized windows automatically when you select them, animate selection changes (off by default — it roughly doubles the CPU cost of a swipe), and two sliders for how far you need to swipe to step to the next app and how quickly repeated steps can happen.

---
[← Previous: Global keyboard shortcuts](04-keyboard-shortcuts.md) · [Back to manual](../USAGE.md) · [Next: TrackPoint →](06-trackpoint.md)
