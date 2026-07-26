import SwiftUI
import CoreGraphics

struct AppSwitcherTab: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var screenCaptureGranted = CGPreflightScreenCaptureAccess()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                if store.appSwitcher.enabled {
                    overlayPreview
                    presentationSection

                    TuningSection(title: "Behavior", icon: "gearshape") {
                        Toggle("Restore minimized windows in native fallback", isOn: switcherBinding(\.restoreMinimizedOnCommit))
                        Text("The custom switcher always restores only the minimized window you select. This option applies when Glide falls back to macOS’s native switcher.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TuningSection(title: "Movement", icon: "slider.horizontal.3") {
                        SliderRow(
                            label: "Step Distance",
                            value: tuningBinding(\.appSwitcherStepThreshold),
                            range: 0.001...0.01,
                            format: "%.3f",
                            hint: "How far your fingers travel before the selection moves one app."
                        )
                        SliderRow(
                            label: "Step Delay",
                            value: tuningBinding(\.appSwitcherDebounce),
                            range: 0.05...0.5,
                            format: "%.2f s",
                            hint: "The shortest pause between selection changes."
                        )
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { screenCaptureGranted = CGPreflightScreenCaptureAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenCaptureGranted = CGPreflightScreenCaptureAccess()
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("App Switcher")
                    .font(.title2.weight(.semibold))
                Text("Swipe left or right to choose an app, then up or down to choose one of its windows. Release to open it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(store.appSwitcher.enabled ? "On" : "Off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.appSwitcher.enabled ? .green : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule(style: .continuous))

            Toggle("Enable App Switcher", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Enable App Switcher")
        }
        .padding(16)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private var overlayPreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .foregroundStyle(Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255))
                Text("Custom overlay preview")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("← → apps · ↑ ↓ windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 10) {
                previewCard(name: "Finder", symbol: "face.smiling", selected: false)
                previewCard(name: "Notes", symbol: "note.text", selected: true)
                previewCard(name: "Safari", symbol: "safari", selected: false)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func previewCard(name: String, symbol: String, selected: Bool) -> some View {
        let violet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
        return VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .frame(width: 42, height: 42)
                .foregroundStyle(selected ? violet : Color.secondary)
            Text(name)
                .font(.caption.weight(selected ? .semibold : .medium))
                .lineLimit(1)
        }
        .frame(width: 104, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? violet.opacity(0.16) : Color.primary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? violet : Color.primary.opacity(0.10), lineWidth: selected ? 3 : 1)
        }
    }
    private var presentationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: screenCaptureGranted ? "macwindow.on.rectangle" : "app.dashed")
                        .foregroundStyle(screenCaptureGranted ? Color.accentColor : Color.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(screenCaptureGranted ? "Window previews are ready" : "Using app icons")
                            .font(.subheadline.weight(.semibold))
                        Text(screenCaptureGranted
                             ? "Glide shows each app’s largest visible window when the switcher opens."
                             : "The switcher works without Screen Recording. Grant access if you also want window previews.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !screenCaptureGranted {
                        Button("Open Privacy Settings") { openScreenRecordingSettings() }
                            .controlSize(.small)
                    }
                }

                Divider()

                Label("If the custom panel cannot open, Glide falls back to the native macOS switcher.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        } label: {
            Label("Presentation", systemImage: "rectangle.on.rectangle.angled")
        }
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.appSwitcher.enabled },
            set: { newValue in store.updateAppSwitcher { $0.enabled = newValue } }
        )
    }

    private func switcherBinding<T>(_ keyPath: WritableKeyPath<AppSwitcherSettings, T>) -> Binding<T> {
        Binding(
            get: { store.appSwitcher[keyPath: keyPath] },
            set: { newValue in store.updateAppSwitcher { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func tuningBinding<T>(_ keyPath: WritableKeyPath<GestureTuning, T>) -> Binding<T> {
        Binding(
            get: { store.tuning[keyPath: keyPath] },
            set: { newValue in store.updateTuning { $0[keyPath: keyPath] = newValue } }
        )
    }
}