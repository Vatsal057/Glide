# Glide 🖐

A high-performance, background macOS utility that provides advanced, fully customizable trackpad gestures. Glide provides a fluid, Windows 11-like user experience by replacing hardcoded gesture logic with a dynamic, data-driven rule engine.

---

## Key Features

- **3-Finger Click to Quit**: Hover over any app window and quickly tap with 3 fingers to quit it instantly.
- **Fluid App Switcher**: 3-finger swipe left or right to browse and switch between active apps with ultra-low latency.
- **Customizable Rule Engine**: Map arbitrary finger counts (3, 4, 5) and directions to specific window management actions.
- **Context Awareness**: Smart gestures that adapt to your workflow (e.g., swipe up restores minimized apps).
- **Performance**: Built with `MultitouchSupport.framework` for raw, low-latency trackpad data processing.
- **Privacy First**: Runs entirely locally. Uses macOS Accessibility APIs only to identify windows and perform actions.

---

## Window Management Actions

| Action | Description |
|--------|-------------|
| **Quit App** | Instantly terminates the app under the cursor. |
| **App Switcher** | Fluidly browse and switch between open applications. |
| **Mission Control** | Toggle macOS Mission Control. |
| **Minimize Window** | Minimize the current window under the cursor. |
| **Maximize/Restore** | Scale windows or restore them to previous size. |
| **Fullscreen** | Enter or exit fullscreen mode for window under cursor. |

---

## Recommended System Settings ⚙️

To ensure Glide's gestures function smoothly and don't conflict with macOS's native behavior, we strongly recommend adjusting your **System Settings → Trackpad → More Gestures**:

1. **Disable Mission Control**: Turn off the default 3/4 finger swipe up. Glide provides its own customizable Mission Control trigger.
2. **Disable App Exposé**: Turn off the 3/4 finger swipe down.
3. **Switch Between Desktops**: We recommend setting this to **4 Fingers**. By default, Glide uses **3-Finger Swipe** for its fluid app switcher, though this can be customized in Glide's preferences.

---

## Build & Install

```bash
# Clone the repository
git clone https://github.com/Vatsal057/Glide
cd Glide

# Build the application
chmod +x build.sh
./build.sh
```

Then drag `build/Glide.app` to your `/Applications` folder.

### Requirements
- macOS 12 Monterey or later
- Xcode Command Line Tools (`xcode-select --install`)

---

## First Launch & Permissions

1. Open `Glide.app` from your Applications folder.
2. macOS will prompt for **Accessibility** permission.
3. Grant it in **System Settings → Privacy & Security → Accessibility**.
4. A 🖐 icon will appear in your menu bar — you're ready to glide!

---

## Usage Tips

- **Quick Taps**: The click-to-quit gesture is a quick tap (all fingers down and up in <0.35s) to avoid conflicts with scrolling.
- **Preferences**: Access the **Preferences...** menu from the status bar icon to customize your rules and sensitivity.
- **Disable/Enable**: You can pause gesture detection any time via the menu bar icon.

---

## License

This project is licensed under the MIT License.
