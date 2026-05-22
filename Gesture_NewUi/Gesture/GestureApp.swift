import SwiftUI
import ServiceManagement
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EngineBridge.shared.startEngine(store: GestureStore.shared, settings: AppSettings.shared)
    }
}

@main
struct GestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var gestureStore = GestureStore.shared
    @StateObject private var appSettings  = AppSettings.shared
    @StateObject private var engineBridge = EngineBridge.shared

    var body: some Scene {
        MenuBarExtra("Gesture", systemImage: "hand.draw") {
            MenuBarView()
                .environmentObject(gestureStore)
                .environmentObject(appSettings)
                .environmentObject(engineBridge)
        }
        .menuBarExtraStyle(.menu)

        Window("Gesture Preferences", id: "preferences") {
            PreferencesWindow()
                .environmentObject(gestureStore)
                .environmentObject(appSettings)
                .environmentObject(engineBridge)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)

        Settings { EmptyView() }
    }
}

// MARK: - EngineBridge

final class EngineBridge: ObservableObject {
    static let shared = EngineBridge()
    private init() {}

    @Published var isEnabled: Bool = true {
        didSet { GestureEngine.shared.isEnabled = isEnabled }
    }

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver:  NSObjectProtocol?
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    func startEngine(store: GestureStore, settings: AppSettings) {
        guard !started else { return }
        started = true

        let engine = GestureEngine.shared
        engine.store     = store
        engine.settings  = settings
        engine.isEnabled = isEnabled
        engine.start()

        // Keep store/settings live on the engine as prefs change
        observeSettings(store: store, settings: settings)

        // Stop/restart around sleep-wake cycle (trackpad hardware reinits after wake)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            NSLog("[App] Sleep — stopping engine")
            GestureEngine.shared.stop()
            self?.isEnabled = false
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            NSLog("[App] Wake — restarting engine")
            self?.isEnabled = true
            GestureEngine.shared.restart()
        }
    }

    private func observeSettings(store: GestureStore, settings: AppSettings) {
        GestureEngine.shared.store    = store
        GestureEngine.shared.settings = settings

        store.objectWillChange
            .sink { _ in
                GestureEngine.shared.store = store
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { _ in
                GestureEngine.shared.settings = settings
            }
            .store(in: &cancellables)
    }

    deinit {
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = wakeObserver  { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }
}
