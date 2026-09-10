<div align="center">

<img src="assets/hero.png" alt="Glide" width="640">

# Glide

**Free, lightweight trackpad gestures, physical edge sliders, TrackPoint mode, and global shortcuts for macOS.**

[![Release](https://img.shields.io/github/v/release/Vatsal057/Glide?label=release)](https://github.com/Vatsal057/Glide/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)](#installation)

[Download DMG](https://github.com/Vatsal057/Glide/releases/latest) · [Usage Manual](USAGE.md) · [Report an Issue](https://github.com/Vatsal057/Glide/issues)

</div>

---

Glide turns your Mac trackpad into a customizable control surface for window management, 2D app switching, physical edge sliders, and the first true TrackPoint pointing stick engine for macOS.

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

Glide provides deep trackpad and desktop control: advanced touchpad gestures, edge sliders, feature-rich app switching, revolutionary TrackPoint for macOS, and global macros in a lean, open-source utility that runs ideally at 0.0% CPU.

| Capability | Glide | BetterTouchTool | macOS Default |
| :--- | :--- | :--- | :--- |
| **License** | **Free & Open Source (MIT)** | Paid ($10 to $24+) | Built-in |
| **Idle Memory** | **~25 MB RAM** | 150–300+ MB RAM | Negligible |
| **Idle CPU / Battery** | **0.0% CPU (event-driven, zero idle drain)** | Ongoing background polling | None |
| **Physical Edge Sliders** | **Hardware rim sliders (volume, brightness, scrub)** | Requires custom scripting | None |
| **Window State Ladders** | **State-adaptive chaining (maximize → fullscreen)** | Manual multi-rule setup | None |
| **Reverse Action Gestures** | **Automatic opposite-direction undo** | Manual inverse rule setup | None |
| **2D Spatial App Switcher** | **Horizontal app flow + vertical window decks** | 1D switcher | ⌘Tab (apps only) |
| **TrackPoint Mode** | **Exclusive to Glide on Mac: pointer stick + 2-finger scroll** | None | None |
| **Global Shortcuts Engine** | **Hotkeys, menu items, key sequences, scripts** | Supported | Shortcuts app (limited) |
| **Configuration UI** | **Native SwiftUI with live animated previews** | Dense multi-pane menus | System Settings |
| **Telemetry & Privacy** | **100% offline, zero telemetry** | Proprietary closed-source | Apple diagnostics |

## Core Features

- **Multi-Finger Gestures:** 3, 4, and 5-finger swipes, clicks, force-clicks, and holds with configurable flick vs. glide speed classification.
- **Physical Rim Sliders:** Slide along the trackpad's physical border to adjust volume, brightness, keyboard backlight, or scrub the App Switcher.
- **TrackPoint (A First on macOS):** Brings ThinkPad-style pointing stick mechanics to the Mac trackpad. Rest or double-tap an anchor finger, then lean in any direction to steer the cursor with continuous, vector-based velocity across multi-monitor setups without lifting your hand. Place a second finger down for high-speed inertia scrolling.
- **State-Aware Ladders & Reciprocals:** Swipes adapt to current window state (maximize → fullscreen), and opposite gestures reverse actions automatically.
- **2D Spatial App Switcher:** Swipe horizontally across running applications and vertically through window decks with live thumbnails.
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

## Why I Built This

About five months ago, I got my first MacBook. The trackpad hardware was easily the best I had ever used, but macOS barely let me do anything with it. I couldn't snap windows, adjust volume with a swipe, or switch between open windows without memorizing shortcuts or lifting my hands from the pad. The traditional tool, BetterTouchTool, felt heavy—ongoing background CPU drain, battery hit, and a paid license for a kitchen-sink utility.

So I opened an editor and started building Glide with the help of AI.

Looking back through the commit history, what started as a simple weekend experiment turned into a five-month journey down the macOS low-level API rabbit hole:

- **The Early Days:** It began with basic 3-finger swipes. Quickly, edge cases piled up—pinch-to-zoom conflicts, accidental Mission Control triggers, and dropped click events. To solve this properly, I had to drop standard AppKit event handling and build a C-based bridge into Apple's private `MultitouchSupport` framework with per-gesture event suppression.
- **The App Switcher Obsession:** I wanted a visual 2D switcher where you swipe horizontally across apps and vertically through their window decks. Standard macOS Accessibility APIs were far too slow across multiple Spaces, causing noticeable lag. I spent weeks rewriting the engine to query window IDs directly from `WindowServer` (`GLDWCopyWindowIDsForProcess`) and remote AX tokens, tuning caching until window switching was instant.
- **TrackPoint Mode (A First on macOS):** Standard trackpads force you to swipe, lift, and swipe again just to traverse high-resolution multi-monitor setups. Windows and Linux ThinkPad users have long relied on the red pointing stick for continuous cursor velocity without repositioning fingers, but macOS has never had anything like it. I brought velocity-driven vector physics to Apple's glass trackpad: anchor a finger, push outward from the origin to accelerate the cursor continuously in any direction, and drop a second finger to instantly transition into high-speed directional scrolling.
- **Physical Rim Sliders:** I wanted to adjust volume and brightness without looking at the keyboard. The challenge was preventing accidental triggers during normal cursor navigation. The solution was strict touch-origin filtering: controls only engage if the contact begins directly on the outer 10mm hardware rim of the trackpad.

Five months of daily dogfooding turned Glide into the tool I wanted on day one: deep trackpad control, pure Swift, zero telemetry, and an event-driven engine that idles at 0.0% CPU.

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

