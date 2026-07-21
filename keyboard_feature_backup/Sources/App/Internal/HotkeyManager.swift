import Cocoa
import Carbon.HIToolbox

// ─────────────────────────────────────────────
// MARK: - HotkeyManager
//
// Registers global keyboard shortcuts (Carbon RegisterEventHotKey) for rules
// flagged `isKeyboardBinding`, and runs their action through the same
// ActionExecutor path gestures use. Carbon hotkeys work for menu-bar (agent)
// apps and consume the combo, so it won't also type into the frontmost app.
// ─────────────────────────────────────────────

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    private var refs: [EventHotKeyRef] = []
    private var ruleByHotkeyID: [UInt32: UUID] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    /// 'GLID' — signature shared by all of Glide's hotkeys.
    private let signature = OSType(0x474C4944)

    /// Rebuilds every registration from the current rule list. Idempotent.
    func reload() {
        installHandlerIfNeeded()
        unregisterAll()
        for rule in Settings.shared.rules where rule.isKeyboardBinding {
            guard rule.isActive, let sc = rule.triggerShortcut else { continue }
            register(rule: rule, shortcut: sc)
        }
    }

    private func register(rule: GestureRule, shortcut sc: KeyboardShortcut) {
        let hotkeyID = nextID
        nextID &+= 1
        let mods = HotkeyTrigger.carbonModifiers(command: sc.command, shift: sc.shift,
                                                 control: sc.control, option: sc.option)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(sc.keyCode), mods,
                                         EventHotKeyID(signature: signature, id: hotkeyID),
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            ruleByHotkeyID[hotkeyID] = rule.id
        } else {
            AppLogger.debug("[Hotkey] register failed for \(sc.displayString) — status \(status)")
        }
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        ruleByHotkeyID.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let id = hkID.id
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.fire(hotkeyID: id) }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    private func fire(hotkeyID: UInt32) {
        guard let ruleID = ruleByHotkeyID[hotkeyID],
              let rule = Settings.shared.rules.first(where: { $0.id == ruleID }),
              rule.isActive,
              GestureRuleResolver.passesContextFilters(rule) else { return }

        Haptic.forRule(rule)
        ActionExecutor.shared.execute(rule.action, appPath: rule.appPath,
                                      menuItemPath: rule.menuItemPath, menuTargetBundleID: rule.appFilter,
                                      customShortcut: rule.customShortcut,
                                      advancedKeyboard: rule.advancedKeyboard,
                                      shortcutName: rule.shortcutName, script: rule.script)
    }
}
