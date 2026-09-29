import Cocoa
import IOKit

// ─────────────────────────────────────────────
// MARK: - Haptic pattern library
// ─────────────────────────────────────────────

/// One physical pulse strength on the Taptic Engine.
enum HapticStrength: String, CaseIterable, Codable {
    case weak = "weak"
    case medium = "medium"
    case strong = "strong"

    /// MTActuator built-in actuation IDs (3 = weak, 4 = medium, 6 = strong).
    var actuationID: Int32 {
        switch self {
        case .weak:   return 3
        case .medium: return 4
        case .strong: return 6
        }
    }

    /// Public-API stand-in when the private actuator is unavailable.
    var fallback: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .weak:   return .alignment
        case .medium: return .generic
        case .strong: return .levelChange
        }
    }
}

extension HapticStrength: Comparable {
    static func < (lhs: HapticStrength, rhs: HapticStrength) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .weak:   return 0
        case .medium: return 1
        case .strong: return 2
        }
    }
}

/// A named, composable haptic: a sequence of pulses with millisecond offsets.
enum HapticPattern: String, CaseIterable, Codable {
    case none       = "none"
    case softTick   = "soft_tick"
    case tap        = "tap"
    case knock      = "knock"
    case doubleTap  = "double_tap"
    case tripleBuzz = "triple_buzz"
    case rising     = "rising"
    case falling    = "falling"
    case heartbeat  = "heartbeat"

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .softTick:   return "Soft Tick"
        case .tap:        return "Tap"
        case .knock:      return "Knock"
        case .doubleTap:  return "Double Tap"
        case .tripleBuzz: return "Triple Buzz"
        case .rising:     return "Rising"
        case .falling:    return "Falling"
        case .heartbeat:  return "Heartbeat"
        }
    }

    /// (millisecond offset from start, pulse strength)
    var steps: [(ms: Int, strength: HapticStrength)] {
        switch self {
        case .none:       return []
        case .softTick:   return [(0, .weak)]
        case .tap:        return [(0, .medium)]
        case .knock:      return [(0, .strong)]
        case .doubleTap:  return [(0, .medium), (90, .medium)]
        case .tripleBuzz: return [(0, .weak), (55, .weak), (110, .weak)]
        case .rising:     return [(0, .weak), (70, .medium), (140, .strong)]
        case .falling:    return [(0, .strong), (70, .medium), (140, .weak)]
        case .heartbeat:  return [(0, .strong), (180, .strong)]
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Haptic events (what happened → which pattern)
// ─────────────────────────────────────────────

/// Every distinct moment Glide gives haptic feedback. Each has a
/// user-assignable pattern, persisted in config.yaml under `haptics:`.
enum HapticEvent: String, CaseIterable {
    case destructiveAction = "destructive_action"   // quit, force-quit, close, empty trash
    case windowAction      = "window_action"        // snap, minimize, fullscreen, move…
    case otherAction       = "other_action"         // shortcuts, media, apps, everything else
    case switcherOpen      = "switcher_open"
    case switcherStep      = "switcher_step"
    case switcherCommit    = "switcher_commit"
    case reciprocal        = "reciprocal"

    var displayName: String {
        switch self {
        case .destructiveAction: return "Quit & Close Actions"
        case .windowAction:      return "Window Actions"
        case .otherAction:       return "Other Actions"
        case .switcherOpen:      return "App Switcher Open"
        case .switcherStep:      return "App Switcher Step"
        case .switcherCommit:    return "App Switcher Commit"
        case .reciprocal:        return "Reciprocal Gesture"
        }
    }

    /// Natural-feel defaults: finality falls, engagement rises,
    /// browsing ticks softly, confirmation double-taps.
    var defaultPattern: HapticPattern {
        switch self {
        case .destructiveAction: return .falling
        case .windowAction:      return .tap
        case .otherAction:       return .softTick
        case .switcherOpen:      return .rising
        case .switcherStep:      return .softTick
        case .switcherCommit:    return .doubleTap
        case .reciprocal:        return .doubleTap
        }
    }

    static var defaultAssignments: [HapticEvent: HapticPattern] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.defaultPattern) })
    }
}

// ─────────────────────────────────────────────
// MARK: - HapticEngine (private MTActuator, NSHaptic fallback)
// ─────────────────────────────────────────────

/// Drives the trackpad's Taptic Engine directly through the private
/// MultitouchSupport MTActuator API (same framework the touch tracker
/// already dlopens). Falls back to NSHapticFeedbackManager when the
/// actuator is unavailable (non-Force-Touch pads, symbol changes).
final class HapticEngine {

    static let shared = HapticEngine()

    private typealias CreateFn  = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenFn    = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private var fnCreate:  CreateFn?
    private var fnOpen:    OpenFn?
    private var fnActuate: ActuateFn?
    private var actuator:  CFTypeRef?

    private init() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return }
        func sym<T>(_ name: String) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: T.self) } }
        fnCreate  = sym("MTActuatorCreateFromDeviceID")
        fnOpen    = sym("MTActuatorOpen")
        fnActuate = sym("MTActuatorActuate")
        openActuator()
    }

    /// Enumerate multitouch devices and open the first one that actuates.
    private func openActuator() {
        guard let create = fnCreate, let open = fnOpen else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleMultitouchDevice"),
                                           &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let ref = IORegistryEntryCreateCFProperty(service, "Multitouch ID" as CFString,
                                                            kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let deviceID = (ref as? UInt64) ?? (ref as? NSNumber)?.uint64Value else { continue }
            guard let candidate = create(deviceID)?.takeRetainedValue() else { continue }
            if open(candidate) == KERN_SUCCESS {
                actuator = candidate
                AppLogger.debug("[Haptic] Actuator open — device 0x\(String(deviceID, radix: 16))")
                return
            }
        }
        AppLogger.debug("[Haptic] No actuator — using NSHapticFeedbackManager fallback")
    }

    // MARK: Playback

    func play(event: HapticEvent) {
        play(Settings.shared.hapticPattern(for: event))
    }

    func play(_ pattern: HapticPattern) {
        guard Settings.shared.hapticFeedbackEnabled, pattern != .none else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.play(pattern) }
            return
        }
        for step in pattern.steps {
            if step.ms == 0 {
                pulse(step.strength)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(step.ms)) { [weak self] in
                    self?.pulse(step.strength)
                }
            }
        }
    }

    /// Serializes concurrent actuator calls — surface-feel pulses from the MT
    /// thread can race discrete pattern pulses from main.
    private let pulseLock = NSLock()

    /// Fires one raw actuator pulse. Safe to call from the multitouch thread:
    /// the private-actuator path runs inline on the caller, and only the
    /// NSHapticFeedbackManager fallback hops to main.
    ///
    /// Callers gate on the master haptic toggle themselves — see
    /// SurfaceFeelEngine, which snapshots it for the MT thread.
    func pulse(_ strength: HapticStrength) {
        pulseLock.lock()
        let ok: Bool
        if let actuator, let actuate = fnActuate {
            ok = actuate(actuator, strength.actuationID, 0, 0, 0) == KERN_SUCCESS
        } else {
            ok = false
        }
        pulseLock.unlock()
        guard !ok else { return }

        let pattern = strength.fallback
        if Thread.isMainThread {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        } else {
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
            }
        }
    }
}
