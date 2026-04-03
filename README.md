<p align="center">
  <img src="assets/hero.png" alt="GestureFlow" width="600"/>
</p>

<h1 align="center">GestureFlow</h1>

<p align="center">
  <b>Powerful trackpad gestures for macOS.</b><br>
  Swipe with 2–5 fingers to control windows, apps, and your Mac — at any speed.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square" alt="macOS 13+"/>
  <img src="https://img.shields.io/badge/Swift-6.3-orange?style=flat-square" alt="Swift 6.3"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"/>
</p>

---

## Table of Contents

- [Quick Start](#quick-start)
- [How Gestures Work](#how-gestures-work)
- [Understanding Speed: Slow, Normal & Fast](#understanding-speed-slow-normal--fast)
- [Mastering Speed Gestures (Without the Frustration)](#mastering-speed-gestures-without-the-frustration)
- [Default Gestures](#default-gestures)
- [All Available Actions](#all-available-actions)
- [Reciprocal Gestures](#reciprocal-gestures)
- [Tuning & Customization](#tuning--customization)
- [Troubleshooting](#troubleshooting)
- [Building from Source](#building-from-source)

---

## Quick Start

1. **Build** — `bash build.sh`
2. **Launch** — `open build/GestureFlow.app`
3. **Grant Access** — macOS will ask for Accessibility permission. Go to **System Settings → Privacy & Security → Accessibility** and enable GestureFlow.
4. **Use it** — Place 3 fingers on the trackpad and swipe. That's it.

> **Tip:** Optionally move to Applications: `cp -r build/GestureFlow.app /Applications/`

---

## How Gestures Work

GestureFlow reads raw multitouch data from your trackpad. When you place multiple fingers and move them, the app:

1. **Detects finger count** (2, 3, 4, or 5 fingers)
2. **Verifies it's a swipe** (not a pinch or zoom)
3. **Determines direction** from the angle of your finger movement
4. **Classifies speed** based on how fast your fingers are moving
5. **Fires the matching action**

```
    ┌─────────────────────────────┐
    │         Your Trackpad       │
    │                             │
    │    ●  ●  ●  ──────►        │  ← 3 fingers swiping right
    │                             │
    └─────────────────────────────┘
                  │
                  ▼
    ┌─────────────────────────────┐
    │    GestureFlow Engine       │
    │                             │
    │  Fingers: 3                 │
    │  Direction: Right (→)       │
    │  Speed: Normal              │
    │  ─────────────────          │
    │  Match: "App Switcher Next" │
    └─────────────────────────────┘
```

---

## Understanding Speed: Slow, Normal & Fast

GestureFlow measures **how fast your fingers are actually moving** — not how long the gesture takes. This means speed detection feels natural and consistent.

### The Three Speeds

| Speed | How to perform | What it feels like | Color in Preferences |
|-------|---------------|-------------------|---------------------|
| 🔵 **Slow** | Move fingers deliberately and gently | Like slowly dragging something | Blue |
| ⚪ **Normal** | Just swipe naturally, don't think about it | Your everyday comfortable swipe | Gray |
| 🟠 **Fast** | Quick flick of the fingers | A sharp, snappy motion | Orange |

### How Speed Is Measured

Speed is determined by **velocity** — the average distance your fingers move per trackpad frame:

```
                    Slow          Normal           Fast
                  ◄──────►    ◄────────────►    ◄──────►
    Velocity:     0          0.003        0.008         ∞
                  ├──────────┤────────────┤────────────►
                  │  SLOW    │   NORMAL   │    FAST
                  │ ≤ 0.003  │   between  │  ≥ 0.008
```

The engine samples your finger movement over 3 frames and averages it. This smooths out any jitter and gives a reliable reading.

---

## Mastering Speed Gestures (Without the Frustration)

This is the most important section. Here's how to consistently trigger each speed:

### 🟠 Fast Gestures — "The Flick"

**Technique:** A quick, confident flick. Think of it like flicking a crumb off the table.

- ✅ Place fingers, flick sharply, lift immediately  
- ✅ Short distance, high speed  
- ✅ Think "snappy" — the motion should take less than a quarter second  
- ❌ Don't drag slowly and then speed up at the end — the app samples early  

**Practice:** Place 3 fingers and quickly flick right. You'll feel a haptic tap when the action fires. If you're getting Normal instead of Fast, make your initial movement more explosive.

### ⚪ Normal Gestures — "The Natural Swipe"

**Technique:** Just swipe. Don't think about speed at all.

- ✅ Move your fingers at a comfortable, natural pace  
- ✅ This is your default — most swipes will register as Normal  
- ✅ Not rushed, not deliberate — just... a swipe  

**Practice:** This should be effortless. If you're accidentally triggering Fast or Slow, you're probably overthinking it. Relax your hand and swipe normally.

### 🔵 Slow Gestures — "The Glide"

**Technique:** Place your fingers and move them very slowly and deliberately, like you're sliding a precise control.

- ✅ Gentle, controlled movement — think of adjusting a dimmer switch  
- ✅ Fingers stay in contact with the trackpad the whole time  
- ✅ The movement should feel intentional and unhurried  
- ❌ Don't just hesitate before swiping — the app measures *movement speed*, not *pause duration*

**Practice:** Place 3 fingers and very slowly glide them upward over 1-2 seconds. This should feel dramatically different from a normal swipe.

### Quick Reference Card

```
╔═══════════════════════════════════════════════════════════════╗
║                    SPEED CHEAT SHEET                         ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  🟠 FAST    →  Quick flick, like brushing crumbs away        ║
║  ⚪ NORMAL  →  Just swipe naturally, don't think about it    ║
║  🔵 SLOW    →  Gentle glide, like a dimmer switch            ║
║                                                               ║
║  KEY INSIGHT: Speed is measured from the FIRST few frames     ║
║  of movement. How you START the gesture matters most.         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

### Pro Tips

1. **The start matters most.** Speed is sampled from the first 3 frames of motion. How you begin the gesture determines the classification — you can't change it mid-swipe.

2. **Same direction, three actions.** You can bind Slow/Normal/Fast swipes to different actions. For example:
   - 3-finger swipe right (Normal) → Next App
   - 3-finger swipe right (Fast) → Close Window
   - 3-finger swipe right (Slow) → Snap Right

3. **Normal is the fallback.** If you have a Fast or Slow rule but the gesture is classified as Normal, it'll match the Normal rule. If you only have a Normal rule for a direction, it fires regardless of speed.

4. **Click gestures ignore speed.** Tap-style gestures (all fingers tap down together) always fire as Normal.

5. **Enable debug logging** (in Preferences → General) to see exactly what speed each gesture was classified as. The console will show:
   ```
   [Engine] Swipe Right — 3 fingers, Fast (avgVel=0.012, angle=5.3°) → Close Window
   ```

---

## Default Gestures

These are the out-of-the-box gestures. All are set to Normal speed.

### 3 Fingers

| Gesture | Action |
|---------|--------|
| Swipe → | Next App (App Switcher) |
| Swipe ← | Previous App (App Switcher) |
| Swipe ↑ | Mission Control |
| Swipe ↓ | Minimize All Apps |
| Click | Quit App Under Cursor |

### 4 Fingers

| Gesture | Action |
|---------|--------|
| Swipe ↑ | Maximize Window |
| Swipe ↓ | Restore/Un-maximize |
| Swipe ← | Snap: Left Half |
| Swipe → | Snap: Right Half |

### 5 Fingers

| Gesture | Action |
|---------|--------|
| Swipe ↑ | Enter Fullscreen |
| Swipe ↓ | Exit Fullscreen |
| Click | Lock Screen |

---

## All Available Actions

### App Control
| Action | Description |
|--------|-------------|
| Quit App Under Cursor | Gracefully quits the app under your cursor |
| Force Quit App Under Cursor | Force-kills the app |
| Quit Frontmost App | Quits whichever app is currently focused |
| Hide App Under Cursor | Hides app (⌘H) |
| Hide Other Apps | Hides all apps except current (⌘⌥H) |
| Open App… | Launches a specific application |

### App Switching
| Action | Description |
|--------|-------------|
| Next App (App Switcher) | Opens ⌘Tab and scrolls right as you keep swiping |
| Previous App (App Switcher) | Opens ⌘Tab and scrolls left |
| Activate Next App | Instantly switches to next app (no UI) |
| Activate Previous App | Instantly switches to previous app |

### Window Management
| Action | Description |
|--------|-------------|
| Maximize Window | Zooms window to fill the screen |
| Restore/Un-maximize | Returns window to its previous size |
| Minimize Window | Minimizes current window to Dock |
| Minimize All Apps | Minimizes all visible windows |
| Restore Minimized Apps | Un-minimizes everything |
| Close Window | Closes current window (⌘W) |
| Cycle Windows | Cycles between windows of current app (⌘`) |

### Window Snapping
| Action | Description |
|--------|-------------|
| Snap: Left/Right Half | Fills left or right half of screen |
| Snap: Top-Left/Right | Fills a quarter of the screen |
| Snap: Bottom-Left/Right | Fills a quarter of the screen |
| Center Window | Centers window on screen |
| Move to Next Display | Moves window to the next monitor |

### Fullscreen
| Action | Description |
|--------|-------------|
| Enter Fullscreen | Makes window fullscreen |
| Exit Fullscreen | Leaves fullscreen |
| Toggle Fullscreen | Switches between fullscreen and windowed |

### System
| Action | Description |
|--------|-------------|
| Mission Control | Opens Mission Control (F3) |
| App Exposé | Shows all windows of current app |
| Show Desktop | Reveals desktop (F11) |
| Launchpad | Opens Launchpad |
| Spotlight | Opens Spotlight search |
| Notification Center | Opens Notification Center |
| Lock Screen | Locks your Mac |
| Sleep | Puts Mac to sleep |
| Screenshot (Area) | Starts area screenshot (⌘⇧4) |
| Screenshot (Full) | Captures full screen (⌘⇧3) |

---

## Reciprocal Gestures

Many actions have a natural "undo." When reciprocal gestures are enabled (the default):

- **Maximize → Restore:** Swipe up to maximize, immediately swipe down to restore
- **Enter Fullscreen → Exit:** 5-finger swipe up, then immediately 5-finger swipe down  
- **Minimize All → Restore All:** Swipe down to minimize, swipe up to restore
- **Mission Control → Dismiss:** Swipe up to open, swipe down to close

Reciprocals only work when you perform the reverse gesture **immediately after** the original. If you do anything else in between (switch apps, click, etc.), the reciprocal token expires.

---

## Tuning & Customization

Open GestureFlow Preferences (click the menu bar icon → Preferences) to access all settings.

### Speed Classification

| Parameter | Default | What it does |
|-----------|---------|-------------|
| Fast Velocity Threshold | 0.008 | Minimum avg velocity for "Fast". **Raise** if fast gestures trigger too easily. **Lower** if fast gestures never trigger. |
| Slow Velocity Threshold | 0.003 | Maximum avg velocity for "Slow". **Lower** if slow gestures trigger too easily. **Raise** if you can't trigger slow gestures. |
| Speed Sample Frames | 3 | How many frames to average. Higher = more stable but slightly delayed. |

### Direction Detection

| Parameter | Default | What it does |
|-----------|---------|-------------|
| Angle Tolerance | 45° | Width of each direction wedge. 45° = no dead zones. Lower values create diagonal dead zones where the gesture waits for a clearer direction. |

### Recognition

| Parameter | Default | What it does |
|-----------|---------|-------------|
| Activation Threshold | 0.018 | Distance fingers must travel before a swipe fires. Lower = more sensitive. |
| Candidate Frames | 3 | Frames collected before confirming it's a swipe. Lower = faster, but more false positives from pinch. |

### Recommended Tuning Presets

**"I keep accidentally triggering Fast when I want Normal"**
> Raise `Fast Velocity Threshold` from 0.008 to 0.012

**"I can never trigger Slow, it always registers as Normal"**  
> Raise `Slow Velocity Threshold` from 0.003 to 0.005

**"I don't use speed gestures, I just want everything to work at any speed"**
> Set all your gesture rules to "Any Speed" instead of Normal/Fast/Slow

**"Gestures feel laggy / delayed"**
> Lower `Candidate Frames` to 2, lower `Activation Threshold` to 0.012

**"I get false swipes during pinch-to-zoom"**
> Raise `Candidate Frames` to 4, lower `Pinch Spread Threshold`

---

## Troubleshooting

### Gestures don't work at all
1. Check that Accessibility permission is granted in **System Settings → Privacy & Security → Accessibility**
2. Try removing GestureFlow from the list and re-adding it
3. Rebuild: `bash build.sh && open build/GestureFlow.app`

### Gestures stop working after sleep/wake
GestureFlow has built-in recovery. If gestures stop within 5 seconds of waking, they should auto-recover. If not:
1. Quit GestureFlow from the menu bar
2. Relaunch it

### Wrong speed is detected
1. Enable debug logging in **Preferences → General**
2. Open Console.app or Terminal, perform gestures, and look for lines like:
   ```
   [Engine] Swipe Right — 3 fingers, Fast (avgVel=0.012, angle=5.3°) → ...
   ```
3. The `avgVel` number tells you exactly how fast your gesture was. Compare it to your thresholds.

### Direction seems wrong
1. Enable debug logging and check the `angle=X°` value
2. Right ≈ 0°/360°, Up ≈ 90°, Left ≈ 180°, Down ≈ 270°
3. If your angle is between directions (e.g., 42° is between Right and Up), try swiping more precisely in one direction

---

## Building from Source

### Requirements
- macOS 13+  
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9+

### Build & Run
```bash
git clone <repo-url>
cd GestureFlow_fixed
bash build.sh
open build/GestureFlow.app
```

### Install permanently
```bash
cp -r build/GestureFlow.app /Applications/
```

### Launch at login
Enable "Launch at Login" in **Preferences → General**.

---

<p align="center">
  <sub>GestureFlow uses Apple's private MultitouchSupport framework for raw trackpad access.<br>
  Speed detection inspired by <a href="https://github.com/taj-ny/InputActions">InputActions</a>.</sub>
</p>
