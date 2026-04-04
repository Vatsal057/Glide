<p align="center">
  <img src="assets/hero.png" alt="Glide" width="600"/>
</p>

<h1 align="center">Glide</h1>

<p align="center">
  <b>Powerful trackpad gestures for macOS.</b><br>
  Swipe with 2–5 fingers to control windows, apps, and your Mac — at any speed, with flawless palm rejection.
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
- [Trackpad Safe Zones (New!)](#trackpad-safe-zones-new)
- [Understanding Speed: Slow, Normal & Fast](#understanding-speed-slow-normal--fast)
- [Default Gestures](#default-gestures)
- [All Available Actions](#all-available-actions)
- [Reciprocal Gestures](#reciprocal-gestures)
- [Tuning & Customization](#tuning--customization)
- [Troubleshooting](#troubleshooting)
- [Building from Source](#building-from-source)

---

## Quick Start

1. **Build** — `bash build.sh`
2. **Launch** — `open build/Glide.app`
3. **Grant Access** — macOS will ask for Accessibility permission. Go to **System Settings → Privacy & Security → Accessibility** and enable Glide.
4. **Use it** — Place 3 fingers on the trackpad and swipe. That's it!

> **Tip:** Optionally move to Applications: `cp -r build/Glide.app /Applications/`

---

## How Gestures Work

Glide reads raw multitouch data from your trackpad. When you place multiple fingers and move them, the app:

1. **Detects finger count** (2, 3, 4, or 5 fingers)
2. **Filters edge touches** using our intelligent lifecycle blocker 
3. **Verifies it's a swipe** (not a pinch or zoom)
4. **Determines direction** from the angle of your finger movement
5. **Classifies speed** based on how fast your fingers are moving
6. **Fires the matching action**

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
    │    Glide Engine             │
    │                             │
    │  Fingers: 3                 │
    │  Direction: Right (→)       │
    │  Speed: Normal              │
    │  ─────────────────          │
    │  Match: "App Switcher Next" │
    └─────────────────────────────┘
```

---

## Trackpad Safe Zones (New!)

To provide a flawless experience, Glide now features a robust **Lifecycle Blocker** working alongside customizable **Trackpad Dead Zones**. 

This completely solves the "palm resting" problem! If any of your fingers or palms touch the outer margins of the trackpad, Glide registers that exact moment and freezes gesture recognition completely. 
- You can rest a thumb in the margin and navigate macOS normally with your other fingers without an accidental 3-finger click firing!
- Swipes starting entirely out of the margin and sliding into the safe-zone are properly registered.
- Adjustable sliders mapped beautifully to the Preferences UI allow you to determine exactly what the "Safe Area" of your trackpad is visually.

---

## Understanding Speed: Slow, Normal & Fast

Glide measures **how fast your fingers are actually moving** — not how long the gesture takes. This means speed detection feels natural and consistent.

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

### ⚪ Normal Gestures — "The Natural Swipe"

**Technique:** Just swipe. Don't think about speed at all.

- ✅ Move your fingers at a comfortable, natural pace  
- ✅ This is your default — most swipes will register as Normal  
- ✅ Not rushed, not deliberate — just... a swipe  

### 🔵 Slow Gestures — "The Glide"

**Technique:** Place your fingers and move them very slowly and deliberately, like you're sliding a precise control.

- ✅ Gentle, controlled movement — think of adjusting a dimmer switch  
- ✅ Fingers stay in contact with the trackpad the whole time  
- ✅ The movement should feel intentional and unhurried  
- ❌ Don't just hesitate before swiping — the app measures *movement speed*, not *pause duration*

### Pro Tips

1. **The start matters most.** Speed is sampled from the first 3 frames of motion. How you begin the gesture determines the classification — you can't change it mid-swipe.
2. **Normal is the fallback.** If you have a Fast or Slow rule but the gesture is classified as Normal, it'll match the Normal rule. If you only have a Normal rule for a direction, it fires regardless of speed.
3. **Click gestures ignore speed.** Tap-style gestures (all fingers tap down together) always fire as Normal.

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

Glide supports comprehensive commands mapped instantly without latency! Enjoy binding directions and clicks for **App Control**, **App Switching**, **Window Management**, **Window Snapping**, **Fullscreen interactions**, and **System overrides** such as Screenshots and Screen Locking! 

Check the Preferences UI in the macOS Menu bar to mix and match customized workflows.

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

Open Glide Preferences (click the menu bar icon → Preferences) to access all settings.

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
2. Try removing Glide from the list and re-adding it
3. Rebuild: `bash build.sh && open build/Glide.app`

### Gestures stop working after sleep/wake
Glide has built-in recovery. If gestures stop within 5 seconds of waking, they should auto-recover. If not:
1. Quit Glide from the menu bar
2. Relaunch it

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
git clone https://github.com/Vatsal057/Glide.git
cd Glide
bash build.sh
open build/Glide.app
```

### Install permanently
```bash
cp -r build/Glide.app /Applications/
```

### Launch at login
Enable "Launch at Login" in **Preferences → General**.

---

<p align="center">
  <sub>Glide uses Apple's private MultitouchSupport framework for raw trackpad access.<br>
  Speed detection inspired by <a href="https://github.com/taj-ny/InputActions">InputActions</a>.</sub>
</p>
