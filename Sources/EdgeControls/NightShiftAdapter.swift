import Foundation
import ObjectiveC.runtime

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NightShiftAdapter
//
// Dynamically bridges to CBBlueLightClient in CoreBrightness.framework to read
// and adjust Night Shift warmth (0...1).
// ─────────────────────────────────────────────────────────────────────────────

@objc private protocol BlueLightClientProtocol {
    func setStrength(_ strength: Float, commit: Bool) -> Bool
    func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool
    func setEnabled(_ enabled: Bool) -> Bool
    func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
}

final class NightShiftAdapter {
    static let shared = NightShiftAdapter()

    private enum StatusLayout {
        static let bufferSize = 64
        static let isOn = 1
    }

    private let client: BlueLightClientProtocol?
    private let canReadStatus: Bool
    private let isReductionSupported: Bool

    init() {
        guard let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            AppLogger.debug("[NightShiftAdapter] CBBlueLightClient missing")
            client = nil
            canReadStatus = false
            isReductionSupported = false
            return
        }

        let instance = clientClass.init()
        let required: [Selector] = [
            NSSelectorFromString("setStrength:commit:"),
            NSSelectorFromString("getStrength:"),
            NSSelectorFromString("setEnabled:"),
        ]
        guard required.allSatisfy({ instance.responds(to: $0) }) else {
            AppLogger.debug("[NightShiftAdapter] CBBlueLightClient missing expected selectors")
            client = nil
            canReadStatus = false
            isReductionSupported = false
            return
        }

        canReadStatus = instance.responds(to: NSSelectorFromString("getBlueLightStatus:"))
        isReductionSupported = Self.checkSupportsBlueLightReduction(clientClass)
        client = unsafeBitCast(instance, to: BlueLightClientProtocol.self)
    }

    private static func checkSupportsBlueLightReduction(_ clientClass: AnyClass) -> Bool {
        typealias Supports = @convention(c) (AnyClass, Selector) -> Bool
        let selector = NSSelectorFromString("supportsBlueLightReduction")
        guard let method = class_getClassMethod(clientClass, selector) else {
            return true
        }
        let implementation = unsafeBitCast(method_getImplementation(method), to: Supports.self)
        return implementation(clientClass, selector)
    }

    var isSupported: Bool { client != nil && isReductionSupported }

    var value: Double {
        get {
            guard let client, isOn else { return 0 }
            var strength: Float = 0
            guard client.getStrength(&strength) else { return 0 }
            return Double(min(max(strength, 0), 1))
        }
        set {
            guard let client else { return }
            let clamped = Float(min(max(newValue, 0), 1))
            if clamped <= 0.001 {
                _ = client.setStrength(0, commit: true)
                _ = client.setEnabled(false)
                return
            }

            _ = client.setStrength(clamped, commit: true)
            if !isOn {
                _ = client.setEnabled(true)
                _ = client.setStrength(clamped, commit: true)
            }
        }
    }

    func adjust(deltaSteps: Double, stepSize: Double = 1.0 / 12.0) {
        let current = value
        let updated = current + deltaSteps * stepSize
        value = updated
    }

    private var isOn: Bool {
        guard let client, canReadStatus else { return false }
        var buffer = [UInt8](repeating: 0, count: StatusLayout.bufferSize)
        let didRead = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return client.getBlueLightStatus(base)
        }
        guard didRead else { return false }
        return buffer[StatusLayout.isOn] != 0
    }
}
