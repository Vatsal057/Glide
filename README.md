<div align="center">

<img src="assets/hero.png" alt="Glide" width="640">

# Glide

**Free, lightweight trackpad gestures, physical edge sliders, and global shortcuts for macOS.**

[![Release](https://img.shields.io/github/v/release/Vatsal057/Glide?label=release)](https://github.com/Vatsal057/Glide/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)](#installation)

[Download DMG](https://github.com/Vatsal057/Glide/releases/latest) · [Usage Manual](USAGE.md) · [Report an Issue](https://github.com/Vatsal057/Glide/issues)

</div>

---

Glide turns your Mac trackpad into a customizable control surface for window management, 2D app switching, system adjustments, and keyboard automation.

Written in pure Swift using low-level `MultitouchSupport` and `WindowServer` APIs, Glide idles at 0.0% CPU, uses ~25 MB of RAM, and runs entirely event-driven with zero idle battery drain.

## Default Gestures

Glide runs quietly in the menu bar (`hand.draw` icon). These inputs work out of the box:

| Input | Action |
| :--- | :--- |
| **Slide finger along right edge** | **System volume up / down** |
| **Slide finger along left edge** | **Display brightness up / down** |
| **3-finger swipe left / right** | **2D App Switcher** (horizontal apps, vertical window decks) |
| **3-finger swipe up** | **Mission Control** |
| **3-finger swipe down** | **Minimize all windows** |
| **3-finger click** | **Quit frontmost app** (or close window) |
| **3-finger force-click top corners** | **Screenshot to clipboard** (left: full screen, right: area selection) |
| **4-finger swipe up** | **Maximize window** (repeat on maximized window: enter fullscreen) |
| **4-finger swipe down** | **Restore window** (repeat: minimize) |
| **4-finger swipe left / right** | **Snap window left / right half** |
| **Double-tap & hold trackpad** | **TrackPoint mode** (velocity pointer; add second finger to scroll) |

> **Edge Sliders:** Controls activate only when touch begins directly on the physical outer rim of the trackpad. Cursor motion that drifts across the edge is ignored.
>
> **Window Ladders:** 4-finger swipes up and down adapt to the active window's current state (normal ↔ maximized ↔ fullscreen) without needing separate gesture triggers.

Everything is customizable. Press `⌘,` with the app focused or click the menu bar icon to open **Preferences**.

## Why Glide?

macOS limits trackpad gestures to a few fixed actions. The traditional alternative, BetterTouchTool, has been a paid utility with unnecessary CPU drain and battery usage.

Glide provides deep trackpad and desktop control: advanced touchpad gestures, edge sliders, feature rich app switching, Revolutionary Trackpoint for macos, and global macros in a lean, open-source utility that runs ideally at 0.0% CPU.

| Capability | Glide | BetterTouchTool | macOS Default |
| :--- | :--- | :--- | :--- |
| **License** | **Free & Open Source (MIT)** | Paid ($10 to $24+) | Built-in |
| **Idle Memory** | **~25 MB RAM** | 150–300+ MB RAM | Negligible |
| **Idle CPU / Battery** | **0.0% CPU (event-driven, zero idle drain)** | Ongoing background polling | None |
| **Physical Edge Sliders** | **Hardware rim sliders (volume, brightness, scrub)** | Requires custom scripting | None |
| **Window State Ladders** | **State-adaptive chaining (maximize → fullscreen)** | Manual multi-rule setup | None |
| **Reverse Action Gestures** | **Automatic opposite-direction undo** | Manual inverse rule setup | None |
| **2D Spatial App Switcher** | **Horizontal app flow + vertical window decks** | 1D switcher | ⌘Tab (apps only) |
| **TrackPoint Velocity Mode** | **Trackpad pointer stick simulation + 2-finger scroll** | None | None |
| **Global Shortcuts Engine** | **Hotkeys, menu items, key sequences, scripts** | Supported | Shortcuts app (limited) |
| **Configuration UI** | **Native SwiftUI with live animated previews** | Dense multi-pane menus | System Settings |
| **Telemetry & Privacy** | **100% offline, zero telemetry** | Proprietary closed-source | Apple diagnostics |

## Core Features

- **Multi-Finger Gestures:** 3, 4, and 5-finger swipes, clicks, force-clicks, and holds with configurable flick vs. glide speed classification.
- **Physical Rim Sliders:** Slide along the trackpad's physical border to adjust volume, brightness, keyboard backlight, or scrub the App Switcher.
- **State-Aware Ladders & Reciprocals:** Swipes adapt to current window state (maximize → fullscreen), and opposite gestures reverse actions automatically.
- **2D Spatial App Switcher:** Swipe horizontally across running applications and vertically through window decks with live thumbnails.
- **TrackPoint Velocity Mode:** Anchor a finger on the pad to drive continuous cursor velocity across multiple monitors, with second-finger directional scrolling.
- **Smart Conditions & Filters:** Restrict any gesture or shortcut by active application, modifier keys, or window state.
- **Global Shortcuts & Automation:** Trigger window snaps, application menu items, keystroke sequences, AppleScripts, shell commands, or macOS Shortcuts.
- **Tuning & Live Previews:** One-click presets (**Relaxed**, **Balanced**, **Precise**), customizable edge dead-zones, palm rejection, and real-time animated touch previews.

## Installation

### Direct Download (Recommended)

1. Download the latest **Glide-vX.Y.Z.dmg** from the [Releases page](https://github.com/Vatsal057/Glide/releases/latest).
2. Open the DMG and drag **Glide** into your **Applications** folder.
3. Launch Glide from Applications. Because Glide is an independent open-source app distributed outside the App Store, macOS Gatekeeper may prompt on first launch:
   - **Right-click** (or Control-click) Glide in Applications and select **Open**, then click **Open**.
   - On **macOS 15 (Sequoia)**: If Open is unavailable, launch Glide once, go to **System Settings → Privacy & Security**, and click **Open Anyway**.
   - If macOS reports *"Glide is damaged and can't be opened"*, clear the quarantine flag in Terminal:
     ```sh
     xattr -cr /Applications/Glide.app
     ```
4. Grant **Accessibility** permission when prompted (**System Settings → Privacy & Security → Accessibility**). Glide requires this to read trackpad touches and manage window positions.

> **Optional Permissions:** Screen Recording is optional for window thumbnails in the App Switcher (falls back to app icons if omitted). Automation is requested only if you run custom AppleScripts or menu commands.

### Build from Source

Requirements: macOS 13+ and Xcode Command Line Tools.

```sh
git clone https://github.com/Vatsal057/Glide.git
cd Glide
./build.sh
```

To create a release DMG:

```sh
./build.sh --dmg
```

### In-App Updates

Glide includes built-in release checking. Open **Preferences → General** and click **Check for Updates**, or select **Check for Updates…** from the menu bar icon. Updates download, verify checksums, and relaunch automatically in place.

## Documentation

Detailed documentation is available in the [docs/](docs/) directory:

- [Usage Manual Overview](USAGE.md) — Complete feature and settings guide.
- [Core Concepts](docs/01-core-concepts.md) — Fingers, swipe speeds, clicks, and conflict resolution.
- [Smart Filters & Conditions](docs/02-filters-and-conditions.md) — Modifiers, app filters, and window state ladders.
- [Action Catalog](docs/03-actions.md) — Complete reference of all window, app, media, and system actions.
- [Global Keyboard Shortcuts](docs/04-keyboard-shortcuts.md) — Hotkey binding and macro execution.
- [App Switcher Guide](docs/05-app-switcher.md) — 2D spatial navigation and window deck switching.
- [TrackPoint Guide](docs/06-trackpoint.md) — Trackpad pointer stick velocity mode and scroll controls.
- [Tuning & Calibration](docs/07-tuning.md) — Sensitivity, diagonal strictness, and palm rejection.
- [General Preferences](docs/08-general-preferences.md) — Window targeting, haptics, and system gesture conflicts.
- [Configuration File](docs/09-configuration-file.md) — Editing, exporting, and importing `config.yaml`.
- [Permissions](docs/10-permissions.md) — Why Accessibility and Screen Recording permissions are used.
- [Troubleshooting](docs/11-troubleshooting.md) — Common questions and resolution steps.
- [Trackpad Edge Controls](docs/12-edge-controls.md) — Edge slider architecture and sensitivity tuning.

## Contributing

Bug reports, feature requests, and pull requests are welcome. Please check [open issues](https://github.com/Vatsal057/Glide/issues) before opening a new issue.

## License

Glide is open source under the [MIT License](LICENSE).

