[← Back to manual](../USAGE.md)

# Tuning & precision controls

**Preferences → Tuning** has three presets (**Relaxed**, **Balanced**, **Precise**) that adjust several settings at once — start there, then fine-tune with the sliders below if needed. Everything is described in plain language first, with the raw numeric values available under **Advanced** for anyone who wants exact control.

### Recognition
- **Sensitivity** — how far fingers must travel before a swipe registers. Lower it for a faster response, raise it if gestures trigger by accident.
- **Diagonal strictness** — how close to perfectly horizontal/vertical a swipe must be. Stricter creates "dead zones" along the diagonals so a sloppy diagonal movement doesn't get mistaken for a straight one.

### Accident protection
One combined **protection level** slider that scales several anti-false-positive checks together — how much finger spread cancels a swipe as a pinch, how uniformly your fingers have to move together, and how many initial frames Glide analyzes before committing to a swipe direction.

### Swipe speed
Only matters for gestures set to trigger specifically on a Slow or Fast swipe. Two sliders control how easily a swipe reads as fast (a flick) or as slow (a deliberate glide), plus a choice between two detection methods: **Simple** (one average-speed reading — predictable) or **Classic** (peak speed, acceleration, and timing together — snappier but less consistent).

### Repeating gestures
For continuous gestures (see [Smart filters & conditions](02-filters-and-conditions.md)): one slider sets how rapidly the action repeats as you keep swiping.

### Trackpad regions
- **Edge margins** — shade off a strip along each edge (0–20%, each edge independent) where touches are ignored entirely. This is palm rejection: if your palm or thumb tends to rest near the bottom or side of the pad, widen that edge's margin so it can't start an accidental gesture. A **visual trackpad preview** shows a live dot as you touch the pad — green means active, orange means it landed in an ignored margin.
- **Force-click zones** — the size of each corner/edge zone used by force-click gestures that check *where* on the pad you pressed (e.g. taking a full-screen screenshot from the top-left corner but an area screenshot from the top-right).

---
[← Previous: TrackPoint](06-trackpoint.md) · [Back to manual](../USAGE.md) · [Next: General preferences →](08-general-preferences.md)
