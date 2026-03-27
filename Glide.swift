import Cocoa

// MARK: - MultitouchSupport

var globalActiveTouchesCount: Int32 = 0

public struct MTTouch {
    public var frame: Int32
    public var timestamp: Double
    public var identifier: Int32
    public var state: Int32
    public var unknown1: Int32
    public var unknown2: Int32
    public var normalizedVector: (Float, Float)
    public var zTotal: Float
    public var pressure: Int32
    public var angle: Float
    public var majorAxis: Float
    public var minorAxis: Float
    public var absoluteVector: (Float, Float)
    public var unknown3: Int32
    public var unknown4: Int32
    public var zDensity: Float
}

typealias MTContactCallbackFunction = @convention(c) (Int32, UnsafeMutableRawPointer, Int32, Double, Int32) -> Int32
typealias MTDeviceCreateDefaultType = @convention(c) () -> UnsafeMutableRawPointer?
typealias MTRegisterContactFrameCallbackType = @convention(c) (UnsafeMutableRawPointer, MTContactCallbackFunction) -> Void
typealias MTDeviceStartType = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
typealias MTDeviceStopType = @convention(c) (UnsafeMutableRawPointer) -> Void

let mtCallback: MTContactCallbackFunction = { device, data, numFingers, timestamp, frame in
    let count = Int(numFingers)
    if count > 0 {
        let touches = data.assumingMemoryBound(to: MTTouch.self)
        var vectors = [(Float, Float)]()
        vectors.reserveCapacity(count)
        for i in 0..<count {
            vectors.append(touches[i].normalizedVector)
        }
        DispatchQueue.main.async {
            globalActiveTouchesCount = numFingers
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.detector.setGestureSuppression(enabled: numFingers >= 3)
            }
            GestureEngine.shared.onTouchesUpdate(numFingers: numFingers, touchVectors: vectors)
        }
    } else {
        DispatchQueue.main.async {
            globalActiveTouchesCount = 0
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.detector.setGestureSuppression(enabled: false)
            }
            GestureEngine.shared.onTouchesUpdate(numFingers: 0, touchVectors: [])
        }
    }
    return 0
}

var mtDevice: UnsafeMutableRawPointer?
var MTDeviceStopFunc: MTDeviceStopType?

func startMultitouch() {
    guard let mtLib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else { return }

    let createFunc = dlsym(mtLib, "MTDeviceCreateDefault")!
    let registerFunc = dlsym(mtLib, "MTRegisterContactFrameCallback")!
    let startFunc = dlsym(mtLib, "MTDeviceStart")!
    let stopFunc = dlsym(mtLib, "MTDeviceStop")!
    
    let MTDeviceCreateDefault = unsafeBitCast(createFunc, to: MTDeviceCreateDefaultType.self)
    let MTRegisterContactFrameCallback = unsafeBitCast(registerFunc, to: MTRegisterContactFrameCallbackType.self)
    let MTDeviceStart = unsafeBitCast(startFunc, to: MTDeviceStartType.self)
    MTDeviceStopFunc = unsafeBitCast(stopFunc, to: MTDeviceStopType.self)

    if let device = MTDeviceCreateDefault() {
        mtDevice = device
        MTRegisterContactFrameCallback(device, mtCallback)
        MTDeviceStart(device, 0)
    }
}

func stopMultitouch() {
    if let device = mtDevice, let stop = MTDeviceStopFunc {
        stop(device)
    }
}

// MARK: - Gesture Detector

class GestureDetector {
    private var monitors: [Any] = []
    private var gestureEventTap: CFMachPort?
    private var gestureRunLoopSource: CFRunLoopSource?
    private var isTapEnabled = false

    func start() {
        startMultitouch()
        startGestureSuppression()

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown,
                                                      handler: { [weak self] e in
            self?.handleLeftClick(e)
        }) { monitors.append(m) }

        print("Glide active.")
    }

    func stop() {
        stopMultitouch()
        stopGestureSuppression()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    // Intercept NSEvent gesture and scroll events so browsers and movies don't scrub or swipe back/forward
    private func startGestureSuppression() {
        let gestureMask = UInt64(NSEvent.EventTypeMask.gesture.rawValue)
        let scrollMask = UInt64(1 << CGEventType.scrollWheel.rawValue)
        let eventMask = gestureMask | scrollMask
        
        gestureEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, cgEvent, userInfo in
                // Suppress scrolling and gesture actions entirely if we are using 3+ fingers
                if globalActiveTouchesCount >= 3 {
                    return nil // Consume the event
                }
                return Unmanaged.passUnretained(cgEvent)
            },
            userInfo: nil
        )
        if let tap = gestureEventTap {
            gestureRunLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), gestureRunLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false) // Start completely dormant to save battery
        }
    }
    
    func setGestureSuppression(enabled: Bool) {
        guard enabled != isTapEnabled else { return }
        isTapEnabled = enabled
        if let tap = gestureEventTap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
    }

    private func stopGestureSuppression() {
        if let tap = gestureEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = gestureRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        gestureEventTap = nil
        gestureRunLoopSource = nil
    }

    // MARK: Click detection

    private func handleLeftClick(_ event: NSEvent) {
        if GestureEngine.shared.isSwiping { return }
        let numFingers = Int(globalActiveTouchesCount)
        
        // Find if user mapped the current finger count to a Click action
        guard let rule = Settings.shared.rules.first(where: { $0.fingers == numFingers && $0.direction == .click }) else { return }
        
        if rule.action == .quitApp {
            let location = NSEvent.mouseLocation
            DispatchQueue.main.async { [weak self] in
                self?.quitAppAtLocation(location)
            }
        } else {
            // Forward other arbitrary actions through the engine
            GestureEngine.shared.executeAction(rule.action)
        }
    }

    // MARK: Window / app detection

    private func quitAppAtLocation(_ mouseLocation: NSPoint) {
        // Cocoa origin = bottom-left. CGWindowList origin = top-left (per screen).
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                        ?? NSScreen.main else { return }

        let cgY = screen.frame.maxY - mouseLocation.y
        let cgPoint = CGPoint(x: mouseLocation.x, y: cgY)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for win in list {
            guard
                let b    = win[kCGWindowBounds as String] as? [String: CGFloat],
                let pid  = win[kCGWindowOwnerPID as String] as? pid_t,
                let layer = win[kCGWindowLayer as String] as? Int,
                pid != myPID,
                layer == 0
            else { continue }

            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                              width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard rect.contains(cgPoint) else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }

            app.terminate()
            return
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let detector = GestureDetector()
    private var enabled  = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        requestAccessibility()
        
        // Monitor for app terminations so we can prune orphaned PIDs from cache
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        // Re-initialize on wake from sleep — MultitouchSupport device and CGEvent tap both get invalidated
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }
    
    @objc private func systemDidWake() {
        guard enabled else { return }
        // Brief delay to let the OS fully wake before re-registering
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.detector.stop()
            self?.detector.start()
        }
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            WindowInteractions.pruneCachedFrame(for: app.processIdentifier)
        }
    }

    // MARK: Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshIcon()
        refreshMenu()
    }

    private func refreshIcon() {
        guard let btn = statusItem.button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.image = NSImage(systemSymbolName: "hand.raised.fill",
                            accessibilityDescription: nil)?
                        .withSymbolConfiguration(cfg)
        btn.image?.isTemplate = true
        btn.appearsDisabled = !enabled
    }

    private func refreshMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Glide", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: enabled ? "Disable" : "Enable",
                                action: #selector(toggle), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "Help", action: #selector(help), keyEquivalent: "h")
        menu.addItem(withTitle: "Quit Glide", action: #selector(quitApp), keyEquivalent: "q")
        
        statusItem.menu = menu
    }

    @objc private func toggle() {
        enabled.toggle()
        enabled ? detector.start() : detector.stop()
        refreshIcon(); refreshMenu()
    }

    @objc private func showPreferences() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func help() {
        let a = NSAlert()
        a.messageText     = "How to use Glide"
        a.informativeText = """
        1. Click & Quit: Hover over any window and 3-finger click to instantly quit it.
        2. App Switchers: 3-finger swipe left or right to fluidly browse and switch apps.
        
        Notes:
        • Uses MultitouchSupport for ultra-low latency tracking.
        • Designed for Windows 11-style snappiness.
        • Requires Accessibility permission.
        """
        a.addButton(withTitle: "Got it")
        a.runModal()
    }

    // MARK: Accessibility

    private func requestAccessibility() {
        let key  = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            detector.start()
        } else {
            poll()
        }
    }

    private func poll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if AXIsProcessTrusted() { self?.detector.start() } else { self?.poll() }
        }
    }
}

// MARK: - Entry Point
