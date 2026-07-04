import SwiftUI
import AppKit

enum PrefsTab: String, CaseIterable, Identifiable {
    case gestures      = "Gestures"
    case appSwitcher   = "App Switcher"
    case tuning        = "Tuning"
    case general       = "General"
    case configuration = "Configuration"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appSwitcher:   return "rectangle.2.swap"
        case .gestures:      return "hand.draw"
        case .tuning:        return "slider.horizontal.3"
        case .general:       return "gearshape"
        case .configuration: return "doc.text"
        }
    }
}

struct PreferencesWindow: View {
    @State private var selectedTab: PrefsTab = .gestures
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge: EngineBridge

    var body: some View {
        NavigationSplitView {
            List(PrefsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .safeAreaInset(edge: .bottom) { sidebarStatus }
        } detail: {
            Group {
                switch selectedTab {
                case .appSwitcher:   AppSwitcherTab()
                case .gestures:      GesturesTab()
                case .tuning:        TuningTab()
                case .general:       GeneralTab()
                case .configuration: ConfigurationTab()
                }
            }
            .navigationTitle(selectedTab.rawValue)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Engine status pinned under the sidebar — visible from every tab.
    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Toggle(isOn: $engineBridge.isEnabled) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engineBridge.isEnabled && preferencesStore.accessibilityGranted ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(engineBridge.isEnabled
                         ? (preferencesStore.accessibilityGranted ? "Gestures active" : "Needs permission")
                         : "Gestures paused")
                        .font(.callout)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
