import SwiftUI

struct GesturesTab: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var selectedRule: GestureRule.ID? = nil

    var body: some View {
        HSplitView {
            // Left: rule list
            VStack(spacing: 0) {
                List(selection: $selectedRule) {
                    ForEach(store.rulesGroupedByFingers(), id: \.fingers) { group in
                        Section("\(group.fingers) Fingers") {
                            ForEach(group.rules) { rule in
                                RuleRow(rule: rule)
                                    .tag(rule.id)
                            }
                            .onDelete { offsets in
                                let ids = group.rules.map(\.id)
                                let storeOffsets = IndexSet(
                                    offsets.compactMap { i in
                                        store.rules.firstIndex { $0.id == ids[i] }
                                    }
                                )
                                store.deleteRules(at: storeOffsets)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

                Divider()

                HStack {
                    Button(action: {
                        let id = store.addRule()
                        selectedRule = id
                    }) {
                        Label("Add Gesture", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .padding(8)

                    Spacer()

                    Text("\(store.rules.filter { !$0.isDraft }.count) gestures")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(8)
                }
            }
            .frame(minWidth: 260, maxWidth: 320)

            // Right: rule editor
            Group {
                if let id = selectedRule,
                   let idx = store.rules.firstIndex(where: { $0.id == id }) {
                    RuleEditor(rule: $store.rules[idx])
                        .id(id)
                } else {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Rule Row

struct RuleRow: View {
    let rule: GestureRule
    @EnvironmentObject var store: PreferencesStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rule.action.iconName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(ruleDisplayLabel(rule))
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(rule.direction.rawValue)
                    if rule.direction != .click {
                        Text("·")
                        Text(rule.speed.rawValue)
                    }
                    if store.isDirectionReservedByAppSwitcher(fingers: rule.fingers, direction: rule.direction,
                                                              modifierFilter: rule.modifierFilter) {
                        Text("·")
                        Image(systemName: "rectangle.2.swap")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !rule.isActive {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .opacity(rule.isActive ? 1 : 0.5)
    }
}

// MARK: - Rule Editor

struct RuleEditor: View {
    @Binding var rule: GestureRule
    @EnvironmentObject var store: PreferencesStore
    @State private var showMenuPicker = false

    private var displayTitle: String {
        if rule.action == .customShortcut, let s = rule.customShortcut, s.isValid {
            return "Shortcut: \(s.displayString)"
        }
        return rule.menuItemLabel ?? rule.action.rawValue
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
            }
            return filtered.isEmpty ? nil : (category, filtered)
        }
    }

    private var supportsContinuousGestures: Bool {
        rule.direction == .swipeLeftRight || rule.direction == .swipeUpDown
    }

    private var reservedBanner: String? {
        guard store.appSwitcher.enabled else { return nil }
        return "Plain 3-finger swipes left/right are reserved for App Switcher. Use a modifier key (e.g. Shift) here to assign a different action on the same swipe."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack {
                    Image(systemName: rule.action.iconName)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(displayTitle)
                            .font(.title2.bold())
                    }
                    Spacer()
                    // Replaced Toggle with a pseudo-enabled check, rule is active if action != .doNothing
                    if store.isRuleShadowed(rule) {
                        Text("Overridden by another rule")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
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

                        if rule.direction != .click {
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
                                if rule.direction != .click {
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

                        if rule.direction != .click {
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
                if rule.isDraft && newValue != .doNothing
                    && newValue != .customMenuItem && newValue != .customShortcut && newValue != .advancedKeyboard {
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

private func ruleDisplayLabel(_ rule: GestureRule) -> String {
    if rule.action == .customShortcut, let s = rule.customShortcut, s.isValid {
        return "Shortcut: \(s.displayString)"
    }
    if rule.action == .advancedKeyboard, !rule.advancedKeyboard.isEmpty {
        return "Advanced Keyboard"
    }
    return rule.menuItemLabel ?? rule.action.rawValue
}

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
