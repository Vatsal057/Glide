[← Back to manual](../USAGE.md)

# Trackpad Edge Controls

Trackpad Edge Controls turns the physical outer rim of your trackpad into precision hardware sliders. Sliding a single finger along any edge allows smooth adjustment of system volume, display brightness, keyboard backlight, microphone gain, Night Shift warmth, scrolling, or application scrub.

Configure edge bindings in **Preferences → Edge Controls**.

## How It Works

1. **Physical Rim Sliders:** Each of the four edges (Left, Right, Top, Bottom) can be mapped to a dedicated action:
   - **Right Edge** *(default: System Volume):* Slide up to raise volume; slide down to lower volume.
   - **Left Edge** *(default: Display Brightness):* Slide up to brighten the display; slide down to dim it.
   - **Top / Bottom Edges** *(optional):* Assign to Keyboard Backlight, Microphone Input Gain, Night Shift, Scroll, or App Switcher scrub.
2. **Native OSD Bezels:** Glide triggers native macOS system display bezels (identical to the overlays displayed by physical media keys). This operates with 0.0% CPU overhead and zero latency.
3. **Tactile Haptic Ticks:** Each adjustment increment delivers a subtle tactile tap via the trackpad Taptic Engine.

## Edge Scrolling

Assigning an edge to **Scroll** turns that rim into a scroll strip, the way edge scrolling worked on older Windows trackpads.

**Every edge scrolls vertically,** including the top and bottom. A horizontal rim acts as a forward/back strip rather than a horizontal scrollbar, since vertical is what people actually want to scroll. Sliding up a side edge, or right along a top or bottom edge, moves forward through the document.

Direction matches the system's natural scrolling by default: content follows your finger, the same as a two-finger scroll. **Reverse scroll direction** switches to the scrollbar convention.

### What makes it smooth

Multitouch frames arrive at uneven intervals and each position carries a little sensor noise, so emitting each frame's travel directly reads as judder even when your finger moved evenly. Glide buffers the travel and releases it on a steady 120 Hz clock, which cuts tick-to-tick judder by roughly 8× at a cost of about 22 ms of delay. Total distance is unchanged, so **Scroll Speed** still means exactly what it says.

Scrolling is also the one edge action with no haptic ticks and no quantization. The others are notched, moving in discrete steps with a tap for each; scrolling reads travel continuously, which is both what makes it smooth and what keeps it from buzzing the Taptic Engine every frame.

### Momentum

With **Glide after lifting your finger** enabled, a flick keeps scrolling and coasts to a stop over about a second.

Momentum has to be earned: it only engages above roughly 25 mm/s of finger speed. A slow, deliberate drag settles the moment you lift, so being careful never costs you an overshoot. A finger that comes to rest before lifting never glides at all. The threshold is measured in finger travel, so it keeps meaning the same thing when you change Scroll Speed.

### Settings

Tune these under **Preferences → Edge Controls → Edge Scrolling**:

| Setting | Meaning |
|---|---|
| **Scroll Speed** | Points of scroll per millimetre of finger travel (default 26, range 5–80). Lower is more precise; higher covers a long document in a single slide. |
| **Glide after lifting your finger** | Whether a flick coasts to a stop (default on). Turn it off for tighter control over exactly where you land. |
| **Reverse scroll direction** | Off (default) is natural scrolling: sliding up a side edge, or right along a top or bottom edge, moves down the page. On gives the scrollbar convention. |



## The pointer holds still

Edge gestures run on a single contact, which means the finger working the slider is the same one macOS reads as pointer movement. Without intervention the cursor drifts off toward whichever screen edge you are sliding along.

So once an edge gesture takes over, Glide freezes the pointer until you lift. This applies to every edge action, not just scrolling. For scrolling it also decides *where* the scroll lands, since scroll events go to the window under the pointer — freezing it keeps the scroll on the window it started over.

The freeze begins only when the gesture actually commits (see below). A touch near the rim that never commits leaves the cursor completely alone, so nothing is lost if you were only moving the pointer.

Freezing alone is not quite enough, though. The travel that *earned* the commit has already moved the cursor by then, and those events have been delivered — suppression cannot take them back. So on commit Glide also puts the cursor back where your finger first landed. Without that, the pointer still crept a few millimetres' worth on every gesture, which is the drift you would otherwise keep seeing.

## Accidental Trigger Protection

Edge Controls apply several independent filters to separate rim gestures from ordinary pointer navigation. A touch has to pass all of them:

- **Edge-Origin Only:** Touches must start on the outer perimeter. A contact that begins on the main trackpad surface is excluded from edge actions for its entire lifetime, so sweeping into an edge never triggers anything.
- **Rim Proximity, with hysteresis:** The finger must start within the border zone (**Edge Margin Depth**, default 12 mm, adjustable 3–30 mm). Once a gesture has committed it keeps 10 mm more room than that before being dropped — see below.
- **No Corners:** A gesture cannot start in a corner. With any real margin the four edge zones overlap there, so "which edge is this?" has no correct answer — and corners are also where the TrackPoint's corner activation lives. The exclusion is at least 12 mm, always at least as deep as the margin (which is what makes the four zones provably non-overlapping), and grows to clear the TrackPoint's zone when corner activation is in use.
- **Activation Travel:** The finger must slide a minimum distance *along* the edge before anything fires (**Activation Travel**, default 4 mm). This is the main dial if edge controls are triggering when you did not mean them to.
- **Direction Purity:** Travel along the edge must be at least twice any drift across it, so the slide has to run roughly parallel to the rim — within about 27°. A diagonal sweep away from the edge keeps steering the cursor no matter how much along-edge distance it covers, which is the most common source of accidental triggers.
- **Commit Near the Rim:** More than 3 mm of inward drift before committing cancels the gesture outright. The decision gets made close to where your finger landed, rather than after it has wandered.
- **Single-Contact Isolation:** Only single-finger touches are considered. A second finger immediately returns handling to native macOS gestures.

### Easier to keep than to start

Entering a gesture is strict, so edge controls stay out of the way of cursor work. Staying in one is deliberately not, because by then the finger has already proved its intent with a straight slide along the rim, and the cost of being wrong has flipped: a gesture dropped halfway through is worse than one held slightly too long.

This matters more than it sounds. Fingers do not track straight — sliding along a long edge, or along the top where the hand has to reach over, wanders several millimetres inward. If a committed gesture were held to the same threshold it entered on, it would be dropped mid-slide, and because dropping it also releases the pointer, the visible symptom is the cursor lurching back to life partway through the gesture. So a committed gesture gets 10 mm of extra depth.

The `--diag-edges` diagnostic reports this directly, per edge: how close your finger got, what fraction of the slide the gesture was held for, how far inward it drifted while held, and how many times it was dropped mid-slide.

### Tuning it

Both dials live under **Preferences → Edge Controls → Sensitivity & Margin**:

| Setting | Meaning |
|---|---|
| **Edge Margin Depth** | How far inward from the rim a gesture may begin, and how far it may drift before being handed back (default 12 mm, range 3–30 mm). A deeper margin also keeps a long slide alive instead of cancelling partway, which itself shows up as the cursor starting to move again. |
| **Activation Travel** | How far you must slide along an edge before it takes over (default 4 mm, range 2–15 mm). |

If edge controls fire when you did not intend them to, raise **Activation Travel** first — it is the most direct lever. If gestures cancel partway through a slide, raise **Edge Margin Depth**. If they feel slow or reluctant to engage, move both the other way.

Note that raising the margin also deepens the corner exclusion, since the two are tied together to keep the edge zones from overlapping. At the maximum 30 mm margin the left and right edges still leave about 38 mm of usable strip.

---
[← Previous: Troubleshooting](11-troubleshooting.md) · [Back to manual](../USAGE.md)
