import SwiftUI

// ─────────────────────────────────────────────
// MARK: - GesturesTab
//
// Master–detail: searchable, filterable gesture list on the left,
// full editor on the right. Rules can be renamed, duplicated, deleted.
// ─────────────────────────────────────────────

struct GesturesTab: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var selectedRule: GestureRule.ID? = nil
    @State private var searchText = ""
    @State private var fingerFilter: Int? = nil      // nil = all
    @State private var renameTarget: GestureRule.ID? = nil
    @State private var renameText = ""

    private var visibleGroups: [(fingers: Int, rules: [GestureRule])] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return store.rulesGroupedByFingers().compactMap { group in
            if let f = fingerFilter, group.fingers != f { return nil }
            let rules = q.isEmpty ? group.rules : group.rules.filter {
                $0.displayName.lowercased().contains(q)
                || $0.action.rawValue.lowercased().contains(q)
                || $0.direction.rawValue.lowercased().contains(q)
            }
            return rules.isEmpty ? nil : (fingers: group.fingers, rules: rules)
        }
    }

    var body: some View {
        HSplitView {
            // ── Left: rule list ──
            VStack(spacing: 0) {
                listHeader

                List(selection: $selectedRule) {
                    ForEach(visibleGroups, id: \.fingers) { group in
                        Section {
                            ForEach(group.rules) { rule in
                                RuleRow(rule: rule)
                                    .tag(rule.id)
                                    .contextMenu {
                                        Button("Rename…") { beginRename(rule) }
                                        Button("Duplicate") {
                                            if let newID = store.duplicateRule(rule.id) { selectedRule = newID }
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            if selectedRule == rule.id { selectedRule = nil }
                                            store.removeRule(rule.id)
                                        }
                                    }
                            }
                        } header: {
                            Label("\(group.fingers) Fingers", systemImage: "hand.raised")
                                .font(.caption.bold())
                        }
                    }
                }
                .listStyle(.inset)

                if visibleGroups.isEmpty {
                    listEmptyState
                }

                Divider()

                HStack {
                    Button {
                        let id = store.addRule()
                        searchText = ""; fingerFilter = nil
                        selectedRule = id
                    } label: {
                        Label("Add Gesture", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .padding(8)

                    Spacer()

                    Text("\(store.rules.filter(\.isActive).count) active · \(store.rules.filter { !$0.isDraft }.count) total")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(8)
                }
            }
            .frame(minWidth: 280, maxWidth: 340)

            // ── Right: rule editor ──
            Group {
                if let id = selectedRule,
                   let idx = store.rules.firstIndex(where: { $0.id == id }) {
                    RuleEditor(rule: $store.rules[idx], onDelete: {
                        selectedRule = nil
                        store.removeRule(id)
                    }, onDuplicate: {
                        if let newID = store.duplicateRule(id) { selectedRule = newID }
                    })
                    .id(id)
                } else {
                    editorEmptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Rename Gesture", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renameTarget { store.renameRule(id, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Give this gesture a name you'll recognize, like “Zoom out in Photos”. Leave empty to go back to the automatic name.")
        }
    }

    private func beginRename(_ rule: GestureRule) {
        renameText = rule.name ?? ""
        renameTarget = rule.id
    }

    // MARK: List chrome

    private var listHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search gestures", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

            Picker("", selection: $fingerFilter) {
                Text("All").tag(Int?.none)
                Text("3").tag(Int?.some(3))
                Text("4").tag(Int?.some(4))
                Text("5").tag(Int?.some(5))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(10)
    }

    private var listEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "hand.draw" : "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No gestures yet" : "No matches")
                .font(.headline)
            Text(searchText.isEmpty
                 ? "Click Add Gesture to create your first one."
                 : "Try a different search or filter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Gesture Selected")
                .font(.title2)
            Text("Select a gesture from the list or click + to add one.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rule Row

struct RuleRow: View {
    let rule: GestureRule
    @EnvironmentObject var store: PreferencesStore

    private var subtitle: String {
        var parts: [String] = [rule.direction.rawValue]
        if rule.direction == .forceClick && rule.zone != .any {
            parts.append(rule.zone.rawValue)
        }
        if rule.direction.hasSpeed && rule.speed != .any {
            parts.append(rule.speed.rawValue)
        }
        if rule.modifierFilter.requiresModifierHeld {
            parts.append(rule.modifierFilter.rawValue)
        }
        if rule.appFilter != nil {
            parts.append(store.appFilterLabel(for: rule.appFilter))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rule.action.iconName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if store.isRuleShadowed(rule) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help("Overridden by another gesture with the same trigger")
            }
            if !rule.isActive {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .help(rule.isDraft ? "Not configured yet" : "Inactive")
            }
        }
        .padding(.vertical, 3)
        .opacity(rule.isActive ? 1 : 0.55)
    }
}

// MARK: - Rule Editor

struct RuleEditor: View {
    @Binding var rule: GestureRule
    var onDelete: () -> Void = {}
    var onDuplicate: () -> Void = {}
    @EnvironmentObject var store: PreferencesStore
    @State private var showMenuPicker = false

    private var autoName: String {
        var copy = rule
        copy.name = nil
        return copy.displayName
    }

    private var categorizedActions: [(String, [GestureAction])] {
        GestureAction.catalog.map { category, actions in
            (category, actions.filter { !Settings.isAppSwitcherAction($0) })
        }
    }

    private var continuousActions: [(String, [GestureAction])] {
        categorizedActions.compactMap { category, actions in
            let filtered = actions.filter {
                $0 != .openApp && $0 != .customMenuItem
                    && $0 != .runShortcut && $0 != .runShellCommand && $0 != .runAppleScript
            }
            return filtered.isEmpty ? nil : (category, filtered)
        }
    }

    private var supportsContinuousGestures: Bool {
        rule.direction == .swipeLeftRight || rule.direction == .swipeUpDown
    }

    private var reservedBanner: String? {
        guard store.appSwitcher.enabled else { return nil }
        return "Plain \(store.appSwitcher.fingers)-finger swipes left/right are reserved for App Switcher. Use a modifier key (e.g. Shift) here to assign a different action on the same swipe."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header: glyph + editable name + actions ──
                HStack(spacing: 12) {
                    Image(systemName: rule.action.iconName)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        TextField(autoName, text: Binding(
                            get: { rule.name ?? "" },
                            set: { newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                rule.name = trimmed.isEmpty ? nil : newValue
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.title2.bold())

                        Text(rule.name == nil ? "Type to name this gesture" : autoName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if store.isRuleShadowed(rule) {
                        Text("Overridden by another rule")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        onDuplicate()
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Duplicate gesture")

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete gesture")
                }
                .padding()
                .background(.quinary)

                Divider()

                if let banner = reservedBanner,
                   store.isDirectionReservedByAppSwitcher(fingers: rule.fingers, direction: rule.direction,
                                                          modifierFilter: rule.modifierFilter) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.2.swap")
                            .foregroundStyle(.orange)
                        Text(banner)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }

                VStack(alignment: .leading, spacing: 20) {

                    // Trigger section
                    EditorSection(title: "Trigger") {
                      if rule.isKeyboardBinding {
                        EditorRow(label: "Shortcut") {
                            VStack(alignment: .leading, spacing: 6) {
                                ShortcutRecorderView(shortcut: $rule.triggerShortcut)
                                if rule.triggerShortcut != nil && !rule.triggerIsRegisterable {
                                    Text("Choose a key together with at least one modifier (⌘ ⌥ ⌃ ⇧).")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("Press this combination anywhere to run the action. It's captured globally, so avoid combos other apps rely on.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onChange(of: rule.triggerShortcut) { _ in
                            if rule.triggerIsRegisterable && rule.action != .doNothing {
                                store.markRuleConfigured(rule.id)
                            }
                        }
                      } else {
                        EditorRow(label: "Fingers") {
                            Picker("", selection: $rule.fingers) {
                                ForEach(3...5, id: \.self) { f in
                                    Text("\(f) Fingers").tag(f)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)
                        }

                        EditorRow(label: "Gesture") {
                            let availableDirections = GestureDirection.allCases.filter {
                                !store.isDirectionReservedByAppSwitcher(fingers: rule.fingers, direction: $0,
                                                                      modifierFilter: rule.modifierFilter)
                            }
                            Picker("", selection: $rule.direction) {
                                ForEach(availableDirections, id: \.self) { t in
                                    Text(t.rawValue.capitalized).tag(t)
                                }
                            }
                            .frame(maxWidth: 200)
                            .onChange(of: rule.fingers) { _ in
                                if store.isDirectionReservedByAppSwitcher(fingers: rule.fingers, direction: rule.direction,
                                                                          modifierFilter: rule.modifierFilter),
                                   let fallback = availableDirections.first {
                                    rule.direction = fallback
                                }
                            }
                            .onChange(of: rule.modifierFilter) { _ in
                                if store.isDirectionReservedByAppSwitcher(fingers: rule.fingers, direction: rule.direction,
                                                                          modifierFilter: rule.modifierFilter),
                                   let fallback = availableDirections.first {
                                    rule.direction = fallback
                                }
                            }
                            .onChange(of: rule.direction) { _ in
                                if !supportsContinuousGestures {
                                    rule.continuous = false
                                }
                            }
                        }

                        if rule.direction.hasSpeed {
                            EditorRow(label: "Speed") {
                                Picker("", selection: $rule.speed) {
                                    ForEach(GestureSpeed.allCases, id: \.self) { s in
                                        Text(s.rawValue.capitalized).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 240)
                            }
                        }

                        if rule.direction == .forceClick {
                            EditorRow(label: "Trackpad Zone") {
                                Picker("", selection: $rule.zone) {
                                    ForEach(TrackpadZone.allCases, id: \.self) { z in
                                        Text(z.rawValue).tag(z)
                                    }
                                }
                                .frame(maxWidth: 200)
                            }
                        }
                      }
                    }

                    // Action section
                    EditorSection(title: "Action") {
                        if rule.continuous && supportsContinuousGestures {
                            EditorRow(label: "Action") {
                                Text("Configured in Continuous Gestures")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            primaryActionEditor(label: "Action")
                        }

                        if supportsContinuousGestures {
                            EditorRow(label: "Continuous Gestures") {
                                Toggle("Continuous gestures", isOn: $rule.continuous)
                                    .onChange(of: rule.continuous) { enabled in
                                        if enabled {
                                            rule.reciprocalEnabled = false
                                            rule.reciprocalAction = nil
                                        }
                                    }
                            }
                        }

                        EditorRow(label: "Haptic") {
                            Picker("", selection: Binding<HapticPattern?>(
                                get: { rule.hapticPattern },
                                set: { newValue in
                                    rule.hapticPattern = newValue
                                    if let p = newValue { HapticEngine.shared.play(p) }
                                })) {
                                Text("Automatic (by action)").tag(HapticPattern?.none)
                                Divider()
                                ForEach(HapticPattern.allCases, id: \.self) { pattern in
                                    Text(pattern.displayName).tag(HapticPattern?.some(pattern))
                                }
                            }
                            .frame(maxWidth: 200)
                        }
                    }

                    if rule.continuous && supportsContinuousGestures {
                        EditorSection(title: "Continuous Gestures") {
                            primaryActionEditor(label: "Begin Action")

                            phaseActionEditor(
                                label: "Update + Action",
                                action: $rule.continuousPositiveAction,
                                shortcut: $rule.continuousPositiveShortcut,
                                keyboard: $rule.continuousPositiveKeyboard
                            )

                            phaseActionEditor(
                                label: "Update - Action",
                                action: $rule.continuousNegativeAction,
                                shortcut: $rule.continuousNegativeShortcut,
                                keyboard: $rule.continuousNegativeKeyboard
                            )

                            phaseActionEditor(
                                label: "End Action",
                                action: $rule.continuousEndAction,
                                shortcut: $rule.continuousEndShortcut,
                                keyboard: $rule.continuousEndKeyboard
                            )
                        }
                    }

                    // Conditions section
                    EditorSection(title: "Conditions") {
                        EditorRow(label: "Modifier Key") {
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("", selection: $rule.modifierFilter) {
                                    ForEach(ModifierFilter.allCases, id: \.self) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                                .frame(maxWidth: 200)
                                if !rule.direction.isClickLike {
                                    Text("Hold this modifier when starting the gesture. Example: Shift + 3-finger swipe right → Cycle Windows (⌘`).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        EditorRow(label: "Window State") {
                            Picker("", selection: $rule.windowStateFilter) {
                                ForEach(WindowStateFilter.allCases, id: \.self) { w in
                                    Text(w.rawValue).tag(w)
                                }
                            }
                            .frame(maxWidth: 200)
                        }

                        EditorRow(label: "App Filter") {
                            Picker("", selection: $rule.appFilter) {
                                Text("Any App").tag(String?.none)
                                Divider()
                                ForEach(store.runningApps()) { app in
                                    Text(app.name).tag(String?.some(app.bundleID))
                                }
                            }
                            .frame(maxWidth: 200)
                        }

                        if rule.direction.hasSpeed {
                            if !rule.continuous {
                                EditorRow(label: "Reciprocal") {
                                    Toggle("Reverse gesture undoes this action", isOn: $rule.reciprocalEnabled)
                                }

                                if rule.reciprocalEnabled {
                                    EditorRow(label: "Reverse Action") {
                                        Picker("", selection: Binding<GestureAction>(
                                            get: { rule.reciprocalAction ?? rule.action.inverseAction ?? .doNothing },
                                            set: { rule.reciprocalAction = $0 }
                                        )) {
                                            ForEach(categorizedActions, id: \.0) { cat, actions in
                                                Section(cat) {
                                                    ForEach(actions, id: \.self) { action in
                                                        Label(action.rawValue, systemImage: action.iconName)
                                                            .tag(action)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxWidth: 260)
                                    }
                                }
                            }
                        }
                    }

                } // VStack inside scroll
                .padding()
            } // outer VStack
        } // ScrollView
    }

    @ViewBuilder
    private func primaryActionEditor(label: String) -> some View {
        EditorRow(label: label) {
            Picker("", selection: $rule.action) {
                ForEach(categorizedActions, id: \.0) { cat, actions in
                    Section(cat) {
                        ForEach(actions, id: \.self) { action in
                            Label(action.rawValue, systemImage: action.iconName)
                                .tag(action)
                        }
                    }
                }
            }
            .frame(maxWidth: 260)
            .onChange(of: rule.action) { newValue in
                if newValue == .customMenuItem {
                    rule.menuItemPath = nil
                }
                if newValue == .customShortcut {
                    rule.customShortcut = nil
                }
                if newValue == .advancedKeyboard {
                    rule.advancedKeyboard = []
                }
                if newValue == .runShortcut {
                    rule.shortcutName = nil
                }
                if newValue == .runShellCommand || newValue == .runAppleScript {
                    rule.script = nil
                }
                if rule.isDraft && newValue != .doNothing
                    && newValue != .customMenuItem && newValue != .customShortcut && newValue != .advancedKeyboard
                    && newValue != .runShortcut && newValue != .runShellCommand && newValue != .runAppleScript {
                    store.markRuleConfigured(rule.id)
                }
            }
        }

        if rule.action == .customMenuItem {
            EditorRow(label: "Target App") {
                Picker("", selection: Binding<String?>(
                    get: { rule.appFilter },
                    set: { rule.appFilter = $0 }
                )) {
                    Text("Frontmost App").tag(String?.none)
                    Divider()
                    ForEach(store.runningApps()) { app in
                        Text(app.name).tag(String?.some(app.bundleID))
                    }
                }
                .frame(maxWidth: 260)
            }

            EditorRow(label: "Menu Item") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(rule.menuItemLabel ?? "Not selected")
                        .foregroundStyle(rule.menuItemPath == nil ? .secondary : .primary)
                    Button("Choose Menu Item…") {
                        showMenuPicker = true
                    }
                    Text("The app must be running. Glide reads its menu bar, like assigning shortcuts in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showMenuPicker) {
                MenuItemPickerSheet(
                    bundleID: rule.appFilter,
                    targetLabel: store.menuItemTargetLabel(bundleID: rule.appFilter),
                    selectedPath: $rule.menuItemPath
                )
                .onDisappear {
                    if rule.menuItemPath != nil {
                        store.markRuleConfigured(rule.id)
                    }
                }
            }
        }

        if rule.action == .openApp {
            EditorRow(label: "App") {
                HStack {
                    Text(store.appLabel(for: rule.appPath))
                        .foregroundStyle(rule.appPath == nil ? .secondary : .primary)
                    Button("Choose…") {
                        store.chooseApp(for: rule.id)
                    }
                }
            }
        }

        if rule.action == .customShortcut {
            EditorRow(label: "Shortcut") {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRecorderView(shortcut: $rule.customShortcut)
                    Text("Records the key combination Glide will send when this gesture fires.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: rule.customShortcut) { _ in
                if rule.customShortcut?.isValid == true {
                    store.markRuleConfigured(rule.id)
                }
            }
        }

        if rule.action == .advancedKeyboard {
            EditorRow(label: "Advanced Keyboard") {
                KeyboardSequenceEditor(steps: $rule.advancedKeyboard)
            }
        }

        if rule.action == .runShortcut {
            EditorRow(label: "Shortcut Name") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Exact name from Shortcuts.app", text: Binding(
                        get: { rule.shortcutName ?? "" },
                        set: { rule.shortcutName = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit {
                        if rule.shortcutName != nil { store.markRuleConfigured(rule.id) }
                    }
                    Text("Runs the shortcut via Shortcuts.app when the gesture fires.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: rule.shortcutName) { _ in
                if !(rule.shortcutName ?? "").isEmpty { store.markRuleConfigured(rule.id) }
            }
        }

        if rule.action == .runShellCommand || rule.action == .runAppleScript {
            EditorRow(label: rule.action == .runShellCommand ? "Command" : "Script") {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: Binding(
                        get: { rule.script ?? "" },
                        set: { rule.script = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 380, minHeight: 60, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Text(rule.action == .runShellCommand
                         ? "Runs with /bin/zsh -c in the background."
                         : "Runs with osascript in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: rule.script) { _ in
                if !(rule.script ?? "").isEmpty { store.markRuleConfigured(rule.id) }
            }
        }
    }

    private func phaseActionEditor(
        label: String,
        action: Binding<GestureAction>,
        shortcut: Binding<KeyboardShortcut?>,
        keyboard: Binding<[KeyboardInputStep]>
    ) -> some View {
        EditorRow(label: label) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: action) {
                    ForEach(continuousActions, id: \.0) { cat, actions in
                        Section(cat) {
                            ForEach(actions, id: \.self) { action in
                                Label(action.rawValue, systemImage: action.iconName)
                                    .tag(action)
                            }
                        }
                    }
                }
                .frame(maxWidth: 260)

                if action.wrappedValue == .customShortcut {
                    ShortcutRecorderView(shortcut: shortcut)
                }

                if action.wrappedValue == .advancedKeyboard {
                    KeyboardSequenceEditor(steps: keyboard)
                }
            }
        }
    }
}

// MARK: - Keyboard Sequence Editor

struct KeyboardSequenceEditor: View {
    @Binding var steps: [KeyboardInputStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if steps.isEmpty {
                Text("No keyboard input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($steps) { $step in
                    KeyboardStepRow(step: $step) {
                        steps.removeAll { $0.id == step.id }
                    }
                }
            }

            Button {
                steps.append(KeyboardInputStep())
            } label: {
                Label("Add Keyboard Step", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct KeyboardStepRow: View {
    @Binding var step: KeyboardInputStep
    let onDelete: () -> Void

    private var shortcutBinding: Binding<KeyboardShortcut?> {
        Binding(
            get: {
                KeyboardShortcut(
                    keyCode: step.keyCode,
                    command: step.event == .tap && step.command,
                    shift: step.event == .tap && step.shift,
                    control: step.event == .tap && step.control,
                    option: step.event == .tap && step.option
                )
            },
            set: { shortcut in
                guard let shortcut else { return }
                step.keyCode = shortcut.keyCode
                if step.event == .tap {
                    step.command = shortcut.command
                    step.shift = shortcut.shift
                    step.control = shortcut.control
                    step.option = shortcut.option
                } else {
                    step.command = false
                    step.shift = false
                    step.control = false
                    step.option = false
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $step.event) {
                ForEach(KeyboardInputEvent.allCases, id: \.self) { event in
                    Text(event.label).tag(event)
                }
            }
            .frame(width: 92)

            ShortcutRecorderView(shortcut: shortcutBinding)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
    }
}

// MARK: - Menu Item Picker

struct MenuItemPickerSheet: View {
    let bundleID: String?
    let targetLabel: String
    @Binding var selectedPath: [String]?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var options: [MenuItemOption] = []
    @State private var failureReason: String?
    @State private var didLoad = false

    private var filtered: [MenuItemOption] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return options }
        return options.filter { $0.displayTitle.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Menu Item")
                .font(.headline)

            Text("Target: \(targetLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !didLoad {
                ProgressView("Loading menus…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if options.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Menu Items Found")
                        .font(.headline)
                    Text(failureReason ?? "Open \(targetLabel) and try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { option in
                    Button {
                        selectedPath = option.path
                        dismiss()
                    } label: {
                        Text(option.displayTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Refresh") { reload() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 520, height: 440)
        .onAppear { reload() }
    }

    private func reload() {
        didLoad = false
        failureReason = nil
        let bundle = bundleID
        Task {
            let result = await MenuItemCatalog.scanAsync(bundleID: bundle)
            options = result.options
            failureReason = result.failureReason
            didLoad = true
        }
    }
}

// MARK: - Helpers

struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct EditorRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            content()
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// Add an extension for icon names based on GestureAction.
extension GestureAction {
    var iconName: String {
        switch self {
        // App control
        case .quitApp:            return "power"
        case .forceQuitApp:       return "xmark.octagon"
        case .quitFrontmost:      return "stop.circle"
        case .hideApp:            return "eye.slash"
        case .hideOthers:         return "eye.slash.fill"
        case .openApp:            return "app"
        case .appSwitcherNext:    return "arrow.right.square"
        case .appSwitcherPrev:    return "arrow.left.square"
        case .switchAppNext:      return "chevron.right.circle"
        case .switchAppPrev:      return "chevron.left.circle"
        case .customMenuItem:     return "list.bullet.rectangle"
        case .customShortcut:     return "keyboard"
        case .advancedKeyboard:   return "keyboard.badge.ellipsis"
        case .runShortcut:        return "square.2.layers.3d"
        case .runShellCommand:    return "terminal"
        case .runAppleScript:     return "applescript"
        // Window management
        case .minimizeWindow:     return "minus.square"
        case .minimizeAllApps:    return "minus.square.fill"
        case .restoreMinimizedApps: return "square.stack"
        case .maximizeWindow:     return "plus.square"
        case .restoreWindow:      return "arrow.down.right.and.arrow.up.left"
        case .closeWindow:        return "xmark.square"
        case .enterFullscreen:    return "arrow.up.backward.and.arrow.down.forward"
        case .exitFullscreen:     return "arrow.down.right.and.arrow.up.left.square"
        case .toggleFullscreen:   return "arrow.up.left.and.arrow.down.right"
        case .cycleWindows:       return "rectangle.on.rectangle"
        case .snapLeft:           return "rectangle.lefthalf.inset.filled"
        case .snapRight:          return "rectangle.righthalf.inset.filled"
        case .snapTopLeft:        return "rectangle.leadingthird.inset.filled"
        case .snapTopRight:       return "rectangle.trailingthird.inset.filled"
        case .snapBottomLeft:     return "square.bottomthird.inset.filled"
        case .snapBottomRight:    return "square.leadingthird.inset.filled"
        case .centerWindow:       return "square.center.inset.filled"
        case .moveNextDisplay:    return "display.2"
        // Mission Control
        case .missionControl:     return "rectangle.3.group"
        case .appExpose:          return "uiwindow.split.2x1"
        case .showDesktop:        return "macwindow"
        case .launchpad:          return "square.grid.3x3"
        // Screenshots
        case .screenshotArea:           return "viewfinder"
        case .screenshotFull:           return "camera"
        case .screenshotAreaClipboard:  return "viewfinder.circle"
        case .screenshotFullClipboard:  return "camera.fill"
        case .screenshotToolbar:        return "camera.viewfinder"
        // Media & display
        case .playPause:      return "playpause"
        case .nextTrack:      return "forward.end"
        case .previousTrack:  return "backward.end"
        case .volumeUp:       return "speaker.wave.3"
        case .volumeDown:     return "speaker.wave.1"
        case .muteToggle:     return "speaker.slash"
        case .brightnessUp:   return "sun.max"
        case .brightnessDown: return "sun.min"
        // System
        case .spotlight:    return "magnifyingglass.circle"
        case .notifCenter:  return "bell"
        case .lockScreen:   return "lock"
        case .sleep:        return "moon"
        case .emptyTrash:   return "trash"
        case .openFinder:   return "folder"
        case .openDownloads: return "arrow.down.circle"
        // Other
        case .doNothing:    return "slash.circle"
        }
    }
}
