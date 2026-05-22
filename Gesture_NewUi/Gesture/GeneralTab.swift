import Combine
import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: GestureStore

    @State private var hasAccessibility: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Accessibility card
                accessibilityCard

                // Behavior section
                GroupBox(label: Label("Behavior", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsRow(label: "Window Targeting") {
                            Picker("", selection: $settings.windowTargetingFocused) {
                                Text("Focused Window First").tag(true)
                                Text("Window Under Cursor First").tag(false)
                            }
                            .frame(maxWidth: 260)
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Haptic Feedback") {
                            Toggle("Vibrate trackpad on gesture recognition", isOn: $settings.hapticFeedback)
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Debug Logging") {
                            Toggle("Write gesture details to Console", isOn: $settings.debugLogging)
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Launch at Login") {
                            Toggle("Start Gesture automatically when you log in", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _ in settings.applyLaunchAtLogin() }
                        }
                    }
                }

                // Stats dashboard
                statsDashboard
            }
            .padding()
        }
        .onAppear { checkAccessibility() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in checkAccessibility() }
    }

    // MARK: - Accessibility Card

    private var accessibilityCard: some View {
        GroupBox(label: Label("Accessibility Permission", systemImage: "hand.raised")) {
            HStack(spacing: 16) {
                Image(systemName: hasAccessibility ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(hasAccessibility ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(hasAccessibility ? "Permission granted" : "Permission required")
                        .font(.headline)
                    Text(hasAccessibility
                         ? "Gesture has all the permissions it needs to intercept trackpad gestures."
                         : "Gesture needs Accessibility access to detect trackpad gestures. Click below to grant it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !hasAccessibility {
                    Button("Open System Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Stats Dashboard

    private var statsDashboard: some View {
        GroupBox(label: Label("Stats", systemImage: "chart.bar")) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(
                    value: "\(store.rules.count)",
                    label: "Total Gestures",
                    icon: "hand.draw",
                    color: .blue
                )
                StatCard(
                    value: "\(store.rules.filter(\.isEnabled).count)",
                    label: "Active Gestures",
                    icon: "bolt",
                    color: .green
                )
                StatCard(
                    value: "\(Set(store.rules.map(\.fingerCount)).count)",
                    label: "Finger Sets Used",
                    icon: "hand.raised",
                    color: .purple
                )
                StatCard(
                    value: "\(store.rules.filter { $0.action == .openApp && $0.targetApp.isEmpty }.count)",
                    label: "Missing Apps",
                    icon: "exclamationmark.triangle",
                    color: .orange
                )
                StatCard(
                    value: "\(store.rules.filter(\.reciprocal).count)",
                    label: "Reciprocal Pairs",
                    icon: "arrow.left.and.right",
                    color: .teal
                )
                StatCard(
                    value: "\(store.rules.filter { $0.modifier != .none }.count)",
                    label: "Modifier Gestures",
                    icon: "command",
                    color: .indigo
                )
            }
            .padding(8)
        }
    }

    private func checkAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
    }
}

// MARK: - Settings Row

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            content()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title.bold())
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - LaunchAtLogin helper (appended)
// Handled via onChange in SettingsRow Toggle; actual SMAppService call is here.
extension AppSettings {
    func applyLaunchAtLogin() {
        // SMAppService is available macOS 13+; guard below keeps it safe on 12.
        if #available(macOS 13.0, *) {
            let svc = ServiceManagement.SMAppService.mainApp
            if launchAtLogin {
                try? svc.register()
            } else {
                try? svc.unregister()
            }
        }
    }
}
