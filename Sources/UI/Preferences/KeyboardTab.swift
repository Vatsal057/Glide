import SwiftUI

// ─────────────────────────────────────────────
// MARK: - KeyboardTab
//
// Global keyboard-shortcut bindings: master–detail like GesturesTab, but the
// list holds `isKeyboardBinding` rules and the editor swaps the gesture trigger
// for a shortcut recorder. Registered via HotkeyManager (Carbon hotkeys).
// ─────────────────────────────────────────────

struct KeyboardTab: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var selectedRule: GestureRule.ID? = nil

    var body: some View {
        HSplitView {
            // ── Left: shortcut list ──
            VStack(spacing: 0) {
                List(selection: $selectedRule) {
                    ForEach(store.keyboardRules) { rule in
                        RuleRow(rule: rule)
                            .tag(rule.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    if selectedRule == rule.id { selectedRule = nil }
                                    store.removeRule(rule.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)

                if store.keyboardRules.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No Keyboard Shortcuts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Add global shortcuts to run Glide actions from anywhere.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }

                Divider()

                HStack {
                    Button {
                        selectedRule = store.addHotkey()
                    } label: {
                        Label("Add Shortcut", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    Spacer()
                }
            }
            .frame(minWidth: 280, maxWidth: 340)

            // ── Right: editor ──
            Group {
                if let id = selectedRule,
                   let idx = store.rules.firstIndex(where: { $0.id == id }) {
                    RuleEditor(rule: $store.rules[idx], onDelete: {
                        selectedRule = nil
                        store.removeRule(id)
                    })
                    .id(id)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("Select or add a keyboard shortcut")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
