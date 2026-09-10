[← Back to manual](../USAGE.md)

# Your configuration file

Every gesture, filter, and tuning value is stored in a single plain-text file:

```
~/Library/Application Support/Glide/config.yaml
```

The configuration uses YAML format, making it clean to read and edit directly. Glide's parser handles missing or reordered keys gracefully. **Preferences → Configuration** provides dedicated tools to manage this file:

- **Open in Finder:** Navigates directly to the configuration directory.
- **Export Copy…:** Saves the current setup as a standalone `.yaml` file for backup or sharing across machines.
- **Import Config…:** Loads a previously exported configuration file. If the incoming configuration contains scripted actions (Shell Command, AppleScript, or Run Shortcut), Glide presents a security audit modal detailing the exact commands before applying them.
- **Reset to Defaults…:** Restores the factory starter configuration. Glide prompts for explicit confirmation prior to resetting.

---
[← Previous: General preferences](08-general-preferences.md) · [Back to manual](../USAGE.md) · [Next: Permissions Glide asks for →](10-permissions.md)
