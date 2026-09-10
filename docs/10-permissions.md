[← Back to manual](../USAGE.md)

# Permissions Glide asks for

| Permission | Why | If you don't grant it |
|---|---|---|
| **Accessibility** | Reads trackpad touches and controls windows (moving, resizing, focusing). | **Required.** Glide won't detect any gestures at all without it. |
| **Screen Recording** | Renders live window thumbnails in the newer App Switcher overlay. | Optional. The switcher still works — it falls back to showing each app's icon instead of a live preview. |
| **Automation (Apple Events)** | Runs AppleScript actions you configure, and reads app menus so you can assign a menu item to a gesture. | Optional. Only the "AppleScript…" and "Menu Item…" actions are affected. |

Glide never makes a network request except to check GitHub for a new release when you ask it to, or to download one you've chosen to install. There's no telemetry and no analytics.

---
[← Previous: Your configuration file](09-configuration-file.md) · [Back to manual](../USAGE.md) · [Next: Troubleshooting →](11-troubleshooting.md)
