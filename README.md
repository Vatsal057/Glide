# Glide — Trackpad Gesture Customizer for macOS

Glide is a lightweight and powerful application for macOS that lets you control your computer using custom trackpad gestures. By sliding or clicking with three, four, or five fingers, you can manage windows, control media, launch apps, take screenshots, and trigger system shortcuts. 

Glide works in the background and intercepts your trackpad movements, translating them into actions instantly.

---

## Table of Contents
1. [Core Concepts](#1-core-concepts)
2. [Smart Filters & Conditions](#2-smart-filters--conditions)
3. [Every Feature & Action Explained](#3-every-feature--action-explained)
4. [Tuning & Precision Controls](#4-tuning--precision-controls)
5. [General App Preferences](#5-general-app-preferences)
6. [Managing Your Configuration File](#6-managing-your-configuration-file)

---

## 1. Core Concepts

Instead of memorizing complex keyboard shortcuts, Glide lets you use natural trackpad movements. Every gesture you configure is built on a few simple elements:

*   **Finger Count:** Glide supports gestures using **3**, **4**, or **5** fingers.
*   **Gesture Types:** 
    *   **Swipes:** Sliding your fingers in a specific direction (**Up**, **Down**, **Left**, or **Right**).
    *   **Clicks:** Pressing down on the trackpad with all fingers in place.
    *   **Force Clicks:** Pressing down harder on a Force Touch trackpad to trigger a deeper physical click.
*   **Swipe Speed:** You can map different actions to the exact same swipe depending on how fast you move. Glide recognizes **Slow**, **Normal**, and **Fast** swipes. For example, a slow three-finger swipe right can switch to the next open window, while a fast flick right can launch your browser.

---

## 2. Smart Filters & Conditions

You don't have to use the same gestures for everything. Glide lets you restrict your gestures using rules so they only trigger under specific conditions:

*   **Keyboard Modifiers:** You can set a gesture to only work when you are holding down a specific key on your keyboard—such as **Command (⌘)**, **Shift (⇧)**, **Option (⌥)**, or **Control (⌃)**—or only when no keys are held down at all.
*   **App Filters:** You can restrict a gesture to a specific app. For example, a three-finger click might close a tab in Safari, but mute the audio in Spotify.
*   **Window State Filters:** Gestures can change behavior depending on whether the window you are using is:
    *   *Fullscreen* (filling the entire screen in macOS fullscreen mode).
    *   *Not Fullscreen*.
    *   *Maximized* (stretched to fill the desk space but still showing the top menu bar).
    *   *Not Maximized*.
*   **Reciprocal (Reverse) Gestures:** This feature allows you to "undo" a gesture by swiping in the opposite direction immediately afterward. For example, if swiping up maximizes a window, swiping down immediately afterward will restore it to its original size.

---

## 3. Every Feature & Action Explained

Below is the complete list of actions you can assign to your trackpad gestures, broken down by category:

### Apps (Application Control)
*   **Quit App Under Cursor:** Instantly closes the application whose window is directly under your mouse pointer, saving you from clicking the app menu.
*   **Force Quit App Under Cursor:** Immediately shuts down the app under your mouse pointer. Use this if an application has frozen or stopped responding.
*   **Quit Frontmost App:** Closes the application you are currently actively using.
*   **Hide App Under Cursor:** Minimizes/hides the application under your mouse pointer from view without closing it.
*   **Hide Other Apps:** Hides all other running apps except for the one under your mouse cursor, letting you focus on a single task.
*   **Open App...:** Launches an application of your choice. When setting up this gesture, Glide opens a file picker so you can select any app in your Applications folder.
*   **Next App (App Switcher) / Previous App (App Switcher):** Activates the macOS application switcher (equivalent to Command + Tab). Sliding your fingers left or right lets you cycle through your open apps.
*   **Activate Next App / Activate Previous App:** Instantly cycles and switches focus to the next or previous running app on your system directly, without opening the app switcher screen.

### Windows (Window Management)
*   **Minimize Window:** Minimizes the active window down into your Dock.
*   **Minimize All Apps:** Instantly hides all open windows on your screen so you can see your clean desktop.
*   **Restore Minimized Apps:** Reopens and restores all the windows that you just hid using the "Minimize All Apps" command.
*   **Maximize Window:** Resizes the active window to fill the entire visible screen area without entering macOS fullscreen mode.
*   **Restore/Un-maximize Window:** Returns a maximized window back to its previous smaller size, or restores a minimized window.
*   **Close Window:** Closes the active window (equivalent to clicking the red button in the window corner).
*   **Enter Fullscreen / Exit Fullscreen / Toggle Fullscreen:** Puts the active window into native macOS fullscreen mode, exits it, or switches back and forth between the two states.
*   **Cycle Windows (⌘`):** Cycles through different open windows belonging to the *same* application (for example, switching between two different Chrome windows).
*   **Snap: Left Half / Right Half:** Resizes the active window to fill exactly the left or right half of your screen.
*   **Snap: Top-Left / Top-Right / Bottom-Left / Bottom-Right:** Resizes the active window to fill exactly one quadrant (one-quarter) of your screen.
*   **Center Window:** Centers the active window in the exact middle of your monitor while keeping its current size.
*   **Move to Next Display:** If you have multiple monitors connected, this instantly sends the active window to your other display, placing it in the same relative position.

### Screenshots
*   **Screenshot (Area):** Opens the selective screenshot crosshair so you can click and drag a box around what you want to capture.
*   **Screenshot (Full):** Instantly captures a screenshot of your entire screen.
*   **Screenshot (Area → Clipboard):** Lets you select an area of the screen and copies the image directly to your clipboard so you can paste it immediately into a chat or document.
*   **Screenshot (Full → Clipboard):** Takes a screenshot of your entire screen and copies it directly to your clipboard.
*   **Screenshot Toolbar:** Opens the built-in macOS screenshot utility panel with options for recording your screen or setting a timer.

### Editing
*   **Copy / Paste / Cut:** Standard editing commands to duplicate, insert, or move selected text or files.
*   **Undo / Redo:** Reverses your last action, or re-performs an action you just undid.
*   **Select All:** Selects all text or items in the current window.
*   **Find:** Opens the search bar inside your active app (useful for finding words on a webpage or document).
*   **Emoji & Symbols:** Opens the macOS emoji keyboard pop-up.
*   **Reload Page:** Refreshes the page inside your web browser or active app.
*   **New Tab:** Opens a new tab in your web browser or supported app.

### Media & Display
*   **Volume Up / Volume Down / Mute:** Controls your Mac's system audio volume.
*   **Play / Pause / Next Track / Previous Track:** Controls playback for media players (such as Spotify, Apple Music, YouTube in a browser, or video players).
*   **Brightness Up / Brightness Down:** Adjusts your computer screen brightness.

### System
*   **Mission Control:** Opens macOS Mission Control to show an overview of all your open windows.
*   **App Exposé:** Shows all open windows belonging to the application you are currently using.
*   **Show Desktop:** Sweeps all open windows to the side to give you a clear view of your desktop files.
*   **Launchpad:** Opens the macOS Launchpad to view and open your installed apps.
*   **Spotlight:** Opens the Spotlight search bar in the middle of your screen.
*   **Notification Center:** Slides out the macOS notification and widget panel from the right edge of your screen.
*   **Lock Screen:** Instantly locks your computer, returning you to the password screen.
*   **Sleep:** Puts your Mac to sleep to conserve power.
*   **Empty Trash:** Safely empties your system Trash bin.
*   **Open Finder:** Launches a new Finder window so you can browse your files.
*   **Open Downloads:** Directly opens your user Downloads folder.

### Other
*   **Do Nothing:** This action does nothing. It is useful for disabling built-in system gestures that you find annoying, or reserving a gesture slot for future use.

---

## 4. Tuning & Precision Controls

Glide includes custom calibration options so you can fine-tune how sensitive your trackpad is to gestures:

### Recognition (How swipes are detected)
*   **Activation Threshold:** Adjusts how far your fingers must travel on the trackpad before Glide registers it as a swipe. Increase this if you find yourself triggering swipes accidentally, or decrease it for faster response times.
*   **Switcher Step Distance:** Sets how far you need to slide your fingers horizontally to move from one app to the next when using the App Switcher gesture.
*   **Switcher Debounce:** A small delay timer that prevents you from accidentally sliding through multiple apps too quickly in the App Switcher.

### Speed Classification (Intent)
*   **Fast Velocity Threshold:** The base movement threshold for flick intent. Glide also checks for a short gesture duration and sharp acceleration before calling a swipe Fast.
*   **Slow Velocity Threshold:** The base movement threshold for controlled slow intent. Glide also checks hold time and travel distance before calling a swipe Slow.
*   **Speed Sample Frames:** The number of movement frames Glide uses for smoothed velocity and acceleration. Increasing this can reduce noisy speed changes.

### Direction Detection
*   **Angle Tolerance:** Adjusts the quadrant size for directions. At 45°, the trackpad is split into four equal diagonal quarters (Up, Down, Left, Right). Lowering this number narrows the detection angle, creating "dead zones" along the diagonals so that diagonal movements are ignored unless they are clearly straight.

### Pinch Veto (Preventing conflicts with Zoom/Pinch)
*   **Candidate Frames:** The number of frames Glide analyzes at the very beginning of a touch before deciding if it's a swipe. Higher values help separate swipes from standard pinch-to-zoom gestures.
*   **Pinch Spread Threshold:** The overall limit on how much your fingers can spread apart or come together during a gesture. If this limit is exceeded, Glide assumes you are pinching/zooming and cancels the swipe.
*   **Pinch Frame Threshold:** The maximum amount of finger spreading allowed in a single frame. If you pinch your fingers together quickly, this instantly cancels any swipe detection.
*   **Swipe Coherence:** Adjusts how closely your fingers must travel in the same direction. A value of 1.0 means all fingers must move in the exact same direction. Lowering this makes detection more lenient if your fingers drift apart slightly while swiping.

### Trackpad Edge Margins
*   **Enable Edge Margin:** Turns on boundary dead-zones.
*   **Margins (Left, Right, Top, Bottom):** Allows you to shade off between 0% and 20% of each trackpad edge. Any touch starting inside these margins will be ignored. This is perfect for preventing accidental gestures if you rest your palms or thumbs on the edges of the trackpad.
*   **Visual Trackpad Preview:** The preferences pane includes a physical trackpad simulator. When you touch your Mac trackpad, a dot appears on this visual simulator in real-time. If your finger lands in the margin zone, the dot turns **orange** (ignored); if it lands in the active area, it turns **green** (active).

---

## 5. General App Preferences

Glide's general settings menu lets you configure how the app behaves globally:

*   **Accessibility Assistant:** A simple card showing whether Glide has the macOS security permissions it needs. If permissions are missing, a button is provided to open your Mac's System Settings directly to the correct page.
*   **Window Targeting:** Choose where window actions are directed:
    *   *Focused Window First:* Actions affect the window you are currently typing in.
    *   *Window Under Cursor First:* Actions affect the window that your mouse pointer is hovering over, even if it is in the background.
*   **Haptic Feedback:** Toggles trackpad vibrations. If enabled, your trackpad will give physical clicks and thumps to confirm when a gesture is recognized, when the app switcher steps, or when a reciprocal gesture is activated.
*   **Debug Logging:** Prints technical details of your trackpad inputs to the system Console for troubleshooting.
*   **Launch at Login:** Automatically opens Glide every time you boot up your Mac.
*   **Stats Dashboard:** Displays live statistics, including how many gestures you have configured, how many finger sets are in use, and if any app-launch gestures are missing their target applications.

---

## 6. Managing Your Configuration File

All of your settings, gestures, and tuning parameters are saved in a simple text file:
`~/Library/Application Support/Glide/config.yaml`

Glide provides several tools in the **Configuration** section to manage this file:
*   **Open folder button:** Instantly opens the folder containing your config file in Finder.
*   **Export Copy...:** Saves a backup copy of your configuration file anywhere on your Mac. You can use this to keep backups or share your custom layout with other Glide users.
*   **Import Config...:** Loads a previously exported `.yaml` file to restore your configuration instantly.
