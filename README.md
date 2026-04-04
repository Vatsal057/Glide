<p align="center">
  <img src="assets/hero.png" alt="Glide" width="620"/>
</p>

<br>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-007AFF?style=flat-square&logo=apple&logoColor=white"/>
  &nbsp;
  <img src="https://img.shields.io/badge/Swift-6.3-F05138?style=flat-square&logo=swift&logoColor=white"/>
  &nbsp;
  <img src="https://img.shields.io/badge/arch-Universal%20Binary-34C759?style=flat-square"/>
  &nbsp;
  <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"/>
</p>

<br>

---

Your Mac's trackpad is extraordinary hardware running mediocre software.

The system gives you four fixed gestures you can't change. Third-party apps either charge a subscription, pull in giant dependencies, or randomly fire when your palm grazes the edge. You end up adjusting your grip just to avoid a misfiring gesture — on *your own laptop*.

**Glide fixes this.** It's a free, open-source macOS utility that reads raw trackpad input and maps every combination of finger count, direction, and *speed* to whatever action you want — snapping windows, switching apps, locking your screen, taking screenshots, or anything else macOS can do. It lives in your menu bar, uses no CPU when idle, and gets out of your way.

One `bash build.sh` and it's running. No Xcode. No package manager. No account required.

---

<br>

## Getting Started

```bash
git clone https://github.com/Vatsal057/Glide.git
cd Glide
bash build.sh
open build/Glide.app
```

Grant the Accessibility permission when macOS asks (Glide needs it to move windows and simulate keys), and you're done. Your trackpad is already smarter.

**Want it in `/Applications` and at login?**

```bash
cp -r build/Glide.app /Applications/
```

Then open **Preferences → General** and flip on **Launch at Login**. That's the full installation.

---

<br>

## What Glide Can Do

Here's the complete catalog of things you can bind to a gesture. Every single one fires instantly.

### Window Management
Move windows however you want without touching the mouse.

| Action | What it does |
|--------|-------------|
| Maximize Window | Expands the frontmost window to fill the screen |
| Restore Window | Snaps it back to where it was before you maximized |
| Minimize Window | Sends the window to the Dock |
| Minimize All Apps | Hides every visible window at once |
| Restore Minimized Apps | Brings them all back |
| Close Window | Same as ⌘W |
| Center Window | Drops the window in the middle of your display |
| Move to Next Display | Throws the window to your other monitor |
| Cycle Windows | ⌘\` — cycles through open windows of the current app |

### Window Snapping
Snap to six positions without any third-party snap tool.

| Action | Position |
|--------|----------|
| Snap: Left Half | Left 50% |
| Snap: Right Half | Right 50% |
| Snap: Top-Left | Top-left quadrant |
| Snap: Top-Right | Top-right quadrant |
| Snap: Bottom-Left | Bottom-left quadrant |
| Snap: Bottom-Right | Bottom-right quadrant |

### Fullscreen

| Action | What it does |
|--------|-------------|
| Enter Fullscreen | True macOS fullscreen (not just maximized) |
| Exit Fullscreen | Drops back out |
| Toggle Fullscreen | Switches between fullscreen and normal |

### App Switching

| Action | What it does |
|--------|-------------|
| Next App (App Switcher) | Opens ⌘Tab and steps forward — hold your swipe to keep scrolling |
| Previous App (App Switcher) | Steps backward through the switcher |
| Activate Next App | Directly focuses the next app in the Dock order |
| Activate Previous App | Directly focuses the previous app |

### App Control

| Action | What it does |
|--------|-------------|
| Quit App Under Cursor | Quits whichever app your cursor is over |
| Force Quit App Under Cursor | Hard-kills it |
| Quit Frontmost App | Quits whatever's active |
| Hide App Under Cursor | ⌘H for the app under your cursor |
| Hide Other Apps | Hides everything except the active app |
| Open App… | Launches any app you pick — assign one per rule |

### System Actions

| Action | What it does |
|--------|-------------|
| Mission Control | Full overview of all windows and Spaces |
| App Exposé | Scatters all windows of the current app |
| Show Desktop | Clears everything to the Desktop |
| Launchpad | Opens the Launchpad overlay |
| Spotlight | ⌘Space |
| Notification Center | Opens the right-side notification panel |
| Screenshot (Area) | ⌘⇧4 — drag to select |
| Screenshot (Full) | ⌘⇧3 — captures everything |
| Lock Screen | Locks immediately |
| Sleep | Sleeps the Mac |

---

<br>

## The Part That Makes It Different

### One gesture. Three possible actions.

Most gesture tools treat every swipe as identical regardless of how fast you move. Glide doesn't.

The same gesture — three fingers swiping right, say — can do something different depending on whether you *flick*, *swipe*, or *glide*. That's three behaviors from one hand movement, no extra fingers required.

```
3 fingers →   slow    ──►  Snap: Right Half
3 fingers →   normal  ──►  App Switcher: Next
3 fingers →   fast    ──►  Move to Next Display
```

Speed is measured by averaging centroid velocity across the first three frames of movement. Your *starting* speed locks in the classification — it doesn't matter how fast you finish. This makes it consistent and deliberate.

| Speed | How it feels | Velocity |
|-------|-------------|----------|
| 🔵 Slow | Deliberate. Like nudging a slider. | ≤ 0.003 |
| ⚪ Normal | Just a swipe. Don't think about it. | 0.003 – 0.008 |
| 🟠 Fast | A flick. Over in a quarter second. | ≥ 0.008 |

Speed thresholds are adjustable in Preferences if the defaults don't match your touch style. And if you just want reliable gestures without speed detection, set any rule to **Any Speed** — it matches all three bands.

---

### Palm rejection that actually works

Touch the outer margin of the trackpad and gesture recognition freezes completely for that touch session. Not slowed down — frozen.

This means you can rest your thumb in the corner, type normally, and use the trackpad with other fingers without a single accidental gesture firing. Margins are configurable per-side (left, right, top, bottom) with live sliders in Preferences. A trackpad visualizer shows you exactly which area is "safe" as you adjust.

Swipes that start inside the safe zone and drift toward the edge are tracked correctly. Only contact that *originates* in the margin is blocked. The moment an edge touch is registered, it latches onto the entire touch session and nothing fires until all fingers lift.

---

### Undo your last gesture

Perform an action, then immediately reverse it with the opposite swipe.

- Maximize a window → swipe back to restore it to its exact original size
- Enter fullscreen → swipe back to exit
- Snap left → swipe back to restore
- Open Mission Control → swipe back to dismiss it
- Minimize everything → swipe back to restore it all

This works because Glide stores a **reciprocal token** after every undoable action — a record of what inverse to fire if the next gesture is the exact reverse. The token expires the moment you do anything else (click, switch apps, let time pass), so it never fires unexpectedly. Reciprocals can be disabled per-rule if you prefer strict one-way behavior.

---

### App Switcher with continuous scroll

When you bind a gesture to **Next App (App Switcher)** and hold the swipe, Glide keeps scrolling through your open apps as your fingers move horizontally. Each step fires a haptic click. Release to commit. Swipe back to change your mind. It's the same feel as a scroll wheel, except it's your trackpad.

---

<br>

## Making It Yours

Click the hand icon in your menu bar and open **Preferences**.

The **Gestures** tab lists all your rules grouped by finger count. Each rule is: fingers + direction + speed + action. The combinations are almost unlimited — 2, 3, 4, or 5 fingers × 5 directions (up, down, left, right, click-tap) × 3 speeds = 75 possible slots, and you can leave most of them empty. Add a rule with **+**, drag to reorder, trash to delete.

The **Tuning** tab exposes the physics layer:

- **Activation Threshold** — how far fingers need to travel before a swipe locks in
- **Candidate Frames** — how many MT frames to analyze before committing to a gesture
- **Fast / Slow Velocity Thresholds** — tune the speed band boundaries to match your hands
- **Pinch Spread Threshold** — controls how aggressively pinch gestures are filtered out
- **Edge Margins** — the four Safe Zone sliders, with a live trackpad map

The **General** tab has haptic feedback, window targeting (focused window vs. window under cursor), and launch at login.

### App-specific rules

Every rule has an optional **App Filter**. When set, that rule only fires when the specified app is frontmost. This lets you build context-aware workflows — the same swipe does different things in Safari vs. Figma vs. your terminal. Global (unfiltered) rules act as fallbacks for any app without its own rule.

---

<br>

## Under the Hood

For anyone who wants to read, fork, or contribute.

Glide is eight Swift source files, roughly 190KB of code. Zero dependencies. No Xcode project — just `swiftc` and the system SDK.

**`MultitouchBridge.swift`** loads `MultitouchSupport.framework` via `dlopen` at runtime (it's a private Apple framework). Enumerates all multitouch devices, registers a C callback, and handles retry logic for cases where the device list is empty right after wake. Properly unregisters callbacks and releases device references on stop.

**`GestureEngine.swift`** is the core pipeline. Runs a five-phase state machine: `idle → candidate → lockedSwipe → fired → idle`, with `ignored` as a dead end for non-swipe touch sequences (pinches, single-finger contacts, etc.). The candidate phase samples velocity, checks finger-to-centroid coherence to reject chaotic multi-finger contacts, and measures spread delta to veto pinch gestures before they can lock. A hardware watchdog timer detects when the MT callback goes silent (stale device) and automatically restarts the bridge.

**`ActionExecutor.swift`** dispatches the ~40 supported actions via Accessibility API for window frame manipulation, CGEvent for keyboard simulation, NSWorkspace for app control, and private notification names for things like Notification Center. Maintains a `savedFrames` dictionary keyed by (pid, window identity) so maximize/restore can return windows to their exact prior dimensions.

**`Settings.swift`** defines all enums (`GestureAction`, `GestureDirection`, `GestureSpeed`, `GestureFingers`), the `GestureRule` codable struct, and the `GestureTuning` struct. Persists everything to `UserDefaults` as JSON with rule deduplication, schema migration between versions, and bounds-clamping on all tuning parameters.

**`PreferencesUI.swift`** is a full SwiftUI panel built with `NavigationSplitView`: sidebar for rule selection, detail pane for editing. The Tuning tab uses a live-updating trackpad visualizer drawn with Canvas. Engine state (current phase, finger count, centroid position) is pushed from `GestureEngine` via a callback closure rather than polling on a timer.

**`AppDelegate.swift`** handles the menu bar item, Accessibility permission checking with polling fallback, sleep/wake observers, and a cascade restart strategy at +0s, +2s, +5s, +10s after wake — because different Mac models reinitialize trackpad hardware at different speeds.

---

<br>

## Build Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools: `xcode-select --install`
- Swift 5.9+ (Swift 6.3 recommended)

The build script compiles `arm64` and `x86_64` slices and merges them with `lipo` into a universal binary inside `build/Glide.app`. Total build time is under 30 seconds on most machines.

```bash
bash build.sh
```

If you only want to build for your current architecture:

```bash
# Apple Silicon
swiftc -O -target arm64-apple-macosx13.0 \
  Sources/main.swift Sources/MultitouchBridge.swift \
  Sources/Settings.swift Sources/ActionExecutor.swift \
  Sources/GestureEngine.swift Sources/PreferencesWindow.swift \
  Sources/PreferencesUI.swift Sources/AppDelegate.swift \
  -framework Cocoa -framework SwiftUI -framework IOKit \
  -o build/Glide
```

---

<br>

## Troubleshooting

**Nothing happens when I swipe**
Go to System Settings → Privacy & Security → Accessibility. Glide must appear in the list with its toggle on. If it's already there but gestures still don't work, remove it from the list, relaunch Glide, and re-add it — macOS sometimes holds stale permission state.

**Gestures stop working after waking from sleep**
Glide schedules automatic restarts at 0, 2, 5, and 10 seconds after any wake notification, since different Mac models reinitialize the trackpad at different speeds. If gestures are still broken after ~15 seconds, quit Glide from the menu bar and relaunch it.

**Fast swipes always register as Normal**
Open Preferences → Tuning and lower the Fast Velocity Threshold. Or enable debug logging (Preferences → General) and check Console — Glide prints raw velocity values on every gesture so you can see exactly what your swipe speed measures as.

**Gestures fire when I rest my palm**
Increase the edge margin sliders in Preferences → Tuning. The live trackpad map updates instantly as you drag the sliders. Start by setting all four margins to 0.10 and test from there.

**A swipe direction feels backwards**
Enable debug logging and watch for `angle=X°` in Console. The mapping is: Right ≈ 0°, Up ≈ 90°, Left ≈ 180°, Down ≈ 270°. If the angle lands between two directions, try swiping more decisively along one axis.

---

<br>

## Contributing

The codebase is intentionally small and meant to stay that way. To add a new action: add a case to `GestureAction` in `Settings.swift`, handle it in `ActionExecutor.execute()`, and optionally add an inverse in `GestureAction.inverseAction` if it's reversible.

For gesture detection changes in `GestureEngine`, enable debug logging first — every phase transition, velocity sample, and classification decision is logged to stdout.

PRs are welcome. Keep dependencies at zero.

---

<br>

<p align="center">
  <sub>MIT licensed &nbsp;·&nbsp; Uses Apple's private <code>MultitouchSupport</code> framework for raw trackpad access &nbsp;·&nbsp; Velocity detection inspired by <a href="https://github.com/taj-ny/InputActions">InputActions</a></sub>
</p>
