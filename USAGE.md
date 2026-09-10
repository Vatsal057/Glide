# Glide Usage Manual

Everything Glide can do, in one place. If you just want to get moving, the [README](README.md#quick-start) has a two-minute quick start — come back here when you want to go deeper.

## Table of contents

1. [Core concepts](#1-core-concepts)
2. [Smart filters & conditions](#2-smart-filters--conditions)
3. [Every action, explained](#3-every-action-explained)
4. [Global keyboard shortcuts](#4-global-keyboard-shortcuts)
5. [App Switcher](#5-app-switcher)
6. [TrackPoint](#6-trackpoint)
7. [Tuning & precision controls](#7-tuning--precision-controls)
8. [General preferences](#8-general-preferences)
9. [Your configuration file](#9-your-configuration-file)
10. [Permissions Glide asks for](#10-permissions-glide-asks-for)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Core concepts

Instead of memorizing keyboard shortcuts, Glide lets you use trackpad movements. Open **Preferences → Gestures** to see and edit them. Every gesture is built from a few simple elements:

- **Finger count.** Gestures use **3**, **4**, or **5** fingers.
- **Gesture type:**
  - **Swipe** — sliding your fingers in a direction (**Up**, **Down**, **Left**, or **Right**).
  - **Click** — pressing down on the trackpad with all fingers in place, like a normal click but with more fingers down.
  - **Force Click** — pressing down harder on a Force Touch trackpad, past the normal click, for a second distinct action on the same fingers.
  - **Tap & Hold** — resting fingers motionless for a moment.
- **Swipe speed.** The same swipe direction can map to two different actions depending on how fast you move: **Slow**, **Normal**, or **Fast**. For example, a slow 3-finger swipe right could switch to the next window, while a fast flick right launches your browser. Speed only applies to swipes — clicks and holds don't have one.

Add a gesture with the **+** button in the Gestures list, then set its finger count, type, and action in the editor on the right. New gestures start as an inactive draft (shown with a pause icon) until you pick a real action.

If two gestures share the exact same trigger (same fingers, direction, speed, and filters), the one **lower in the list** wins — the list shows a warning icon on any gesture another one shadows.

## 2. Smart filters & conditions

You don't have to use the same gesture for everything everywhere. Every gesture's editor has a **Conditions** section you can expand:

- **Keyboard modifiers.** Restrict a gesture to only fire while a specific key is held — **Command (⌘)**, **Shift (⇧)**, **Option (⌥)**, or **Control (⌃)** — or require that *no* modifier is held. Useful for stacking two behaviors on the same swipe (e.g. plain 3-finger swipe left/right browses apps; Shift + the same swipe does something else).
- **App filter.** Restrict a gesture to one specific app. A 3-finger click could close a tab in Safari but mute Spotify, using two separate rules each filtered to its own app.
- **Window state filter.** Change behavior based on the frontmost window's layout:
  - *Fullscreen* — filling the screen in native macOS fullscreen mode.
  - *Not Fullscreen*.
  - *Maximized* — resized to fill the screen but still showing the menu bar (not the same as native fullscreen).
  - *Not Maximized*.

  This is how the built-in gestures build a "ladder": swipe up once to maximize, swipe up again (now that the window is maximized) to go fullscreen. Same gesture, two window states, two outcomes.
- **Reciprocal (reverse) gestures.** For swipes, this lets the opposite direction undo the action — swipe up to maximize, swipe down right after to restore. Enabled by default for most actions that have a natural opposite (maximize ↔ restore, volume up ↔ down, next track ↔ previous). Turn it off, or pick a custom reverse action, in Conditions.
- **Continuous gestures.** Left/right and up/down swipes can be set to *continuous*: instead of firing once, they run a begin → repeat → end sequence for as long as you keep your fingers down and moving. Good for scrub-style controls like volume or brightness, where you want the action to keep stepping while you swipe rather than firing once per gesture.

## 3. Every action, explained

Open the **Action** picker in a gesture's editor to see these grouped by category.

### Apps
| Action | What it does |
|---|---|
| Quit App Under Cursor | Closes the app whose window is under your mouse pointer. |
| Force Quit App Under Cursor | Force-closes the app under your pointer — for when it's frozen. |
| Quit Frontmost App | Closes the app you're actively using. |
| Hide App Under Cursor | Hides the app under your pointer without closing it. |
| Hide Other Apps | Hides every app except the one under your pointer. |
| Open App… | Launches an app you choose from a file picker. |
| Activate Next App / Activate Previous App | Switches focus straight to the next or previous running app — no switcher UI, just an instant swap. |

### Windows
| Action | What it does |
|---|---|
| Minimize Window | Sends the active window to the Dock. |
| Minimize All Apps | Hides every open window to show a clean desktop. |
| Restore Minimized Apps | Brings back everything "Minimize All Apps" just hid. |
| Maximize Window | Resizes the window to fill the screen (not native fullscreen). |
| Restore/Un-maximize Window | Returns a maximized (or minimized) window to its previous size. |
| Close Window | Closes the active window — the red button, from your trackpad. |
| Enter Fullscreen / Exit Fullscreen / Toggle Fullscreen | Enters, exits, or toggles native macOS fullscreen. |
| Cycle Windows (⌘`) | Cycles between windows of the *same* app (e.g. two Chrome windows). |
| Snap: Left Half / Right Half | Resizes the window to exactly half the screen. |
| Snap: Top-Left / Top-Right / Bottom-Left / Bottom-Right | Resizes the window to exactly one quarter of the screen. |
| Center Window | Centers the window on screen at its current size. |
| Move to Next Display | Sends the window to your other monitor, same relative position. |

### Screenshots
| Action | What it does |
|---|---|
| Screenshot (Area) | Opens the crosshair to select and capture a region. |
| Screenshot (Full) | Captures the entire screen. |
| Screenshot (Area → Clipboard) | Selects a region and copies the image straight to your clipboard. |
| Screenshot (Full → Clipboard) | Captures the entire screen straight to your clipboard. |
| Screenshot Toolbar | Opens the native macOS screenshot panel (with recording/timer options). |

### Media & display
| Action | What it does |
|---|---|
| Play / Pause | Plays or pauses whatever media app is active. |
| Next Track / Previous Track | Skips forward or back. |
| Volume Up / Volume Down / Mute / Unmute | Controls system volume. |
| Brightness Up / Brightness Down | Adjusts screen brightness. |

### System
| Action | What it does |
|---|---|
| Mission Control | Shows an overview of every open window. |
| App Exposé | Shows every window of the app you're currently using. |
| Show Desktop | Sweeps windows aside to reveal the desktop. |
| Launchpad | Opens Launchpad. |
| Spotlight | Opens Spotlight search. |
| Notification Center | Slides out the notification & widget panel. |
| Lock Screen | Locks your Mac. |
| Sleep | Puts your Mac to sleep. |
| Empty Trash | Empties the Trash. |
| Open Finder | Opens a new Finder window. |
| Open Downloads | Opens your Downloads folder directly. |

### Custom
These let you reach outside Glide's built-in list:

| Action | What it does |
|---|---|
| Menu Item… | Picks a specific menu item from any app (e.g. Safari → File → New Tab) and fires it directly, no mouse required. |
| Keyboard Shortcut… | Records a key combination and sends it when the gesture fires — the bridge between a trackpad gesture and any app-specific shortcut Glide doesn't have a named action for. |
| Advanced Keyboard… | Builds a sequence of individual key taps, holds, and releases — for shortcuts that need keys pressed and released in a specific order rather than all at once. |
| Run Shortcut… | Runs a Shortcuts.app shortcut by name. |
| Shell Command… | Runs a shell command. |
| AppleScript… | Runs an AppleScript. |

> ⚠️ **Shell Command, AppleScript, and Run Shortcut execute code the moment the gesture fires.** If you import a config someone else made, Glide's importer flags every gesture bound to one of these before applying it, so you always know what you're agreeing to run. See [§9](#9-your-configuration-file).

### Other
| Action | What it does |
|---|---|
| Do Nothing | A no-op. Use it to silence a macOS system gesture you find annoying (see [§8, macOS Gesture Conflicts](#8-general-preferences)) or to reserve a slot for later. |

## 4. Global keyboard shortcuts

Beyond trackpad gestures, Glide can bind any of its actions to a **global keyboard shortcut** — one that works from anywhere, not just inside a specific app. Set these up in **Preferences → Keyboard**.

Add a shortcut, record the key combination, and pick an action exactly the way you would for a gesture — every action above is available. The combo must include at least one modifier key (⌘ ⌥ ⌃ ⇧) so it doesn't collide with normal typing; Glide will tell you if it doesn't.

Because these are global hotkeys, avoid combos other apps already rely on — Glide doesn't check for conflicts with other software's shortcuts, only with itself.

## 5. App Switcher

The App Switcher is a hold-and-swipe way to browse and jump between running apps — separate from the gesture rule list, and reserved on **3-finger left/right swipes** by default. Turn it on or off, and configure it, in **Preferences → App Switcher**.

**How it works:** swipe left or right with 3 fingers to browse apps, and release to switch — or lift all fingers without committing to cancel.

**Two presentation styles:**
- **Newer** — Glide's own overlay: app icons in a row, a window "deck" for the selected app if it has more than one window (swipe up or down to pick a specific one), live thumbnails of each window when Screen Recording access is granted (falls back to app icons if not — switching still works either way).
- **Legacy** — converts your swipe directly into native ⌘Tab events and lets the system's own switcher UI handle it. No extra permissions needed, works on every macOS version, but no custom overlay and no per-window selection — it's exactly what ⌘Tab already does, just triggered by a swipe.

Because it reserves the 3-finger horizontal swipe, any gesture you create on that same trigger needs a modifier key (like holding Shift) to coexist with it — the editor will tell you when this applies.

Other settings: skip Finder in the switcher when it has no open windows, restore minimized windows automatically when you select them, animate selection changes (off by default — it roughly doubles the CPU cost of a swipe), and two sliders for how far you need to swipe to step to the next app and how quickly repeated steps can happen.

## 6. TrackPoint

TrackPoint turns a patch of your trackpad into a pointing stick, like the red nub in the middle of a ThinkPad keyboard. Instead of your finger's *position* mapping directly to cursor position — the way a trackpad normally works — your finger's *displacement from where it landed* maps to cursor *velocity*. Lean left and the cursor moves left for as long as you hold the lean; ease back toward center and it slows down. That's why a fingertip-sized patch of trackpad can move the cursor across the entire screen without your finger ever having to lift and reset. Turn it on and configure it in **Preferences → TrackPoint**.

**Why you'd want it:** reaching the far corner of a large or multi-monitor screen normally takes multiple relative swipes. With TrackPoint engaged, you just keep leaning your finger in a direction and the cursor keeps going.

**Activation modes** — how you tell Glide "I want to drive the cursor now" versus "I'm just using the trackpad normally":

| Mode | How you engage it |
|---|---|
| Double-Tap & Hold *(default)* | Tap once with one finger, tap again, and hold. The double tap is deliberate enough that you can't trigger it by accident just resting a finger on the pad. |
| One-Finger Hold | Rest one finger anywhere on the pad and hold still for a moment. |
| Corner Hold | Rest one finger in a corner you pick, and hold still for a moment. Keeps the rest of the trackpad free for normal use. |
| Two-Finger Hold | Rest two fingers anywhere and hold still; lift one and the remaining finger becomes the stick. |

Whichever mode you use, a short hold ("hold to engage") is what tells Glide you're committing to the stick rather than starting an ordinary drag or swipe — move too far before the hold completes and Glide steps aside, leaving the touch to macOS untouched.

**Once engaged:**
- Push your finger in a direction; the cursor accelerates that way. Ease off toward the anchor point and it decelerates. This continues as long as the finger stays down.
- Rest a **second finger** anywhere on the pad (if scrolling is enabled) to turn the stick into a scroll wheel instead of a cursor — the same role the middle button plays on a real TrackPoint.
- Lift the finger to disengage and hand control back to macOS.
- A soft haptic tick confirms engagement and release, if haptics are enabled.

**Tunable feel:** top speed, how far the finger has to travel to reach it (push distance), a dead zone around the anchor so a resting finger doesn't drift, and an acceleration curve exponent (higher values keep small pushes slow for fine control while still reaching full speed on a bigger lean). Corner-mode users can also set which corner and how large its zone is, visually, in the preferences pane.

## 7. Tuning & precision controls

**Preferences → Tuning** has three presets (**Relaxed**, **Balanced**, **Precise**) that adjust several settings at once — start there, then fine-tune with the sliders below if needed. Everything is described in plain language first, with the raw numeric values available under **Advanced** for anyone who wants exact control.

### Recognition
- **Sensitivity** — how far fingers must travel before a swipe registers. Lower it for a faster response, raise it if gestures trigger by accident.
- **Diagonal strictness** — how close to perfectly horizontal/vertical a swipe must be. Stricter creates "dead zones" along the diagonals so a sloppy diagonal movement doesn't get mistaken for a straight one.

### Accident protection
One combined **protection level** slider that scales several anti-false-positive checks together — how much finger spread cancels a swipe as a pinch, how uniformly your fingers have to move together, and how many initial frames Glide analyzes before committing to a swipe direction.

### Swipe speed
Only matters for gestures set to trigger specifically on a Slow or Fast swipe. Two sliders control how easily a swipe reads as fast (a flick) or as slow (a deliberate glide), plus a choice between two detection methods: **Simple** (one average-speed reading — predictable) or **Classic** (peak speed, acceleration, and timing together — snappier but less consistent).

### Repeating gestures
For continuous gestures (see [§2](#2-smart-filters--conditions)): one slider sets how rapidly the action repeats as you keep swiping.

### Trackpad regions
- **Edge margins** — shade off a strip along each edge (0–20%, each edge independent) where touches are ignored entirely. This is palm rejection: if your palm or thumb tends to rest near the bottom or side of the pad, widen that edge's margin so it can't start an accidental gesture. A **visual trackpad preview** shows a live dot as you touch the pad — green means active, orange means it landed in an ignored margin.
- **Force-click zones** — the size of each corner/edge zone used by force-click gestures that check *where* on the pad you pressed (e.g. taking a full-screen screenshot from the top-left corner but an area screenshot from the top-right).

## 8. General preferences

**Preferences → General** covers app-wide behavior:

- **Accessibility Permission** — a status card showing whether Glide has the access it needs, with a one-click button to the right System Settings page if not.
- **Window Targeting** — whether window actions (minimize, snap, close, etc.) target the window you're actively focused on, or the window your mouse is hovering over, when the two differ.
- **Debug Logging** — writes gesture detail to the system Console, for troubleshooting.
- **Launch at Login** — starts Glide automatically when you log in.
- **Haptics** — toggle trackpad vibration feedback overall, and assign a specific pattern (soft tick, tap, knock, double tap, rising, falling, etc.) to each kind of event: destructive actions, window actions, app switcher steps, reciprocal gestures, and so on. Selecting a pattern plays it immediately so you can feel the difference.
- **macOS Gesture Conflicts** — Glide can detect when one of its own gestures shares a trigger with a *native* macOS trackpad gesture (which would otherwise fire both, or fight for the same touch) and offers to disable the native one for you. Anything Glide disables this way is tracked separately so you can re-enable it individually, or all at once, later. Enable "Auto-Disable" to have this happen automatically as conflicts arise.
- **Stats** — live counts of your gestures (total, active, using each finger count), reciprocal pairs, modifier-restricted gestures, and any "Open App…" gestures pointing at an app that's no longer installed.
- **Updates** — checks GitHub for a newer release and, if there is one, downloads and installs it in place with a progress bar and checksum verification, finishing with a **Relaunch Now** button. If Glide can't write to its own install location, it hands you the downloaded disk image instead so you can install manually.
- **Welcome Tour** — replay the first-launch onboarding at any time.

## 9. Your configuration file

Every gesture, filter, and tuning value lives in one plain-text file:

```
~/Library/Application Support/Glide/config.yaml
```

It's YAML, so it's readable and editable by hand if you're comfortable with that — Glide's loader is deliberately lenient about missing or reordered fields. **Preferences → Configuration** gives you tools to manage it without touching a text editor:

- **Open in Finder** — jumps straight to the file's folder.
- **Export Copy…** — saves your current setup as a standalone `.yaml` file. Use this to back up your configuration, or to share your layout with another Glide user (send them the file, they use Import).
- **Import Config…** — loads a previously exported file, replacing your current gestures and settings. If the incoming config has any gesture bound to a scripted action (Shell Command, AppleScript, or Run Shortcut — see [§3](#3-every-action-explained)), Glide shows you exactly what it would run before you confirm the import.
- **Reset to Defaults…** — restores Glide's built-in starter gestures, discarding your custom ones. This cannot be undone, and Glide asks you to confirm first.

## 10. Permissions Glide asks for

| Permission | Why | If you don't grant it |
|---|---|---|
| **Accessibility** | Reads trackpad touches and controls windows (moving, resizing, focusing). | **Required.** Glide won't detect any gestures at all without it. |
| **Screen Recording** | Renders live window thumbnails in the newer App Switcher overlay. | Optional. The switcher still works — it falls back to showing each app's icon instead of a live preview. |
| **Automation (Apple Events)** | Runs AppleScript actions you configure, and reads app menus so you can assign a menu item to a gesture. | Optional. Only the "AppleScript…" and "Menu Item…" actions are affected. |

Glide never makes a network request except to check GitHub for a new release when you ask it to, or to download one you've chosen to install. There's no telemetry and no analytics.

## 11. Troubleshooting

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

Full details in [Installation](README.md#installation).

**Still stuck?** [Open an issue](https://github.com/Vatsal057/Glide/issues) — include your macOS version and, if it's gesture-related, which fingers/direction/action you expected.
