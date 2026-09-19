# Security Policy

## Reporting a vulnerability

Please report security issues **privately**, not as a public issue.

Use GitHub's private vulnerability reporting:
[**Report a vulnerability**](https://github.com/Vatsal057/Glide/security/advisories/new)

That opens a private advisory visible only to you and the maintainer. I'll
acknowledge it as soon as I can, and I'd ask that you hold off on public
disclosure until a fix ships.

Glide is maintained by one person in their spare time, so please be realistic
about response times. I'd rather receive a report late than not at all.

## Supported versions

Fixes go into the latest release. Only the most recent version is supported —
Glide has an in-app updater, so staying current is a single click in
**Preferences → General → Check for Updates**.

| Version | Supported |
| :--- | :--- |
| Latest release | ✅ |
| Anything older | ❌ |

## What Glide can do on your Mac

Worth stating plainly, because Glide legitimately holds permissions that would
be alarming in the wrong hands. If you are auditing it, these are the places to
look.

**Accessibility access (required).** Glide installs `CGEventTap`s and global
`NSEvent` monitors, which means it can observe input system-wide, and it uses
the Accessibility API to move, focus, and close windows in other applications.
There is no way to build a gesture app on macOS without this. The taps are in
`Sources/Gestures/Components/GestureInputManager.swift`; the broad-mask one is
deliberately created disabled and only armed while three or more fingers are
down.

**Screen Recording access (optional).** Used only to draw window thumbnails in
the app switcher, via `CGWindowListCreateImage`. Glide works without it and
falls back to app icons. See `Sources/UI/AppSwitcherOverlay.swift`.

**Private system APIs.** Glide links `MultitouchSupport` for raw trackpad
contacts and SkyLight/`WindowServer` symbols for window and Space information,
both resolved at runtime with `dlopen`/`dlsym`. See
`Sources/Gestures/Components/GlideMultitouchBridge.c` and
`Sources/Actions/Components/GlideWindowServerBridge.c`. These are unsupported
interfaces; they can change or disappear between macOS releases, and Glide
degrades rather than crashing when a symbol is missing.

**User-configured code execution.** A gesture can be bound to a shell command,
an AppleScript, or a Shortcuts.app shortcut. That is the point of the feature,
but it means **your configuration file is as trusted as your shell**. Do not
import a `config.yaml` from someone you don't trust — read it first. It lives at
`~/Library/Application Support/Glide/config.yaml`.

**The in-app updater.** Glide downloads a DMG from this repository's GitHub
Releases over HTTPS, verifies it against the published `.sha256` checksum, and
refuses to install an image whose app fails signature verification. See
`Sources/App/Internal/UpdateChecker.swift` and `UpdateInstaller.swift`, and the
`Verify Release Artifacts` step in `.github/workflows/release.yml`. If you find
a way to get Glide to install something that isn't the signed release artifact,
that's a serious bug and I want to hear about it.

## What Glide does not do

- **No telemetry, no analytics, no crash reporting.** Nothing is collected.
- **No network access except the update check** against the GitHub Releases API,
  and that can be ignored entirely.
- **Nothing leaves your Mac.** Gesture configuration, window titles, and
  captured thumbnails stay local. Thumbnails live in memory only and are
  discarded when the switcher closes.
- **No bundled dependencies.** Glide is Swift and C against system frameworks,
  with no third-party packages, so there is no dependency supply chain to
  compromise.

## Notarization

Glide is **signed but not notarized**, because notarization requires a paid
Apple Developer account. macOS will warn you on first launch. This is a real
gap: notarization is Apple's malware scan, and Glide does not have it.

If you would rather not trust a signed-but-unnotarized binary, build from
source — `./build.sh --release` is the whole process, and it's the same script
CI uses. Every release also publishes a SHA-256 checksum so you can confirm the
DMG you downloaded matches the one CI produced.
