import Cocoa
import CoreGraphics

/// The system's own "Move to previous/next space" shortcut, as the user currently
/// has it configured.
///
/// Reaching a window on another Space means asking macOS to change Space, and
/// pressing this shortcut is the only way an ordinary application can do that
/// cleanly. So the real binding has to be read rather than assumed: pressing
/// Control-arrow blindly would do nothing for someone who remapped it, and could
/// fire whatever they bound in its place.
struct MissionControlShortcut {

    let keyCode: CGKeyCode
    let flags: CGEventFlags

    /// One of the two `AppleSymbolicHotKeys` entries, with the binding macOS ships
    /// for it. Both are taken from the settings pane's own table, at
    /// `/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex/Contents/`
    /// `Resources/en.lproj/DefaultShortcutsTable.xml`, which names 79 "Move to
    /// previous space" with key 123 and 81 "Move to next space" with key 124, each
    /// carrying modifier 262144 — Control.
    struct Binding {
        let identifier: String
        let keyCode: CGKeyCode

        static let previous = Binding(identifier: "79", keyCode: 123)
        static let next = Binding(identifier: "81", keyCode: 124)
        static let shippedFlags: CGEventFlags = .maskControl
    }

    /// macOS stores this in place of a key code or character that is not set.
    private static let unboundParameter = 65535

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let hotKeysKey = "AppleSymbolicHotKeys" as CFString

    /// `nil` when the shortcut is switched off or left unbound, in which case
    /// Glide must not try to change Space this way at all.
    static func moveToSpace(next: Bool) -> MissionControlShortcut? {
        let binding = next ? Binding.next : Binding.previous
        return shortcut(for: binding, entry: hotKeyEntry(binding.identifier))
    }

    /// Kept separate from the preference it normally comes from, so the recorded
    /// forms can be exercised without rewriting anyone's keyboard settings.
    static func shortcut(for binding: Binding, entry: [String: Any]?) -> MissionControlShortcut? {
        let shipped = MissionControlShortcut(keyCode: binding.keyCode, flags: Binding.shippedFlags)

        // No entry means the pane has never written one, so the shipped binding is
        // in force. An entry with no recorded parameters means the same: the pane
        // stores only the enabled flag until the binding itself is changed.
        guard let entry else { return shipped }
        if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber],
              parameters.count >= 3 else { return shipped }

        // Recorded as (character, virtual key code, modifier mask).
        let recordedKeyCode = parameters[1].intValue
        guard recordedKeyCode != unboundParameter,
              recordedKeyCode >= 0,
              recordedKeyCode <= Int(UInt16.max) else { return nil }

        return MissionControlShortcut(
            keyCode: CGKeyCode(recordedKeyCode),
            flags: eventFlags(fromModifierMask: parameters[2].uintValue)
        )
    }

    private static func hotKeyEntry(_ identifier: String) -> [String: Any]? {
        // Another process owns this preference, so the local cache has to be dropped
        // or a shortcut changed since Glide launched would go unnoticed.
        CFPreferencesAppSynchronize(domain)
        let stored = CFPreferencesCopyValue(
            hotKeysKey, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) ?? CFPreferencesCopyAppValue(hotKeysKey, domain)
        guard let hotKeys = stored as? [String: Any] else { return nil }
        return hotKeys[identifier] as? [String: Any]
    }

    /// The mask is recorded in `NSEvent`'s vocabulary, which is also where
    /// `CGEventFlags` gets its values — but only the modifiers a shortcut can
    /// actually use are carried over.
    private static func eventFlags(fromModifierMask mask: UInt) -> CGEventFlags {
        let modifiers = NSEvent.ModifierFlags(rawValue: mask)
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
