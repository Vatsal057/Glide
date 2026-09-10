[← Back to manual](../USAGE.md)

# Every action, explained

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

> ⚠️ **Shell Command, AppleScript, and Run Shortcut execute code the moment the gesture fires.** If you import a config someone else made, Glide's importer flags every gesture bound to one of these before applying it, so you always know what you're agreeing to run. See [Your configuration file](09-configuration-file.md).

### Other
| Action | What it does |
|---|---|
| Do Nothing | A no-op. Use it to silence a macOS system gesture you find annoying (see [macOS Gesture Conflicts](08-general-preferences.md)) or to reserve a slot for later. |

---
[← Previous: Smart filters & conditions](02-filters-and-conditions.md) · [Back to manual](../USAGE.md) · [Next: Global keyboard shortcuts →](04-keyboard-shortcuts.md)
