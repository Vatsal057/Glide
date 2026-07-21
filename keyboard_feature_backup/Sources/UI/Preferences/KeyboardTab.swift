import SwiftUI

struct KeyboardTab: View {
    @ObservedObject var store = PreferencesStore.shared
    @State private var selectedRuleID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Global Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button(action: {
                    let id = store.addHotkey()
                    selectedRuleID = id
                }) {
                    Label("Add Shortcut", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            if store.keyboardRules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Keyboard Shortcuts Configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add global shortcuts to execute Glide actions from anywhere.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Add Shortcut") {
                        let id = store.addHotkey()
                        selectedRuleID = id
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.keyboardRules) { rule in
                            RuleEditor(ruleID: rule.id)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
