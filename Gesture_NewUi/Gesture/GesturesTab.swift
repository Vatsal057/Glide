import SwiftUI

struct GesturesTab: View {
    @EnvironmentObject var store: GestureStore
    @State private var selectedRule: GestureRule.ID? = nil

    var body: some View {
        HSplitView {
            // Left: rule list
            VStack(spacing: 0) {
                List(selection: $selectedRule) {
                    ForEach(FingerCount.allCases) { fingers in
                        let group = store.rules.filter { $0.fingerCount == fingers }
                        if !group.isEmpty {
                            Section(fingers.label) {
                                ForEach(group) { rule in
                                    RuleRow(rule: rule)
                                        .tag(rule.id)
                                }
                                .onDelete { offsets in
                                    // map section offsets back to store
                                    let ids = group.map(\.id)
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
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

                Divider()

                HStack {
                    Button(action: { store.addRule() }) {
                        Label("Add Gesture", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .padding(8)

                    Spacer()

                    Text("\(store.rules.count) gestures")
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
                    ContentUnavailableView(
                        "No Gesture Selected",
                        systemImage: "hand.draw",
                        description: Text("Select a gesture from the list or click + to add one.")
                    )
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
            Image(systemName: rule.action.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.action.rawValue)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(rule.gestureType.rawValue)
                    if rule.gestureType != .click && rule.gestureType != .forceClick {
                        Text("·")
                        Text(rule.speed.rawValue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !rule.isEnabled {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Rule Editor

struct RuleEditor: View {
    @Binding var rule: GestureRule

    private var categorizedActions: [(String, [GestureAction])] {
        let categories = ["Apps", "Windows", "Screenshots", "Editing", "Media & Display", "System", "Other"]
        return categories.compactMap { cat in
            let actions = GestureAction.allCases.filter { $0.category == cat }
            return actions.isEmpty ? nil : (cat, actions)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack {
                    Image(systemName: rule.action.systemImage)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(rule.action.rawValue)
                            .font(.title2.bold())
                        Text(rule.action.category)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: $rule.isEnabled)
                        .toggleStyle(.switch)
                }
                .padding()
                .background(.quinary)

                Divider()

                VStack(alignment: .leading, spacing: 20) {

                    // Trigger section
                    EditorSection(title: "Trigger") {
                        EditorRow(label: "Fingers") {
                            Picker("", selection: $rule.fingerCount) {
                                ForEach(FingerCount.allCases) { f in
                                    Text(f.label).tag(f)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)
                        }

                        EditorRow(label: "Gesture") {
                            Picker("", selection: $rule.gestureType) {
                                ForEach(GestureType.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .frame(maxWidth: 200)
                        }

                        if rule.gestureType != .click && rule.gestureType != .forceClick {
                            EditorRow(label: "Speed") {
                                Picker("", selection: $rule.speed) {
                                    ForEach(SwipeSpeed.allCases) { s in
                                        Text(s.rawValue).tag(s)
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
                                        ForEach(actions) { action in
                                            Label(action.rawValue, systemImage: action.systemImage)
                                                .tag(action)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: 260)
                        }

                        if rule.action == .openApp {
                            EditorRow(label: "App") {
                                HStack {
                                    Text(rule.targetApp.isEmpty ? "None selected" : rule.targetApp)
                                        .foregroundStyle(rule.targetApp.isEmpty ? .secondary : .primary)
                                    Button("Choose…") {
                                        pickApp()
                                    }
                                }
                            }
                        }
                    }

                    // Conditions section
                    EditorSection(title: "Conditions") {
                        EditorRow(label: "Modifier Key") {
                            Picker("", selection: $rule.modifier) {
                                ForEach(ModifierKey.allCases) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .frame(maxWidth: 200)
                        }

                        EditorRow(label: "Window State") {
                            Picker("", selection: $rule.windowState) {
                                ForEach(WindowState.allCases) { w in
                                    Text(w.rawValue).tag(w)
                                }
                            }
                            .frame(maxWidth: 200)
                        }

                        EditorRow(label: "App Filter") {
                            HStack {
                                TextField("Any app", text: $rule.appFilter)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 200)
                                if !rule.appFilter.isEmpty {
                                    Button("Clear") { rule.appFilter = "" }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        EditorRow(label: "Reciprocal") {
                            Toggle("Reverse gesture undoes this action", isOn: $rule.reciprocal)
                        }
                    }

                } // VStack inside scroll
                .padding()
            } // outer VStack
        } // ScrollView
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            rule.targetApp = panel.url?.lastPathComponent.replacingOccurrences(of: ".app", with: "") ?? ""
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
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}
