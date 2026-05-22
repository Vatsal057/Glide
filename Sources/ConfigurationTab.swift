import SwiftUI

struct ConfigurationTab: View {
    @EnvironmentObject var store: PreferencesStore

    private let configPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Glide/config.yaml").path
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Path info
                GroupBox(label: Label("Configuration File", systemImage: "doc.text")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(configPath)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            openConfigFolder()
                        } label: {
                            Label("Open in Finder", systemImage: "folder.badge.questionmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                }

                if let alert = store.configAlert {
                    HStack {
                        switch alert {
                        case .exportSuccess(let path):
                            Label("Exported to \(path)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .importSuccess:
                            Label("Configuration imported successfully.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .error(let msg):
                            Label(msg, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal)
                }

                // Export
                GroupBox(label: Label("Export", systemImage: "square.and.arrow.up")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save a backup copy of your gestures and settings as a `.yaml` file. Share it with other Glide users or keep it as a snapshot.")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        Button("Export Copy…") {
                            store.exportConfig()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                }

                // Import
                GroupBox(label: Label("Import", systemImage: "square.and.arrow.down")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Load a previously exported `.yaml` file to restore a configuration. This will replace your current gestures and settings.")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        Button("Import Config…") {
                            store.importConfig()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                }

                // Reset section
                GroupBox(label: Label("Reset", systemImage: "arrow.counterclockwise")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Restore Glide to its factory default gesture configuration. Your current gestures will be lost.")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        Button("Reset to Defaults…") {
                            let alert = NSAlert()
                            alert.messageText = "Reset to Default Gestures?"
                            alert.informativeText = "This will replace all your gestures with the built-in defaults. This cannot be undone."
                            alert.addButton(withTitle: "Reset")
                            alert.addButton(withTitle: "Cancel")
                            alert.alertStyle = .warning
                            if alert.runModal() == .alertFirstButtonReturn {
                                store.resetRules()
                            }
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                    .padding(8)
                }
            }
            .padding()
        }
        .onChange(of: store.configAlert) { alert in
            if alert != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if store.configAlert == alert {
                        store.configAlert = nil
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openConfigFolder() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let glideDir = support.appendingPathComponent("Glide")
        try? FileManager.default.createDirectory(at: glideDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(glideDir)
    }
}
