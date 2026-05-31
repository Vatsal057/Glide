import Cocoa

final class AppSwitcherState {

    static let shared = AppSwitcherState()

    private var mruAppOrder: [pid_t] = []
    private var mruObserver: Any?

    private init() {}

    func startMRUTracking() {
        if let front = NSWorkspace.shared.frontmostApplication {
            mruAppOrder = [front.processIdentifier]
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if !mruAppOrder.contains(app.processIdentifier) {
                mruAppOrder.append(app.processIdentifier)
            }
        }
        mruObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            self.mruAppOrder.removeAll { $0 == pid }
            self.mruAppOrder.insert(pid, at: 0)
        }
    }

    func stopMRUTracking() {
        if let observer = mruObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            mruObserver = nil
        }
    }

    func getOrderedApps() -> [NSRunningApplication] {
        var apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let cfg = Settings.shared.appSwitcher
        if cfg.useMRUOrdering {
            let mru = self.mruAppOrder
            apps.sort { a, b in
                let ai = mru.firstIndex(of: a.processIdentifier) ?? Int.max
                let bi = mru.firstIndex(of: b.processIdentifier) ?? Int.max
                return ai < bi
            }
        }
        return apps
    }
}
