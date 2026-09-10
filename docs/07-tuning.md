[← Back to manual](../USAGE.md)

# Tuning & precision controls

**Preferences → Tuning** provides three calibrated presets (**Relaxed**, **Balanced**, **Precise**) that adjust tracking parameters simultaneously. Fine-tuning is available via individual sliders, with numeric metrics accessible under **Advanced**.

### Recognition
- **Sensitivity:** Travel distance required before a swipe registers. Lower values yield faster response times; higher values require more deliberate movement.
- **Diagonal strictness:** Angle threshold for horizontal and vertical swipes. Higher strictness establishes dead zones along diagonal vectors, ensuring clean separation between directional swipes.

### Accident Protection
The **protection level** slider coordinates multiple validation checks: finger spread tolerance (distinguishing pinches from parallel swipes), movement coherence across contacts, and frame analysis delays prior to direction locking.

### Swipe Speed
Applies to gestures configured with distinct Slow or Fast speed triggers. Two threshold sliders govern classification boundaries for deliberate glides and quick flicks. Two calculation engines are available:
- **Simple:** Evaluates overall average velocity for predictable classification.
- **Classic:** Evaluates peak velocity, acceleration curves, and timing dynamics.

### Repeating Gestures
For continuous gestures (see [Smart filters & conditions](02-filters-and-conditions.md)), this setting adjusts the rate at which repeated actions fire as fingers continue moving.

### Trackpad Regions
- **Edge margins:** Establish border zones along each edge (0 to 20%, configured independently) where touches are excluded from gesture processing. This provides palm and thumb rejection. A **live visual preview** displays touch coordinates in real time: green denotes active tracking, while orange indicates an excluded margin.
- **Force-click zones:** Adjust the dimensional boundaries for corner and perimeter force-click triggers.

---
[← Previous: TrackPoint](06-trackpoint.md) · [Back to manual](../USAGE.md) · [Next: General preferences →](08-general-preferences.md)
