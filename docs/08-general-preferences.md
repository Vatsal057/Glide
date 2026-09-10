[← Back to manual](../USAGE.md)

# General preferences

**Preferences → General** covers app-wide behavior:

- **Accessibility Permission** — a status card showing whether Glide has the access it needs, with a one-click button to the right System Settings page if not.
- **Window Targeting** — whether window actions (minimize, snap, close, etc.) target the window you're actively focused on, or the window your mouse is hovering over, when the two differ.
- **Debug Logging** — writes gesture detail to the system Console, for troubleshooting.
- **Launch at Login** — starts Glide automatically when you log in.
- **Haptics** — toggle trackpad vibration feedback overall, and assign a specific pattern (soft tick, tap, knock, double tap, rising, falling, etc.) to each kind of event: destructive actions, window actions, app switcher steps, reciprocal gestures, and so on. Selecting a pattern plays it immediately so you can feel the difference.
- **macOS Gesture Conflicts** — Glide can detect when one of its own gestures shares a trigger with a *native* macOS trackpad gesture (which would otherwise fire both, or fight for the same touch) and offers to disable the native one for you. Anything Glide disables this way is tracked separately so you can re-enable it individually, or all at once, later. Enable "Auto-Disable" to have this happen automatically as conflicts arise.
- **Stats** — live counts of your gestures (total, active, using each finger count), reciprocal pairs, modifier-restricted gestures, and any "Open App…" gestures pointing at an app that's no longer installed.
- **Updates** — checks GitHub for a newer release and, if there is one, downloads and installs it in place with a progress bar and checksum verification, finishing with a **Relaunch Now** button. If Glide can't write to its own install location, it hands you the downloaded disk image instead so you can install manually.
- **Welcome Tour** — replay the first-launch onboarding at any time.

---
[← Previous: Tuning & precision controls](07-tuning.md) · [Back to manual](../USAGE.md) · [Next: Your configuration file →](09-configuration-file.md)
