import Cocoa
import ApplicationServices

final class GestureInputManager {
    weak var engine: GestureEngine?

    var suppressionTap: CFMachPort?
    var suppressionSource: CFRunLoopSource?
    private(set) var suppressionEnabled = false

    var clickObservationTap: CFMachPort?
    var clickObservationSource: CFRunLoopSource?
    var clickTapInstalled = false

    var lastClickEventTime: TimeInterval = 0
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
        let mask = UInt64(NSEvent.EventTypeMask.gesture.rawValue)
                 | UInt64(1 << CGEventType.scrollWheel.rawValue)
                 | UInt64(1 << CGEventType.leftMouseDown.rawValue)

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
                    if TouchTracker.glideActiveTouches >= 3 { TouchTracker.glideClickFingerCount = TouchTracker.glideActiveTouches }
                    return Unmanaged.passUnretained(cgEvent)
                }
                if TouchTracker.glideActiveTouches >= 3 { return nil }
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
                GestureEngine.shared.inputManager.lastClickEventTime = ProcessInfo.processInfo.systemUptime
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
                    if Settings.shared.hapticFeedbackEnabled {
                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    }
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

        let pressureMask = NSEvent.EventTypeMask(rawValue: 1 << NSEvent.EventType.pressure.rawValue)
        pressureMonitor = NSEvent.addGlobalMonitorForEvents(matching: pressureMask) { [weak self] event in
            guard let self = self, let engine = self.engine, engine.isRunning else { return }
            let count = TouchTracker.getThreeFingerCount()
            let peak = TouchTracker.getSessionPeakActiveTouches()
            guard TouchTracker.clickGestureMatchesFingerState(count: count, peak: peak), event.stage >= 2 else { return }
            let now = Date().timeIntervalSinceReferenceDate
            guard now - self.lastForceClickTime > self.forceCooldown else { return }
            self.lastForceClickTime = now
            DispatchQueue.main.async { engine.processClick(fingerCount: count) }
        }
        if let pm = pressureMonitor { interactionMonitors.append(pm) }
    }

    func removeMonitors() {
        interactionMonitors.forEach { NSEvent.removeMonitor($0) }
        interactionMonitors.removeAll()
    }

    func checkHealth() {
        if let tap = suppressionTap {
            if !CFMachPortIsValid(tap) {
                teardownSuppressionTap(); setupSuppressionTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) && suppressionEnabled {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let tap = clickObservationTap {
            let stale = now - lastClickEventTime > 10.0
            if !CFMachPortIsValid(tap) {
                teardownClickObservationTap(); setupClickObservationTap()
            } else if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else if stale && TouchTracker.glideActiveTouches >= 3 {
                teardownClickObservationTap(); setupClickObservationTap()
            }
        }
    }
}
