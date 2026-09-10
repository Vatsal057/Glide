[← Back to manual](../USAGE.md)

# Every action, explained

Open the **Action** picker in a gesture editor to view all available actions grouped by category.

### Apps
| Action | What it does |
|---|---|
| Quit App Under Cursor | Closes the application under your mouse pointer. |
| Force Quit App Under Cursor | Force-closes the application under your pointer when unresponsive. |
| Quit Frontmost App | Closes the active application. |
| Hide App Under Cursor | Hides the application under your pointer while keeping it running. |
| Hide Other Apps | Hides all applications except the one under your pointer. |
| Open App… | Launches an application selected from a file dialog. |
| Activate Next App / Activate Previous App | Switches focus directly to the adjacent running application instantly. |

### Windows
| Action | What it does |
|---|---|
| Minimize Window | Sends the active window to the Dock. |
| Minimize All Apps | Hides all open windows to reveal the desktop. |
| Restore Minimized Apps | Restores the windows hidden by "Minimize All Apps". |
| Maximize Window | Resizes the window to fill the available display area. |
| Restore/Un-maximize Window | Returns a maximized or minimized window to its previous dimensions. |
| Close Window | Closes the active window directly from the trackpad. |
| Enter Fullscreen / Exit Fullscreen / Toggle Fullscreen | Enters, exits, or toggles native macOS fullscreen mode. |
| Cycle Windows (⌘`) | Cycles between windows of the current application (for example, between multiple browser windows). |
| Snap: Left Half / Right Half | Resizes the window to fill exactly half of the screen. |
| Snap: Top-Left / Top-Right / Bottom-Left / Bottom-Right | Resizes the window to fill one quadrant of the screen. |
| Center Window | Centers the active window at its current dimensions. |
| Move to Next Display | Moves the window to an adjacent monitor while preserving relative position. |

### Screenshots
| Action | What it does |
|---|---|
| Screenshot (Area) | Opens the selection crosshair to capture a defined region. |
| Screenshot (Full) | Captures the entire screen to a file. |
| Screenshot (Area → Clipboard) | Captures a selected region directly to the clipboard. |
| Screenshot (Full → Clipboard) | Captures the entire screen directly to the clipboard. |
| Screenshot Toolbar | Opens the native macOS screenshot overlay with recording options. |

### Media & display
| Action | What it does |
|---|---|
| Play / Pause | Toggles playback for the active media application. |
| Next Track / Previous Track | Skips forward or backward in media playback. |
| Volume Up / Volume Down / Mute / Unmute | Controls system audio output. |
| Brightness Up / Brightness Down | Adjusts display backlight brightness. |

### System
| Action | What it does |
|---|---|
| Mission Control | Opens Mission Control for an overview of open windows. |
| App Exposé | Displays all open windows of the active application. |
| Show Desktop | Slides open windows away to reveal the desktop. |
| Launchpad | Opens Launchpad. |
| Spotlight | Opens Spotlight search. |
| Notification Center | Opens Notification Center and system widgets. |
| Lock Screen | Locks the current macOS session. |
| Sleep | Puts the Mac into sleep state. |
| Empty Trash | Empties the Trash. |
| Open Finder | Opens a new Finder window. |
| Open Downloads | Opens the Downloads folder directly. |

### Custom
These actions allow triggering external scripts, menus, and shortcuts:

| Action | What it does |
|---|---|
| Menu Item… | Selects a specific menu item from any app (e.g. Safari → File → New Tab) and fires it directly. |
| Keyboard Shortcut… | Records a key combination and sends it upon gesture trigger, connecting trackpad gestures to application shortcuts. |
| Advanced Keyboard… | Executes an orchestrated sequence of key taps, holds, and releases for shortcuts requiring ordered input. |
| Run Shortcut… | Triggers a Shortcuts.app workflow by name. |
| Shell Command… | Executes a terminal command. |
| AppleScript… | Executes an AppleScript script. |

> ⚠️ **Shell Command, AppleScript, and Run Shortcut execute system code when triggered.** When importing a configuration file from another user, Glide displays a security verification modal listing all embedded scripts before activating them. See [Your configuration file](09-configuration-file.md).

### Other
| Action | What it does |
|---|---|
| Do Nothing | Explicit no-op. Useful for silencing conflicting macOS system gestures (see [macOS Gesture Conflicts](08-general-preferences.md)) or holding trigger slots. |

---
[← Previous: Smart filters & conditions](02-filters-and-conditions.md) · [Back to manual](../USAGE.md) · [Next: Global keyboard shortcuts →](04-keyboard-shortcuts.md)
