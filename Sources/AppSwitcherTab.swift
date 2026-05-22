import SwiftUI

struct AppSwitcherTab: View {
    @EnvironmentObject var store: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                headerCard

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Enable App Switcher", isOn: enabledBinding)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                        if store.appSwitcher.enabled {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Finger Count")
                                    .foregroundStyle(.secondary)
                                Picker("", selection: fingersBinding) {
                                    Text("3 Fingers").tag(3)
                                    Text("4 Fingers").tag(4)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 280)
                                .padding(.horizontal, 12)

                                Text(reservedGestureSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if store.appSwitcher.enabled {
                    TuningSection(title: "Sensitivity", icon: "slider.horizontal.3") {
                        SliderRow(
                            label: "Step Threshold",
                            value: tuningBinding(\.appSwitcherStepThreshold),
                            range: 0.001...0.01,
                            format: "%.3f",
                            hint: "How far to swipe while holding to move to the next or previous app."
                        )
                        SliderRow(
                            label: "Debounce",
                            value: tuningBinding(\.appSwitcherDebounce),
                            range: 0.05...0.5,
                            format: "%.2f s",
                            hint: "Minimum time between steps so apps are not skipped too quickly."
                        )
                    }

                    comparisonCard
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "rectangle.2.swap")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text("App Switcher")
                    .font(.title2.bold())
                Text("Hold the gesture, swipe left or right to browse open apps in the macOS switcher, then release to confirm. This is separate from other gestures — swipe left and right with your chosen finger count are reserved here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var comparisonCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Not the same as “Activate Next/Previous App”", systemImage: "info.circle")
                    .font(.subheadline.bold())
                Text("Activate Next/Previous App switches instantly with no overlay. App Switcher opens the Cmd+Tab overlay so you can browse before releasing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reservedGestureSummary: String {
        let n = store.appSwitcher.fingers
        return "\(n)-finger swipe left → previous app · \(n)-finger swipe right → next app. Other directions for \(n) fingers can still be assigned under Gestures."
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.appSwitcher.enabled },
            set: { newValue in store.updateAppSwitcher { $0.enabled = newValue } }
        )
    }

    private var fingersBinding: Binding<Int> {
        Binding(
            get: { store.appSwitcher.fingers },
            set: { newValue in store.updateAppSwitcher { $0.fingers = newValue } }
        )
    }

    private func tuningBinding<T>(_ keyPath: WritableKeyPath<GestureTuning, T>) -> Binding<T> {
        Binding(
            get: { store.tuning[keyPath: keyPath] },
            set: { newValue in store.updateTuning { $0[keyPath: keyPath] = newValue } }
        )
    }
}
