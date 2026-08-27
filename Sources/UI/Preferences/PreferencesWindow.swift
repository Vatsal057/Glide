import SwiftUI
import AppKit

enum PrefsTab: String, CaseIterable, Identifiable {
    case gestures      = "Gestures"
    case keyboard      = "Keyboard"
    case appSwitcher   = "App Switcher"
    case trackPoint    = "TrackPoint"
    case tuning        = "Tuning"
    case general       = "General"
    case configuration = "Configuration"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appSwitcher:   return "rectangle.2.swap"
        case .trackPoint:    return "dot.circle.and.hand.point.up.left.fill"
        case .gestures:      return "hand.draw"
        case .keyboard:      return "keyboard"
        case .tuning:        return "slider.horizontal.3"
        case .general:       return "gearshape"
        case .configuration: return "doc.text"
        }
    }
}

/// Lets other parts of the app decide which tab the Preferences window opens on.
///
/// Held outside the view so callers can set it *before* the window exists —
/// posting a notification at a window that hasn't been created yet would land
/// on nothing.
@MainActor
final class PreferencesNavigator: ObservableObject {
    static let shared = PreferencesNavigator()
    private init() {}

    @Published var tab: PrefsTab = .gestures
}

struct PreferencesWindow: View {
    @ObservedObject private var navigator = PreferencesNavigator.shared
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge: EngineBridge

    private var selectedTab: PrefsTab { navigator.tab }

    var body: some View {
        NavigationSplitView {
            List(PrefsTab.allCases, selection: $navigator.tab) { tab in
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
                case .trackPoint:    TrackPointTab()
                case .gestures:      GesturesTab()
                case .keyboard:      KeyboardTab()
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
