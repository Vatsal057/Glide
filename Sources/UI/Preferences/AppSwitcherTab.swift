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
                    HStack(alignment: .top, spacing: 18) {
                        // Left Column: Mode Presentation & Visual Preview
                        VStack(alignment: .leading, spacing: 18) {
                            if store.appSwitcher.style == .newer {
                                overlayPreview
                                presentationSection
                            } else {
                                legacyNotice
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        // Right Column: Tuning & Behavior Controls
                        VStack(alignment: .leading, spacing: 18) {
                            behaviorSection
                            movementSection
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: store.appSwitcher.style)
            .animation(.easeInOut(duration: 0.2), value: store.appSwitcher.enabled)
        }
        .onAppear { screenCaptureGranted = CGPreflightScreenCaptureAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenCaptureGranted = CGPreflightScreenCaptureAccess()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("App Switcher")
                        .font(.title2.weight(.semibold))
                    Text(headerSubtitle)
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

            if store.appSwitcher.enabled {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Switcher Mode", systemImage: "square.on.square.squareshape.controlhandles")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    Picker("Switcher Style", selection: switcherBinding(\.style)) {
                        ForEach(AppSwitcherStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(store.appSwitcher.style == .newer
                         ? "Newer mode presents Glide's visual Liquid Glass app switcher overlay with window previews and vertical window selection decks."
                         : "Legacy mode uses macOS's native Command+Tab keyboard shortcuts approach directly during trackpad swipes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
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
                Image(systemName: "drop.fill")
                    .foregroundStyle(violet)
                Text("Liquid Glass Overlay Preview")
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
                HStack(spacing: 16) {
                    previewApp(name: "Mail", symbol: "envelope.fill", selected: false)
                    previewApp(name: "Notes", symbol: "note.text", selected: true)
                    previewApp(name: "Safari", symbol: "safari.fill", selected: false)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }

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
                .frame(width: 220)
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
        let violet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
        return VStack(spacing: 4) {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(violet.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(violet, lineWidth: 2.5)
                        }
                }
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(selected ? violet : Color.secondary)
            }
            .frame(width: 52, height: 48)

            Text(name)
                .font(.caption2.weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
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
    private var headerSubtitle: String {
        switch store.appSwitcher.style {
        case .newer:
            return "Swipe left or right to choose an app, then up or down to choose one of its windows. Release to open it."
        case .legacy:
            return "Swipe left or right to cycle through running apps using macOS native Command+Tab keyboard shortcuts."
        }
    }

    private var presentationSection: some View {
        TuningSection(title: "Presentation", icon: "macwindow.on.rectangle") {
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

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Animate selection", isOn: switcherBinding(\.animationsEnabled))
                    Text("Springy transitions as you move between apps and windows. Off by default: because selection can step several times a second, the animation keeps the whole overlay redrawing and roughly doubles the CPU the switcher uses while you swipe. Leave it off for the lightest, most battery-friendly switcher.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Label("If the custom panel cannot open, Glide falls back to the native macOS switcher.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var legacyNotice: some View {
        TuningSection(title: "Presentation", icon: "keyboard") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        keyCapView(symbol: "command", label: "Cmd")
                        Text("+")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        keyCapView(symbol: "arrow.right.to.line", label: "Tab")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("macOS System Switcher Integration")
                            .font(.subheadline.weight(.semibold))
                        Text("Swiping converts trackpad gestures directly into Command+Tab events. The native macOS HUD handles app selection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Zero screen recording permissions required. Compatible with all macOS versions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private var behaviorSection: some View {
        TuningSection(title: "Behavior", icon: "gearshape") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Restore minimized windows in native fallback", isOn: switcherBinding(\.restoreMinimizedOnCommit))
                Text("The custom switcher always restores only the minimized window you select. This option applies when Glide falls back to macOS’s native switcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private var movementSection: some View {
        TuningSection(title: "Movement", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                SliderRow(
                    label: "Step Distance",
                    value: tuningBinding(\.appSwitcherStepThreshold),
                    range: 0.001...0.01,
                    format: "%.3f",
                    hint: "How far your fingers travel before the selection moves one app."
                )
                Divider()
                SliderRow(
                    label: "Step Delay",
                    value: tuningBinding(\.appSwitcherDebounce),
                    range: 0.05...0.5,
                    format: "%.2f s",
                    hint: "The shortest pause between selection changes."
                )
            }
            .padding(12)
        }
    }

    private func keyCapView(symbol: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
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