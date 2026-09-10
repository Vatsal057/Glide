[← Back to manual](../USAGE.md)

# Your configuration file

Every gesture, filter, and tuning value lives in one plain-text file:

```
~/Library/Application Support/Glide/config.yaml
```

It's YAML, so it's readable and editable by hand if you're comfortable with that — Glide's loader is deliberately lenient about missing or reordered fields. **Preferences → Configuration** gives you tools to manage it without touching a text editor:

- **Open in Finder** — jumps straight to the file's folder.
- **Export Copy…** — saves your current setup as a standalone `.yaml` file. Use this to back up your configuration, or to share your layout with another Glide user (send them the file, they use Import).
- **Import Config…** — loads a previously exported file, replacing your current gestures and settings. If the incoming config has any gesture bound to a scripted action (Shell Command, AppleScript, or Run Shortcut — see [Every action, explained](03-actions.md)), Glide shows you exactly what it would run before you confirm the import.
- **Reset to Defaults…** — restores Glide's built-in starter gestures, discarding your custom ones. This cannot be undone, and Glide asks you to confirm first.

---
[← Previous: General preferences](08-general-preferences.md) · [Back to manual](../USAGE.md) · [Next: Permissions Glide asks for →](10-permissions.md)
