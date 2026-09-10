[← Back to manual](../USAGE.md)

# Troubleshooting

**Gestures are not registering:**
Verify the status card in the Preferences sidebar. It indicates whether gesture recognition is active and whether Accessibility permission has been granted. If permission appears inactive, enable it under **System Settings → Privacy & Security → Accessibility**. Toggling the checkbox off and back on may be required following an application update.

**A gesture triggers an unintended action or appears ignored:**
Check the Gestures list in **Preferences → Gestures**. Rules sharing an identical trigger display a warning badge, indicating that a rule lower in the list takes precedence.

**Swipes trigger inadvertently when palms contact the pad:**
Increase the **Edge Margins** under **Preferences → Tuning** along the corresponding border. The real-time touch coordinate display indicates exact contact locations.

**A custom gesture conflicts with native macOS multi-touch swipes:**
Inspect **Preferences → General → macOS Gesture Conflicts**. Glide detects overlapping system gestures and can disable the native trigger directly, with options to re-enable at any time.

**The app switcher displays application icons when window thumbnails are expected:**
Screen Recording permission is required for live window thumbnails. To enable previews, grant permission via the link provided in **Preferences → App Switcher**.

**Gatekeeper reports the application cannot be verified or is damaged:**
This represents standard macOS Gatekeeper verification for independent open-source applications distributed outside the App Store. Right-click Glide in Applications and choose **Open**, or clear the quarantine attribute via Terminal:

```sh
xattr -cr /Applications/Glide.app
```

Refer to the [Installation guide](../README.md#installation) for complete setup steps.

**Assistance and reporting:**
If an issue persists, [submit a report on GitHub](https://github.com/Vatsal057/Glide/issues) with your macOS version, trackpad model, and gesture configuration.

---
[← Previous: Permissions Glide asks for](10-permissions.md) · [Back to manual](../USAGE.md)
