import SwiftUI

enum PrefsTab: String, CaseIterable, Identifiable {
    case gestures      = "Gestures"
    case tuning        = "Tuning"
    case general       = "General"
    case configuration = "Configuration"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .gestures:      return "hand.draw"
        case .tuning:        return "slider.horizontal.3"
        case .general:       return "gearshape"
        case .configuration: return "doc.text"
        }
    }
}

struct PreferencesWindow: View {
    @State private var selectedTab: PrefsTab = .gestures
    @EnvironmentObject var gestureStore: GestureStore
    @EnvironmentObject var appSettings:  AppSettings
    @EnvironmentObject var engineBridge: EngineBridge

    var body: some View {
        NavigationSplitView {
            List(PrefsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)

            // Invisible engine starter embedded in the sidebar
            EngineStarter()
                .frame(width: 0, height: 0)
                .hidden()
        } detail: {
            switch selectedTab {
            case .gestures:      GesturesTab()
            case .tuning:        TuningTab()
            case .general:       GeneralTab()
            case .configuration: ConfigurationTab()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
