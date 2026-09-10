[← Back to manual](../USAGE.md)

# Troubleshooting

**Gestures aren't doing anything.**
Check the sidebar of the Preferences window — it shows whether gestures are active or paused, and whether Accessibility permission is granted. If permission shows as missing, grant it in **System Settings → Privacy & Security → Accessibility**, then toggle Glide off and back on in that list (a re-grant after an update sometimes needs a toggle to take effect).

**A gesture triggers the wrong action, or nothing happens when two rules look similar.**
Open **Preferences → Gestures** — a rule shadowed by a later, identical-trigger rule shows a warning icon. The rule lower in the list always wins.

**Swipes fire by accident when my palm rests on the trackpad.**
Widen the **Edge Margins** in **Preferences → Tuning**, especially on whichever edge your palm tends to touch. The visual trackpad preview there shows exactly where your touches land in real time.

**A gesture I use conflicts with a normal three/four-finger macOS gesture (like swiping between desktops).**
Check **Preferences → General → macOS Gesture Conflicts** — Glide detects these and can disable the native one for you, without needing you to dig through System Settings yourself.

**The app switcher shows app icons instead of window previews.**
That means Screen Recording access hasn't been granted. It's optional — switching works fine without it — but if you want previews, **Preferences → App Switcher** has a direct link to the right System Settings page.

**"App can't be opened because it is from an unidentified developer" or "is damaged."**
Neither is true — this is just Gatekeeper reacting to an unsigned, non-notarized open-source app. Right-click Glide in Applications and choose **Open**, or if macOS says it's "damaged," run:

```sh
xattr -cr /Applications/Glide.app
```

Full details in [Installation](../README.md#installation).

**Still stuck?** [Open an issue](https://github.com/Vatsal057/Glide/issues) — include your macOS version and, if it's gesture-related, which fingers/direction/action you expected.

---
[← Previous: Permissions Glide asks for](10-permissions.md) · [Back to manual](../USAGE.md)
