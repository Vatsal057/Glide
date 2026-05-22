import SwiftUI

struct ConfigurationTab: View {
    @EnvironmentObject var store: GestureStore
    @State private var exportMessage: String? = nil
    @State private var importMessage: String? = nil

    private let configPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Gesture/config.yaml").path
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

                // Export
                GroupBox(label: Label("Export", systemImage: "square.and.arrow.up")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save a backup copy of your gestures and settings as a `.yaml` file. Share it with other Gesture users or keep it as a snapshot.")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        if let msg = exportMessage {
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        }

                        Button("Export Copy…") {
                            exportConfig()
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

                        if let msg = importMessage {
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        }

                        Button("Import Config…") {
                            importConfig()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                }

                // Reset section
                GroupBox(label: Label("Reset", systemImage: "arrow.counterclockwise")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Restore Gesture to its factory default gesture configuration. Your current gestures will be lost.")
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
                                store.rules = GestureStore.defaultRules()
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
    }

    // MARK: - Actions

    private func openConfigFolder() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let glideDir = support.appendingPathComponent("Gesture")
        try? FileManager.default.createDirectory(at: glideDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(glideDir)
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "glide-config.yaml"
        panel.allowedContentTypes = [.yaml]
        if panel.runModal() == .OK, let url = panel.url {
            let yaml = generateYAML()
            try? yaml.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Exported to \(url.lastPathComponent)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exportMessage = nil }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            importMessage = "Configuration imported successfully."
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { importMessage = nil }
        }
    }

    private func generateYAML() -> String {
        var lines = ["# Gesture Configuration", "# Generated by Gesture on \(Date())", "gestures:"]
        for rule in store.rules {
            lines.append("  - fingers: \(rule.fingerCount.rawValue)")
            lines.append("    gesture: \(rule.gestureType.rawValue)")
            lines.append("    speed: \(rule.speed.rawValue)")
            lines.append("    action: \(rule.action.rawValue)")
            lines.append("    modifier: \(rule.modifier.rawValue)")
            lines.append("    window_state: \(rule.windowState.rawValue)")
            if !rule.appFilter.isEmpty { lines.append("    app_filter: \(rule.appFilter)") }
            lines.append("    reciprocal: \(rule.reciprocal)")
            lines.append("    enabled: \(rule.isEnabled)")
        }
        return lines.joined(separator: "\n")
    }
}
