import SwiftUI

enum PrefsTab: String, CaseIterable, Identifiable {
    case appSwitcher   = "App Switcher"
    case gestures      = "Gestures"
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
    @State private var selectedTab: PrefsTab = .appSwitcher
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge: EngineBridge

    var body: some View {
        NavigationSplitView {
            List(PrefsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            switch selectedTab {
            case .appSwitcher:   AppSwitcherTab()
            case .gestures:      GesturesTab()
            case .tuning:        TuningTab()
            case .general:       GeneralTab()
            case .configuration: ConfigurationTab()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
