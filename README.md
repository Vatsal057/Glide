![Glide](assets/hero.png)

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-007AFF?style=flat-square&logo=apple&logoColor=white)](https://github.com/Vatsal057/Glide/releases/latest)
[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![arch: Universal Binary](https://img.shields.io/badge/arch-Universal%20Binary-34C759?style=flat-square)](https://github.com/Vatsal057/Glide/releases/latest)
[![Release](https://img.shields.io/github/v/release/Vatsal057/Glide?style=flat-square&label=release&color=0A84FF)](https://github.com/Vatsal057/Glide/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

---

macOS gives you four trackpad gestures and no way to change them. I made an app to fix just that. 

It reads raw multitouch input and maps any combination of finger count, direction, and speed to whatever you want - window snapping, app switching, screenshots, locking your screen, or launching apps. Free, open-source. no need of paying for additional features on your trackpad.

---

## Install

**[⬇ Download Glide v1.0.0](https://github.com/Vatsal057/Glide/releases/latest)** - Universal Binary (Apple Silicon + Intel)

1. Download `Glide.app.zip`, unzip it
2. Move `Glide.app` to `/Applications/`
3. Launch it and grant Accessibility permission when macOS asks

Or build from source if you're into that:

```bash
git clone https://github.com/Vatsal057/Glide.git
cd Glide
bash build.sh
open build/Glide.app
```

---

## What it does

### Speed-aware gestures

The same swipe can do three different things depending on how fast you move. A slow deliberate drag, a normal swipe, and a quick flick are all distinct - no extra fingers needed.

```
3 fingers →  slow    ──►  Snap: Right Half
3 fingers →  normal  ──►  App Switcher: Next
3 fingers →  fast    ──►  Move to Next Display
```

Speed is classified by your *starting* velocity (first three frames), so it's consistent regardless of how you finish the gesture. You can tune the thresholds in Preferences, or just set a rule to **Any Speed** if you'd rather not think about it.

### Supported actions

Window stuff: maximize, restore, minimize, center, snap to halves and quadrants, move to next display, close, cycle windows.

App stuff: switch apps (with continuous scroll through the switcher), quit, force quit, hide, launch a specific app.

System stuff: Mission Control, App Exposé, Spotlight, Launchpad, Notification Center, Show Desktop, screenshot (area or full), lock screen, sleep.

That's roughly 40 actions. Assign any of them to any gesture slot.

### App-specific rules

Every rule can be filtered to a specific app. Same swipe, different behavior depending on what's frontmost. Global rules apply everywhere else as fallback.

### Recoprocal actions (Undo actions)

After a reversible action, swiping back does the inverse. Snap right then swipe left brings the window back to exactly where it was. Works for maximize/restore, fullscreen, minimize-all, and a few others. The undo token expires the moment you do anything else, so it won't randomly fire.

### Palm rejection

Touches that start in the edge margins are ignored for the entire touch session. You can rest your thumb in the corner without triggering anything. Margins are configurable per-side with a live trackpad preview in Preferences.

---

## Preferences

Click the hand icon in the menu bar → Preferences.

**Gestures tab** - your rules. Each rule is `fingers + direction + speed → action`. Add with `+`, drag to reorder. The available combinations are 2/3/4/5 fingers × 5 directions × 3 speeds, so you have plenty of slots to fill (or not).

**Tuning tab** - the physics: activation threshold, candidate frame count, velocity thresholds for fast/slow, pinch sensitivity, and the edge margin sliders with a live map.

**General tab** - haptic feedback, window targeting mode (focused window vs. cursor), launch at login, edge margin config. 

---

## Internals

Eight Swift files, ~190KB, zero dependencies. Builds with `swiftc` directly. no Xcode project.

- **MultitouchBridge.swift** - loads Apple's private `MultitouchSupport.framework` at runtime via `dlopen`, registers a C callback for raw touch events, handles retry on wake (the device list is sometimes empty right after the trackpad reinitializes)
- **GestureEngine.swift** - five-phase state machine: `idle → candidate → lockedSwipe → fired → idle`. Candidate phase checks velocity, finger coherence, and spread delta to separate swipes from pinches before committing
- **ActionExecutor.swift** - dispatches actions through Accessibility API (window frames), CGEvent (keyboard simulation), NSWorkspace (app control), and a few private notification names for things like Notification Center
- **Settings.swift** - all enums and structs, JSON persistence via UserDefaults, schema migration, bounds clamping on tuning values
- **PreferencesUI.swift** - SwiftUI panel with NavigationSplitView; the trackpad visualizer in Tuning is drawn with Canvas and updates from engine callbacks rather than a timer
- **AppDelegate.swift** - menu bar, permission checking with polling fallback, sleep/wake observers, and a cascade restart at +0/2/5/10s after wake (different Macs reinitialize the trackpad at different speeds, unfortunately)

---

## Build requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9+ (6.3 recommended)

`bash build.sh` compiles arm64 and x86_64 and merges them with `lipo`. Takes under 30 seconds.

---

## Troubleshooting

**Nothing happens when I swipe**
Check System Settings → Privacy & Security → Accessibility. Glide needs to be in the list with its toggle on. If it's already there and still broken, remove it and re-add it - macOS sometimes caches stale permission state and removing it is the only fix.

**Gestures stop working after sleep**
Glide schedules restarts at 0, 2, 5, and 10 seconds after wake. If it's still broken after ~15 seconds, quit from the menu bar and relaunch.

**Fast swipes always register as Normal**
Lower the Fast Velocity Threshold in Preferences → Tuning. If you want to see the raw numbers, enable debug logging in General and watch Console - Glide prints velocity on every gesture.

**Gestures fire when I rest my palm**
Increase the edge margin sliders in Tuning. Start with all four at 0.10 and adjust from there. The live preview updates as you drag.

---

## Contributing

The codebase is meant to stay small. To add a new action: add a case to `GestureAction` in `Settings.swift`, handle it in `ActionExecutor.execute()`, and optionally add an inverse in `GestureAction.inverseAction`. That's it.

For anything touching `GestureEngine`, turn on debug logging first - every phase transition and velocity sample is printed to stdout.

PRs welcome. Keep dependencies at zero.

---

<p align="center">
  <sub>MIT licensed · Uses Apple's private <code>MultitouchSupport</code> framework for raw trackpad access · Velocity detection inspired by <a href="https://github.com/taj-ny/InputActions">InputActions</a></sub>
</p>
