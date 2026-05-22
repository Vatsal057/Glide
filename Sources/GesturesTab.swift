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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rule.action.iconName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.action.rawValue)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(rule.direction.rawValue)
                    if rule.direction != .click {
                        Text("·")
                        Text(rule.speed.rawValue)
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

    private var categorizedActions: [(String, [GestureAction])] {
        GestureAction.catalog.map { ($0.category, $0.actions) }
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
                        Text(rule.action.rawValue)
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
                            Picker("", selection: $rule.direction) {
                                ForEach(GestureDirection.allCases, id: \.self) { t in
                                    Text(t.rawValue.capitalized).tag(t)
                                }
                            }
                            .frame(maxWidth: 200)
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
                        EditorRow(label: "Action") {
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
                                if rule.isDraft && newValue != .doNothing {
                                    store.markRuleConfigured(rule.id)
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
                    }

                    // Conditions section
                    EditorSection(title: "Conditions") {
                        EditorRow(label: "Modifier Key") {
                            Picker("", selection: $rule.modifierFilter) {
                                ForEach(ModifierFilter.allCases, id: \.self) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .frame(maxWidth: 200)
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

                } // VStack inside scroll
                .padding()
            } // outer VStack
        } // ScrollView
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
        // Editing
        case .copy:       return "doc.on.doc"
        case .paste:      return "doc.on.clipboard"
        case .cut:        return "scissors"
        case .undo:       return "arrow.uturn.backward"
        case .redo:       return "arrow.uturn.forward"
        case .selectAll:  return "checkmark.rectangle"
        case .find:       return "magnifyingglass"
        case .emojiPicker: return "face.smiling"
        case .reloadPage: return "arrow.clockwise"
        case .newTab:     return "plus.rectangle"
        // Media & Display
        case .volumeUp:       return "speaker.wave.3"
        case .volumeDown:     return "speaker.wave.1"
        case .mute:           return "speaker.slash"
        case .playPause:      return "playpause"
        case .nextTrack:      return "forward.end"
        case .previousTrack:  return "backward.end"
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
