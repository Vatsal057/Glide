import Cocoa
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private let store = PreferencesStore.shared

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: true)   // FIX: Defer backing-store allocation until window is first shown
        win.title = "GestureFlow"
        win.minSize = NSSize(width: 860, height: 520)
        win.center()
        win.titlebarAppearsTransparent = false
        win.toolbarStyle = .unified

        super.init(window: win)

        win.contentViewController = NSHostingController(rootView: PreferencesRootView(store: store))
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        store.reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
