# Changelog

## 2.4.0

### Gestures

- Added individual enable/disable toggle switches for each gesture.
- Disabled gestures are retained in configuration and YAML exports without matching trackpad events.
- Integrated switches directly into the gesture list rows and the gesture detail editor in Preferences.

## 2.3.0

Performance release. The app switcher used to be the most expensive thing Glide
did; it is now roughly seven times cheaper, and the app wakes the CPU far less
when you are not touching the trackpad.

### App switcher CPU

Holding a swipe through the switcher was measured at about **67 ms of CPU per
selection step** with five apps open — well over half a core for as long as the
swipe lasted, and worse the more apps you had running. It is now about
**9.5 ms per step**.

The cause was SwiftUI spring animations on the panel. A spring re-renders the
view it is attached to on every display frame for as long as it runs, and
selection steps arrive every 100 ms (`appSwitcherDebounce`) while a spring takes
roughly 500 ms to settle — so the curves overlapped and the panel re-laid out
continuously for the whole gesture. One of those springs was attached to the
entire panel, so it animated the layout of the app rail, the window shelf, every
card, and the glass measurement together.

Shortening the curves did not help, because the cost is per animated layout
pass rather than per second of animation. Removing them did.

- Selection now applies instantly, as the system ⌘-Tab panel and AltTab both do.
  Cards still scale when selected; the change just is not tweened.
- **New setting: Preferences → App Switcher → Presentation → "Animate
  selection"**, off by default.
  Turn it on to get the springs back, at roughly double the CPU per step.
  Accessibility's *Reduce Motion* still disables them regardless.

Also in the switcher:

- Glass slab frames are snapped to whole points. They were arriving from a
  SwiftUI `GeometryReader` mid-animation carrying values like
  `160.44298885476712`, changing in the low bits every layout pass, and each
  distinct frame made the WindowServer rebuild its glass.
- The window shelf's glass view is now reused and hidden rather than destroyed
  and rebuilt. It appears and disappears whenever the selection crosses between
  a single-window app and a multi-window one, which is most steps, and building
  an `NSGlassEffectView` makes the WindowServer stand up a whole glass surface.
- Rail icons are rasterised once per app and cached. Every open previously
  redrew a 320x320 bitmap for every running app, synchronously, before the panel
  could appear.

### Battery

- The event-tap health check was a 5 second repeating timer created once at
  launch and never invalidated — about 17,000 wake-ups a day, and it kept firing
  even with gestures switched off or the machine asleep. It now lives and dies
  with the gesture engine and runs every 30 seconds with generous slack, so
  macOS can fold it into a wake it was already making.
- The Accessibility permission poll no longer runs forever. It polls briskly for
  the first minute after launch, then stops; a later grant is still picked up by
  the existing `didBecomeActive` observer.
- The TrackPoint's 120 Hz cursor timer now suspends itself while your finger
  rests inside the dead zone and resumes the moment you push back out. A steady
  push is unaffected, so the cursor still glides without depending on new
  frames.
- The global mouse-up handler no longer schedules main-queue work on every click
  system-wide while the engine is stopped.

Idle CPU with the engine running and no input measures 0.07%.
