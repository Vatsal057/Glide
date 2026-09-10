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

Glide turns your Mac trackpad into a programmable control surface for window management, 2D app switching, and system adjustments. Snap windows, browse running applications and window decks, trigger multi-step keyboard macros, and slide your finger along the physical trackpad edges to adjust volume and brightness.

Written in pure Swift using low-level MultitouchSupport and WindowServer APIs, Glide idles at 0.0% CPU, uses ~25 MB of memory, and maintains zero background battery tax.

## Why Glide?

BetterTouchTool (BTT) has long been the standard choice for custom Mac gestures, but it has grown into a heavy utility suite bundled with notch bars, stream decks, web servers, and clipboard managers. That extra baggage brings background battery drain, 150 to 300+ MB of RAM usage, a paid license, and a complex interface.

Glide focuses purely on gestures, edge sliders, and shortcuts:

| Capability | Glide | BetterTouchTool | macOS Default |
| :--- | :--- | :--- | :--- |
| **License & Price** | **100% Free & Open Source (MIT)** | Paid ($10 to $24+) | Built-in |
| **Idle Resource Usage** | **~25 MB RAM, 0.0% CPU** | 150 - 300+ MB RAM | Negligible |
| **Battery Impact** | **Zero idle drain (event-driven)** | Ongoing background drain | None |
| **Reverse Action Gestures** | **Automatic opposite-direction undo (maximize ↔ restore)** | Manual configuration | None |
| **Physical Edge Sliders** | **Hardware rim detection for volume & brightness** | Complex custom scripting | None |
| **2D Spatial Switcher** | **Horizontal apps + vertical window decks** | Standard 1D switcher | ⌘Tab (apps only) |
| **Speed-Aware Gestures** | **Dual actions per direction (glide vs flick)** | None | None |
| **Force-Click Corner Zones** | **4 independent pressure triggers in corners** | None | None |
| **Global Shortcuts Engine** | **Hotkeys, menu items, key sequences, shell, AppleScript** | Supported | Limited Shortcuts app |
| **Configuration UI** | **Clean native SwiftUI with live animated previews** | Dense multi-pane menus | Basic system panels |
| **Telemetry & Privacy** | **Offline execution, zero tracking** | Proprietary closed-source | Apple diagnostics |

## Core Features

### Advanced Trackpad Gestures
- **Multi-Finger Inputs:** Map swipes, clicks, deep force-clicks, and tap-and-hold with 3, 4, or 5 fingers.
- **Reverse Action Gestures:** Opposite swipes naturally undo actions. Swipe up to maximize; swipe down immediately restores the window to its exact prior size and position. Glide pairs reciprocal actions automatically (maximize ↔ restore, volume up ↔ down, next ↔ previous track) and supports custom reverse triggers.
- **Speed-Aware Triggers:** The same swipe direction can trigger two different actions based on initial hand velocity. A slow swipe right snaps the window to the right half; a quick flick right throws it to an external monitor.
- **Force-Click Corner Zones:** The four corners of a Force Touch trackpad function as independent pressure buttons (e.g. top-left corner deep-press for full screenshot, top-right for area selection).
- **Gesture Ladders & State Filters:** Swipes adapt based on frontmost window state. Swipe up on a normal window to maximize; swipe up again on that maximized window to enter native fullscreen.
- **Smart Conditions:** Scope gestures to specific applications (Safari, Spotify, Terminal) or require modifier keys (⌘, ⇧, ⌥, ⌃).

### Physical Trackpad Edge Controls
Slide a single finger along the physical outer border of your trackpad for direct hardware control:
- **Right Edge:** Slide up/down to adjust system volume.
- **Left Edge:** Slide up/down to adjust display brightness.
- **Top & Bottom Edges (Configurable):** Map to keyboard backlight, mic gain, Night Shift warmth, or app scrub.
- **Zero Overhead:** Triggers native macOS OSD bezels with 0.0% CPU usage and tactile Taptic Engine ticks.
- **Accidental Trigger Immunity:** Only touches originating directly on the physical outer rim register. Cursor movements that drift into an edge from the center are ignored.

### Global Keyboard Shortcuts & Automations
Every action supported by gestures can also be triggered via system-wide hotkeys:
- **Window Snapping & Targeting:** Snap, center, or maximize windows. Target the focused window or act directly on background windows under your cursor.
- **Direct Menu Items:** Execute deep menu commands (such as `Safari > File > New Private Window`) directly from a hotkey.
- **Keystroke Sequences:** Record multi-step key sequences with precise press, hold, and release timing.
- **Shortcuts, Shell & AppleScript:** Trigger macOS Shortcuts by name, run shell scripts, or fire AppleScripts. Shared configurations display a security review before running imported scripts.

### Visual App Switcher (2D Spatial Navigation)
Standard macOS ⌘Tab switches between applications. Glide adds 2D spatial navigation to target individual windows of the active app:
- **Horizontal Swipe (Left / Right):** Scrub through all running applications.
- **Vertical Swipe (Up / Down):** Scrub through the window deck of the selected app to jump directly to any document or browser window.
- **Live Window Thumbnails:** See live visual previews of every window, or switch to lightweight app icons. Release to focus; lift outside to cancel.

### TrackPoint Mode
Move the cursor continuously across multi-monitor setups and ultra-wide displays:
- Maps finger displacement to **cursor velocity**.
- Double-tap and hold or rest a finger in a corner: lean slightly to glide the cursor continuously across multiple displays.
- Place a second finger down to engage high-speed scrolling.

### Live Animated Previews & Calibration
- **Live Motion Previews:** Settings displays real-time vector animations for every gesture, showing finger positions, directions, and speed tiers.
- **Precision Calibration:** Presets for Relaxed, Balanced, and Precise profiles, diagonal dead zones, and palm rejection edge margins with a live touch visualizer.

## Default Gestures

Glide works immediately after launch with practical default settings:

| Trigger | Default Action | Reverse Action |
| :--- | :--- | :--- |
| **Slide finger along right edge** | System Volume Up | System Volume Down |
| **Slide finger along left edge** | Display Brightness Up | Display Brightness Down |
| **Swipe up with 3 fingers** | Mission Control | Show Desktop |
| **Swipe down with 3 fingers** | Minimize All Windows | Restore Minimized Windows |
| **Swipe left / right with 3 fingers** | Visual App Switcher (2D navigation) | App Switcher reverse scrub |
| **Swipe up with 4 fingers** | Maximize Active Window | Restore Window Size |
| **Swipe up again on maximized window** | Enter Native Fullscreen | Exit Native Fullscreen |
| **Swipe left / right with 4 fingers** | Snap Window Left Half | Snap Window Right Half |
| **Force-click top-left corner** | Screenshot (Full screen to clipboard) | None |
| **Force-click top-right corner** | Screenshot (Area selection) | None |

Every gesture, edge slider, and shortcut can be customized in **Preferences** (`⌘,`).

## Installation

### Method 1: Direct Download (Recommended)

1. Download the latest **Glide-vX.Y.Z.dmg** from the [Releases page](https://github.com/Vatsal057/Glide/releases/latest).
2. Open the DMG and drag **Glide** into your **Applications** folder.
3. Open Glide from Applications. Because Glide is an independent open-source project distributed outside the Mac App Store, macOS Gatekeeper displays a verification prompt on first launch:
   - **Right-click** (or Control-click) Glide in Applications and select **Open**, then click **Open** in the confirmation dialog.
   - On **macOS 15 (Sequoia)**, if the Open option is not shown: open Glide once, go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
   - If macOS displays *"Glide is damaged and can't be opened"*, clear the Gatekeeper quarantine attribute in Terminal:
     ```sh
     xattr -cr /Applications/Glide.app
     ```
4. Grant **Accessibility** permissions when prompted (**System Settings → Privacy & Security → Accessibility**). Glide requires this to read trackpad touch coordinates and manage window positions.

### Method 2: Build from Source

Requirements: macOS 13 or later and Xcode Command Line Tools.

```sh
git clone https://github.com/Vatsal057/Glide.git
cd Glide
./build.sh
```

To create a release DMG:
```sh
./build.sh --dmg
```

### Automatic In-App Updates

Glide includes built-in release checking. Open **Preferences → General** and click **Check for Updates**, or select **Check for Updates…** from the menu bar icon. When a new release is available on GitHub, Glide verifies the checksum, installs the update, and relaunches automatically.

## Documentation

Detailed documentation is available in the `docs/` folder:

- [Usage Manual Overview](USAGE.md): Complete guide to all features and settings.
- [Core Concepts](docs/01-core-concepts.md): Fingers, swipe speeds, clicks, and conflict resolution.
- [Smart Filters & Conditions](docs/02-filters-and-conditions.md): Modifiers, app filters, and window state ladders.
- [Action Catalog](docs/03-actions.md): Complete reference of all window, app, media, and system actions.
- [Global Keyboard Shortcuts](docs/04-keyboard-shortcuts.md): Hotkey binding and macro execution.
- [App Switcher Guide](docs/05-app-switcher.md): 2D spatial navigation and window deck switching.
- [TrackPoint Guide](docs/06-trackpoint.md): ThinkPad pointing stick calibration and modes.
- [Tuning & Calibration](docs/07-tuning.md): Sensitivity, diagonal strictness, and palm rejection.
- [General Preferences](docs/08-general-preferences.md): Window targeting, haptics, and system gesture conflicts.
- [Configuration File](docs/09-configuration-file.md): Editing, exporting, and importing `config.yaml`.
- [Permissions](docs/10-permissions.md): Why Accessibility and Screen Recording permissions are used.
- [Troubleshooting](docs/11-troubleshooting.md): Common questions and resolution steps.
- [Trackpad Edge Controls](docs/12-edge-controls.md): Edge slider architecture and sensitivity tuning.

## Contributing

Bug reports, feature requests, and pull requests are welcome. Please check [open issues](https://github.com/Vatsal057/Glide/issues) before opening a new issue.

## License

Glide is open source under the [MIT License](LICENSE).
