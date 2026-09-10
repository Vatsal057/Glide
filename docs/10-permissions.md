[← Back to manual](../USAGE.md)

# Permissions Glide asks for

| Permission | Purpose | Impact if disabled |
|---|---|---|
| **Accessibility** | Reads trackpad multi-touch coordinates and manages window layouts. | **Required.** Core gesture detection and window actions depend on this permission. |
| **Screen Recording** | Renders live window thumbnails in the App Switcher overlay. | Optional. The switcher displays standard application icons when omitted. |
| **Automation (Apple Events)** | Executes configured AppleScript commands and inspects application menus for menu-item triggers. | Optional. Applies exclusively to "AppleScript…" and "Menu Item…" actions. |

Glide operates locally on your Mac. Network requests occur exclusively when querying GitHub for application updates. No telemetry, analytics, or background reporting services are included.

---
[← Previous: Your configuration file](09-configuration-file.md) · [Back to manual](../USAGE.md) · [Next: Troubleshooting →](11-troubleshooting.md)
