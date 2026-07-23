import Cocoa
import ApplicationServices

final class GestureInputManager {
    weak var engine: GestureEngine?

    var suppressionTap: CFMachPort?
    var suppressionSource: CFRunLoopSource?
    private(set) var suppressionEnabled = false

    /// During the zoom double-tap window the tap stays active, but gesture-class
    /// events are passed through so macOS can recognize the tap. Scroll is always
    /// swallowed at 3+ fingers regardless, so a moving swipe can't scrub video.
    var tapWindowActive = false

    var clickObservationTap: CFMachPort?
    var clickObservationSource: CFRunLoopSource?
    var clickTapInstalled = false

    var interactionMonitors: [Any] = []
    var pressureMonitor: Any?
    var lastForceClickTime: TimeInterval = 0
    let forceCooldown: TimeInterval = 0.4

    init(engine: GestureEngine) {
        self.engine = engine
    }

    func setupTaps() {
        setupSuppressionTap()
        setupClickObservationTap()
    }

    func teardownTaps() {
        teardownSuppressionTap()
        teardownClickObservationTap()
    }

    func setupSuppressionTap() {
        let gestureEventTypeValues: [UInt32] = [18, 19, 20, 29, 30, 31, 32]
        var mask = UInt64(NSEvent.EventTypeMask.gesture.rawValue)
                 | UInt64(NSEvent.EventTypeMask.pressure.rawValue)
                 | UInt64(1 << CGEventType.scrollWheel.rawValue)
                 | UInt64(1 << CGEventType.leftMouseDown.rawValue)
        for type in gestureEventTypeValues {
            mask |= (1 << type)
        }

        suppressionTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if GestureEngine.shared.inputManager.suppressionEnabled,
                       let tap = GestureEngine.shared.inputManager.suppressionTap {
                        AppLogger.debug("[Input] Suppression tap timed out — re-enabling")
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                if type == .leftMouseDown {
                    if TouchTracker.glideActiveTouches >= 3 {
                        TouchTracker.glideClickFingerCount = TouchTracker.glideActiveTouches
                    }
                    return Unmanaged.passUnretained(cgEvent)
                }
                if TouchTracker.glideActiveTouches >= 3 {
                    let im = GestureEngine.shared.inputManager!
                    let isScroll = type.rawValue == CGEventType.scrollWheel.rawValue
                    let isSystemGesture = [18, 19, 20, 29, 30, 31, 32].contains(type.rawValue)
                    
                    // Deep-press events are gesture-class, so this tap swallows them
                    // while 3+ fingers are down — exactly when a force click can happen.
                    // The NSEvent pressure monitor would never see them; detect here first.
                    if !isScroll, let ns = NSEvent(cgEvent: cgEvent), ns.type == .pressure {
                        im.handleDeepPress(stage: ns.stage)
                    }
                    
                    // Always swallow scroll at 3+ fingers so a 3-finger swipe can't
                    // reach apps (e.g. scrub a video).
                    // Always swallow system gestures at 3+ fingers so Mission Control doesn't trigger.
                    if isScroll || isSystemGesture { return nil }
                    
                    // In the zoom tap window, still pass gesture-class events so the double-tap is recognized.
                    return im.tapWindowActive ? Unmanaged.passUnretained(cgEvent) : nil
                }
                return Unmanaged.passUnretained(cgEvent)
            },
            userInfo: nil)

        if let tap = suppressionTap {
            suppressionSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), suppressionSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func setSuppressionActive(_ active: Bool) {
        guard active != suppressionEnabled, let tap = suppressionTap else { return }
        suppressionEnabled = active
        CGEvent.tapEnable(tap: tap, enable: active)
    }

    func teardownSuppressionTap() {
        if let tap = suppressionTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = suppressionSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        suppressionTap    = nil
        suppressionSource = nil
        suppressionEnabled = false
    }

    func setupClickObservationTap() {
        guard !clickTapInstalled else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        clickObservationTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = GestureEngine.shared.inputManager.clickObservationTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }
                let count = TouchTracker.getThreeFingerCount()
                let peak = TouchTracker.getSessionPeakActiveTouches()
                if TouchTracker.clickGestureMatchesFingerState(count: count, peak: peak) {
                    // No app haptic here: a physical click already gives native
                    // down/up feedback — adding one reads as a triple "crunch".
                    DispatchQueue.main.async { GestureEngine.shared.processClick(fingerCount: count) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil)

        if let tap = clickObservationTap {
            clickObservationSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), clickObservationSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            clickTapInstalled = true
        }
    }

    func teardownClickObservationTap() {
        if let tap = clickObservationTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = clickObservationSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        clickObservationTap    = nil
        clickObservationSource = nil
        clickTapInstalled      = false
    }

    func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.engine?.handleExternalInteraction()
        }) { interactionMonitors.append(m) }

        // Resolve a deferred click on release: if no deep press arrived before the
        // fingers lifted, it was a normal click. Dispatched async so it always runs
        // after the mouse-down's processClick has registered the pending click.
        if let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            DispatchQueue.main.async { self?.engine?.flushPendingClick() }
        }) { interactionMonitors.append(up) }

        // Fallback path only — while 3+ fingers are down the suppression tap consumes
        // pressure events before they reach this monitor, and calls handleDeepPress itself.
        let pressureMask = NSEvent.EventTypeMask(rawValue: 1 << NSEvent.EventType.pressure.rawValue)
        pressureMonitor = NSEvent.addGlobalMonitorForEvents(matching: pressureMask) { [weak self] event in
            self?.handleDeepPress(stage: event.stage)
        }
        if let pm = pressureMonitor { interactionMonitors.append(pm) }
    }

    /// Deep-press (stage 2) → force click. Called from both the suppression tap and the
    /// NSEvent pressure monitor; the cooldown dedupes if both ever see the same press.
    func handleDeepPress(stage: Int) {
        guard stage >= 2, let engine = engine, engine.isRunning else { return }
        let count = TouchTracker.getThreeFingerCount()
        let peak = TouchTracker.getSessionPeakActiveTouches()
        guard TouchTracker.clickGestureMatchesFingerState(count: count, peak: peak) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastForceClickTime > forceCooldown else { return }
        lastForceClickTime = now
        DispatchQueue.main.async { engine.processForceClick(fingerCount: count) }
    }

    func removeMonitors() {
        interactionMonitors.forEach { NSEvent.removeMonitor($0) }
        interactionMonitors.removeAll()
        pressureMonitor = nil
    }

    func checkHealth() {
        if let tap = suppressionTap {
            if !CFMachPortIsValid(tap) {
                teardownSuppressionTap(); setupSuppressionTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) && suppressionEnabled {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        if let tap = clickObservationTap {
            if !CFMachPortIsValid(tap) {
                teardownClickObservationTap(); setupClickObservationTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }
}
