import Combine
import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @EnvironmentObject var store: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Accessibility card
                accessibilityCard

                // Behavior section
                GroupBox(label: Label("Behavior", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsRow(label: "Window Targeting") {
                            Picker("", selection: Binding(get: { store.windowTargetingMode == .focusedThenCursor }, set: { b in store.updateWindowTargetingMode(b ? .focusedThenCursor : .cursorThenFocused) })) {
                                Text("Focused Window First").tag(true)
                                Text("Window Under Cursor First").tag(false)
                            }
                            .frame(maxWidth: 260)
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Debug Logging") {
                            Toggle("Write gesture details to Console", isOn: Binding(get: { store.debugLoggingEnabled }, set: store.updateDebugLogging))
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Launch at Login") {
                            Toggle("Start Glide automatically when you log in", isOn: Binding(get: { store.launchAtLoginEnabled }, set: store.updateLaunchAtLogin))
                        }
                    }
                }

                // Haptics
                hapticsCard

                // Native gesture conflicts
                nativeGesturesCard

                // Stats dashboard
                statsDashboard

                // About
                aboutCard
            }
            .padding()
        }
        .onAppear { store.reload() }
    }

    // MARK: - Accessibility Card

    private var accessibilityCard: some View {
        GroupBox(label: Label("Accessibility Permission", systemImage: "hand.raised")) {
            HStack(spacing: 16) {
                Image(systemName: store.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(store.accessibilityGranted ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.accessibilityGranted ? "Permission granted" : "Permission required")
                        .font(.headline)
                    Text(store.accessibilityGranted
                         ? "Glide has all the permissions it needs to intercept trackpad gestures."
                         : "Glide needs Accessibility access to detect trackpad gestures. Click below to grant it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !store.accessibilityGranted {
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

    // MARK: - Haptics

    private var hapticsCard: some View {
        GroupBox(label: Label("Haptics", systemImage: "waveform")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Haptic Feedback") {
                    Toggle("Vibrate trackpad on gesture recognition", isOn: Binding(get: { store.hapticFeedbackEnabled }, set: store.updateHapticFeedback))
                }

                ForEach(HapticEvent.allCases, id: \.self) { event in
                    Divider().padding(.leading, 12)
                    SettingsRow(label: event.displayName) {
                        Picker("", selection: Binding(
                            get: { store.hapticAssignments[event] ?? event.defaultPattern },
                            set: { store.updateHapticPattern($0, for: event) })) {
                            ForEach(HapticPattern.allCases, id: \.self) { pattern in
                                Text(pattern.displayName).tag(pattern)
                            }
                        }
                        .frame(maxWidth: 200)
                        .disabled(!store.hapticFeedbackEnabled)
                    }
                }

                Divider().padding(.leading, 12)
                HStack {
                    Text("Selecting a pattern plays it on the trackpad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults") { store.resetHapticAssignments() }
                        .disabled(!store.hapticFeedbackEnabled)
                }
                .padding(12)
            }
        }
    }

    // MARK: - Native Gesture Conflicts

    private var nativeGesturesCard: some View {
        GroupBox(label: Label("macOS Gesture Conflicts", systemImage: "exclamationmark.arrow.triangle.2.circlepath")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Auto-Disable") {
                    Toggle("Turn off macOS gestures that collide with Glide gestures",
                           isOn: Binding(get: { store.autoDisableNativeGestures },
                                         set: store.updateAutoDisableNativeGestures))
                }

                if store.nativeConflicts.isEmpty {
                    Divider().padding(.leading, 12)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("No conflicts — no active macOS gesture shares a trigger with your Glide gestures.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                } else {
                    ForEach(store.nativeConflicts) { conflict in
                        Divider().padding(.leading, 12)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conflict.native.title)
                                    .font(.callout.weight(.medium))
                                Text("Collides with: \(conflict.glideTriggers.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if !conflict.native.appliesWithoutLogout {
                                    Text("May need a log out & back in to fully take effect.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button("Disable") { store.disableNativeConflict(conflict) }
                                .help("Turns the native macOS gesture off (restarts the Dock)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    if store.nativeConflicts.count > 1 {
                        Divider().padding(.leading, 12)
                        HStack {
                            Spacer()
                            Button("Disable All Native Conflicts") { store.disableAllNativeConflicts() }
                        }
                        .padding(12)
                    }
                }

                // ── Re-enable anything Glide turned off ──
                if !store.disabledNativeGestures.isEmpty {
                    Divider().padding(.leading, 12)
                    HStack {
                        Text("Disabled by Glide")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if store.disabledNativeGestures.count > 1 {
                            Button("Re-enable All") { store.reEnableAllNativeGestures() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ForEach(store.disabledNativeGestures) { gesture in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "slash.circle")
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(gesture.title)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Re-enable") { store.reEnableNativeGesture(gesture) }
                                .help("Restores the native macOS gesture to how it was before Glide disabled it")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        GroupBox(label: Label("About", systemImage: "info.circle")) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glide \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.headline)
                    Text("Free and open source. Everything stays on your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Welcome Tour") {
                    OnboardingController.shared.show()
                }
                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Vatsal057/Glide")!)
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
                    value: "\(store.rules.filter(\.isActive).count)",
                    label: "Active Gestures",
                    icon: "bolt",
                    color: .green
                )
                StatCard(
                    value: "\(store.diagnostics.configuredFingerCounts)",
                    label: "Finger Sets Used",
                    icon: "hand.raised",
                    color: .purple
                )
                StatCard(
                    value: "\(store.diagnostics.openAppRulesMissingTarget)",
                    label: "Missing Apps",
                    icon: "exclamationmark.triangle",
                    color: .orange
                )
                StatCard(
                    value: "\(store.rules.filter { $0.reciprocalEnabled && $0.direction.hasSpeed }.count)",
                    label: "Reciprocal Pairs",
                    icon: "arrow.left.and.right",
                    color: .teal
                )
                StatCard(
                    value: "\(store.rules.filter { $0.modifierFilter != .any }.count)",
                    label: "Modifier Gestures",
                    icon: "command",
                    color: .indigo
                )
            }
            .padding(8)
        }
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
