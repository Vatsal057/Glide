import SwiftUI
import CoreGraphics

private struct AppSwitcherPreviewDeckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let neckWidth: CGFloat = 16
        let neckHeight: CGFloat = 14
        let radius: CGFloat = 18
        let midX = rect.midX
        var path = Path()

        path.move(to: CGPoint(x: midX - neckWidth / 2, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + neckHeight + radius),
            control1: CGPoint(x: midX + neckWidth / 2, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + neckHeight)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + neckHeight + radius))
        path.addCurve(
            to: CGPoint(x: midX - neckWidth / 2, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + neckHeight),
            control2: CGPoint(x: midX - neckWidth / 2, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

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
        let violet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .foregroundStyle(violet)
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

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    previewApp(name: "Mail", symbol: "envelope.fill", selected: false)
                    previewApp(name: "Notes", symbol: "note.text", selected: true)
                    previewApp(name: "Safari", symbol: "safari.fill", selected: false)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "note.text")
                            .foregroundStyle(violet)
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("• 2 windows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ZStack(alignment: .top) {
                        previewWindow(title: "Quick Notes", selected: false)
                            .scaleEffect(0.92)
                            .offset(y: 18)
                        previewWindow(title: "Project Notes", selected: true)
                    }
                    .frame(height: 108)
                }
                .padding(.top, 21)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                .background(.regularMaterial, in: AppSwitcherPreviewDeckShape())
                .frame(width: 210)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Example app switcher with Notes selected and a two-window deck")
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func previewApp(name: String, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                }
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(
                        selected
                        ? Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
                        : Color.secondary
                    )
            }
            .frame(width: 48, height: 44)

            Text(selected ? name : " ")
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 64)
        }
    }

    private func previewWindow(title: String, selected: Bool) -> some View {
        let violet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
        return VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 142, height: 58)
                .overlay {
                    Image(systemName: "text.alignleft")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            Text(title)
                .font(.caption2.weight(selected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 142)
        }
        .padding(7)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? violet : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
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
                             ? "Glide shows a preview for each selectable window on the current Space as you move through apps."
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