import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import ServiceManagement

@MainActor
final class PreferencesStore: ObservableObject {

    // ── Config I/O feedback ──
    enum ConfigAlert: Equatable {
        case exportSuccess(String)   // path
        case importSuccess
        case error(String)
    }
    @Published var configAlert: ConfigAlert? = nil

    struct RuleDiagnostics {
        var configuredFingerCounts: Int = 0
        var appSpecificRules: Int = 0
        var openAppRulesMissingTarget: Int = 0
        var menuItemRulesMissingTarget: Int = 0
    }

    static let shared = PreferencesStore()

    @Published var rules: [GestureRule] = [] {
        didSet {
            persistRules()
        }
    }
    @Published private(set) var appSwitcher: AppSwitcherSettings = .init()
    @Published private(set) var tuning: GestureTuning = .init()
    @Published private(set) var windowTargetingMode: WindowTargetingMode = .focusedThenCursor
    @Published private(set) var hapticFeedbackEnabled = true
    @Published private(set) var hapticAssignments: [HapticEvent: HapticPattern] = HapticEvent.defaultAssignments
    @Published private(set) var debugLoggingEnabled = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var diagnostics = RuleDiagnostics()
    @Published private(set) var autoDisableNativeGestures = false
    @Published private(set) var nativeConflicts: [SystemGestureManager.Conflict] = []
    @Published private(set) var disabledNativeGestures: [SystemGestureManager.NativeGesture] = []


    private init() { reload() }

    func reload() {
        let s = Settings.shared
        rules = s.rules.map(sanitizedRule)
        appSwitcher = s.appSwitcher
        tuning = s.tuning
        windowTargetingMode = s.windowTargetingMode
        hapticFeedbackEnabled = s.hapticFeedbackEnabled
        hapticAssignments = s.hapticAssignments
        debugLoggingEnabled = s.debugLoggingEnabled
        // The login item can be toggled behind our back in System Settings —
        // SMAppService is the source of truth, the YAML value just mirrors it.
        let actuallyRegistered = SMAppService.mainApp.status == .enabled
        launchAtLoginEnabled = actuallyRegistered
        if s.launchAtLoginEnabled != actuallyRegistered {
            Settings.shared.launchAtLoginEnabled = actuallyRegistered
        }
        refreshAccessibilityStatus()
        diagnostics = buildDiagnostics(for: rules)
        autoDisableNativeGestures = s.autoDisableNativeGestures
        refreshNativeConflicts()
    }

    func refreshAccessibilityStatus() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    @discardableResult
    func addRule() -> UUID {
        let rule = GestureRule.newDraft()
        rules.append(rule)
        return rule.id
    }
    
    func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    func markRuleConfigured(_ ruleID: UUID) {
        guard var rule = rules.first(where: { $0.id == ruleID }), rule.isDraft else { return }
        rule.isDraft = false
        updateRule(rule)
    }

    /// `true` when a newer rule in the list overrides this one (same gesture signature).
    func isRuleShadowed(_ rule: GestureRule) -> Bool {
        guard rule.isActive else { return false }
        guard let winner = rules.last(where: { $0.isActive && $0.matchSignature == rule.matchSignature }) else {
            return false
        }
        return winner.id != rule.id
    }

    func resetRules() {
        rules = Settings.defaultRules.map(sanitizedRule)
    }

    func updateAppSwitcher(_ mutate: (inout AppSwitcherSettings) -> Void) {
        var copy = appSwitcher
        mutate(&copy)
        copy = AppSwitcherSettings.normalized(copy)
        let fingersChanged = copy.enabled && copy.fingers != appSwitcher.fingers
        let turnedOn = copy.enabled && !appSwitcher.enabled
        if copy.enabled && (turnedOn || fingersChanged) {
            var updatedRules = rules
            Settings.stripReservedHorizontalSwipes(from: &updatedRules, fingerCount: copy.fingers)
            rules = updatedRules.map(sanitizedRule)
        }
        Settings.shared.appSwitcher = copy
        appSwitcher = Settings.shared.appSwitcher
        SystemGestureManager.reconcileIfAutoEnabled()
        refreshNativeConflicts()
    }

    /// Horizontal swipes reserved for app switcher on this finger count (when enabled).
    func isDirectionReservedByAppSwitcher(fingers: Int, direction: GestureDirection,
                                          modifierFilter: ModifierFilter = .any) -> Bool {
        guard appSwitcher.enabled, fingers == appSwitcher.fingers else { return false }
        guard direction == .swipeLeft || direction == .swipeRight || direction == .swipeLeftRight else { return false }
        return !modifierFilter.requiresModifierHeld
    }

    func updateRule(_ r: GestureRule) {
        guard let i = rules.firstIndex(where: { $0.id == r.id }) else { return }
        rules[i] = sanitizedRule(r)
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
    }

    @discardableResult
    func duplicateRule(_ id: UUID) -> UUID? {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = rules[idx]
        copy.id = UUID()
        copy.name = "\(copy.displayName) Copy"
        rules.insert(copy, at: idx + 1)
        return copy.id
    }

    func renameRule(_ id: UUID, to newName: String) {
        guard var rule = rules.first(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        rule.name = trimmed.isEmpty ? nil : trimmed
        updateRule(rule)
    }

    func updateWindowTargetingMode(_ m: WindowTargetingMode) {
        windowTargetingMode = m
        Settings.shared.windowTargetingMode = m
    }

    func updateHapticFeedback(_ v: Bool) {
        hapticFeedbackEnabled = v
        Settings.shared.hapticFeedbackEnabled = v
    }

    func updateHapticPattern(_ pattern: HapticPattern, for event: HapticEvent) {
        hapticAssignments[event] = pattern
        Settings.shared.hapticAssignments = hapticAssignments
        HapticEngine.shared.play(pattern)   // let the user feel the choice immediately
    }

    func resetHapticAssignments() {
        hapticAssignments = HapticEvent.defaultAssignments
        Settings.shared.hapticAssignments = hapticAssignments
    }

    func updateDebugLogging(_ v: Bool) {
        debugLoggingEnabled = v
        Settings.shared.debugLoggingEnabled = v
    }

    func updateLaunchAtLogin(_ v: Bool) {
        launchAtLoginEnabled = v
        Settings.shared.launchAtLoginEnabled = v
        do {
            if v {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            AppLogger.debug("[Config] SMAppService error: \(error.localizedDescription)")
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            Settings.shared.launchAtLoginEnabled = launchAtLoginEnabled
        }
    }

    func updateTuning(_ mutate: (inout GestureTuning) -> Void) {
        var copy = tuning
        mutate(&copy)
        Settings.shared.tuning = copy          // Settings.normalizedTuning runs here + saves
        tuning = Settings.shared.tuning        // read back the clamped value
    }

    func resetTuning() {
        Settings.shared.resetTuning()
        tuning = Settings.shared.tuning
    }

    // ── YAML Config Export — copies live file to user-chosen location ──
    func exportConfig() {
        let panel = NSSavePanel()
        panel.title                    = "Export Glide Config"
        panel.nameFieldLabel           = "Save As:"
        panel.nameFieldStringValue     = "glide_config.yaml"
        panel.allowedContentTypes      = [.yaml]
        panel.canCreateDirectories     = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if GlideConfigStore.shared.exportTo(url) {
            configAlert = .exportSuccess(url.lastPathComponent)
        } else {
            configAlert = .error("Export failed — check file permissions.")
        }
    }

    // ── YAML Config Import — loads file, applies, saves to live path ──
    func importConfig() {
        let panel = NSOpenPanel()
        panel.title                   = "Import Glide Config"
        panel.allowedContentTypes     = [.yaml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if GlideConfigStore.shared.importFrom(url) {
            reload()
            configAlert = .importSuccess
        } else {
            configAlert = .error("File is not a valid Glide config.")
        }
    }

    func chooseApp(for ruleID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var rule = rules.first(where: { $0.id == ruleID }) else { return }
        rule.appPath = url.path
        updateRule(rule)
    }

    func setAppFilter(_ bundleID: String?, for ruleID: UUID) {
        guard var rule = rules.first(where: { $0.id == ruleID }) else { return }
        rule.appFilter = bundleID
        updateRule(rule)
    }

    func setWindowStateFilter(_ state: WindowStateFilter, for ruleID: UUID) {
        guard var rule = rules.first(where: { $0.id == ruleID }) else { return }
        rule.windowStateFilter = state
        updateRule(rule)
    }

    func setModifierFilter(_ filter: ModifierFilter, for ruleID: UUID) {
        guard var rule = rules.first(where: { $0.id == ruleID }) else { return }
        rule.modifierFilter = filter
        updateRule(rule)
    }

    func binding(for ruleID: UUID) -> Binding<GestureRule> {
        Binding(
            get: { self.rules.first(where: { $0.id == ruleID }) ?? GestureRule(fingers: 3, direction: .click, action: .doNothing) },
            set: { self.updateRule($0) }
        )
    }

    func runningApps() -> [RunningAppOption] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bid = app.bundleIdentifier else { return nil }
                return RunningAppOption(bundleID: bid, name: app.localizedName ?? bid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func appFilterLabel(for bundleID: String?) -> String {
        guard let bundleID else { return "Any App" }
        return runningApps().first(where: { $0.bundleID == bundleID })?.name
            ?? bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }

    func appLabel(for path: String?) -> String {
        guard let path else { return "Choose App…" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    func menuItemTargetLabel(bundleID: String?) -> String {
        guard let bundleID else { return "Frontmost App" }
        return appFilterLabel(for: bundleID)
    }

    /// Configured rules grouped by finger count (preserves list order within each group).
    func rulesGroupedByFingers() -> [(fingers: Int, rules: [GestureRule])] {
        let configured = rules.filter { !$0.isDraft && !$0.isKeyboardBinding }
        let grouped = Dictionary(grouping: configured) { $0.fingers }
        return grouped.keys.sorted().map { (fingers: $0, rules: grouped[$0]!) }
    }

    /// Keyboard-shortcut bindings (includes drafts so the editor can show them).
    var keyboardRules: [GestureRule] {
        rules.filter { $0.isKeyboardBinding }
    }

    @discardableResult
    func addHotkey() -> UUID {
        let rule = GestureRule.newKeyboardDraft()
        rules.append(rule)
        return rule.id
    }

    private func persistRules() {
        Settings.shared.rules = rules.map(sanitizedRule)
        diagnostics = buildDiagnostics(for: rules)
        HotkeyManager.shared.reload()
        SystemGestureManager.reconcileIfAutoEnabled()
        refreshNativeConflicts()
    }

    // MARK: Native gesture conflicts

    func refreshNativeConflicts() {
        nativeConflicts = SystemGestureManager.currentConflicts(rules: Settings.shared.rules,
                                                                appSwitcher: Settings.shared.appSwitcher)
        disabledNativeGestures = SystemGestureManager.disabledByGlide()
    }

    func reEnableNativeGesture(_ gesture: SystemGestureManager.NativeGesture) {
        SystemGestureManager.reEnableNativeGestures([gesture])
        scheduleConflictRefresh()
    }

    func reEnableAllNativeGestures() {
        SystemGestureManager.reEnableNativeGestures(disabledNativeGestures)
        scheduleConflictRefresh()
    }

    func updateAutoDisableNativeGestures(_ v: Bool) {
        autoDisableNativeGestures = v
        Settings.shared.autoDisableNativeGestures = v
        if v { SystemGestureManager.reconcileIfAutoEnabled() }
        scheduleConflictRefresh()
    }

    func disableNativeConflict(_ conflict: SystemGestureManager.Conflict) {
        SystemGestureManager.disableNativeGestures([conflict.native])
        scheduleConflictRefresh()
    }

    func disableAllNativeConflicts() {
        SystemGestureManager.disableNativeGestures(nativeConflicts.map(\.native))
        scheduleConflictRefresh()
    }

    /// The defaults writes run off-main; re-read after they had a moment to land.
    private func scheduleConflictRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshNativeConflicts()
        }
    }

    /// Same normalization the engine applies, plus: any rule with an action set stops being a draft.
    private func sanitizedRule(_ r: GestureRule) -> GestureRule {
        var copy = Settings.normalizedRule(r)
        if copy.action != .doNothing { copy.isDraft = false }
        return copy
    }

    private func buildDiagnostics(for rules: [GestureRule]) -> RuleDiagnostics {
        RuleDiagnostics(
            configuredFingerCounts: Set(rules.map(\.fingers)).count,
            appSpecificRules: rules.filter { $0.appFilter != nil || $0.windowStateFilter != .any }.count,
            openAppRulesMissingTarget: rules.filter { $0.action == .openApp && (($0.appPath?.isEmpty) != false) }.count,
            menuItemRulesMissingTarget: rules.filter {
                $0.action == .customMenuItem && ($0.menuItemPath == nil || ($0.menuItemPath?.count ?? 0) < 2)
            }.count
        )
    }
}

struct RunningAppOption: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}
