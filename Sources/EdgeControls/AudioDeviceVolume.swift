import CoreAudio
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AudioDeviceVolume
//
// Reads and writes the volume scalar (0...1) of the system default CoreAudio
// output (speakers/headphones) or input (microphone) devices.
// ─────────────────────────────────────────────────────────────────────────────

final class AudioDeviceVolume {

    typealias DeviceProvider = () -> AudioObjectID?

    private static let virtualMainVolumeSelector: AudioObjectPropertySelector = 0x766D_7663 // 'vmvc'

    private let scope: AudioObjectPropertyScope
    private let deviceProvider: DeviceProvider

    init(scope: AudioObjectPropertyScope, device: @escaping DeviceProvider) {
        self.scope = scope
        self.deviceProvider = device
    }

    /// Default output device (speakers, headphones).
    static func defaultOutput() -> AudioDeviceVolume {
        AudioDeviceVolume(scope: kAudioDevicePropertyScopeOutput) {
            defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        }
    }

    /// Default input device (microphone).
    static func defaultInput() -> AudioDeviceVolume {
        AudioDeviceVolume(scope: kAudioDevicePropertyScopeInput) {
            defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        }
    }

    // MARK: - Reading and writing

    var isSettable: Bool {
        guard let device = deviceProvider() else { return false }
        return isSettable(mainVolumeAddress, on: device) || !settableChannels(of: device).isEmpty
    }

    func read() -> Double? {
        guard let device = deviceProvider() else { return nil }

        if let scalar = scalar(at: mainVolumeAddress, on: device) {
            return Double(scalar)
        }

        let channels = settableChannels(of: device)
        guard !channels.isEmpty else { return nil }

        let readings = channels.compactMap { scalar(at: channelVolumeAddress($0), on: device) }
        guard !readings.isEmpty else { return nil }
        return Double(readings.reduce(0, +) / Float(readings.count))
    }

    func write(_ newValue: Double) {
        guard let device = deviceProvider() else { return }
        let scalar = Float(min(max(newValue, 0), 1))

        if isSettable(mainVolumeAddress, on: device) {
            setScalar(scalar, at: mainVolumeAddress, on: device)
        } else {
            for channel in settableChannels(of: device) {
                setScalar(scalar, at: channelVolumeAddress(channel), on: device)
            }
        }
    }

    func unmute() {
        guard let device = deviceProvider() else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue else { return }

        var muted: UInt32 = 0
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted
        )
    }

    // MARK: - CoreAudio plumbing

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private var mainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: Self.virtualMainVolumeSelector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func channelVolumeAddress(_ channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope,
            mElement: channel
        )
    }

    private func settableChannels(of device: AudioObjectID) -> [UInt32] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var channels: (UInt32, UInt32) = (1, 2)
        var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &channels)

        return [channels.0, channels.1].filter {
            isSettable(channelVolumeAddress($0), on: device)
        }
    }

    private func scalar(at address: AudioObjectPropertyAddress, on device: AudioObjectID) -> Float? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var scalar: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &scalar)
        return status == noErr ? scalar : nil
    }

    private func setScalar(_ scalar: Float, at address: AudioObjectPropertyAddress, on device: AudioObjectID) {
        var address = address
        var scalar = scalar
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &scalar
        )
        if status != noErr {
            AppLogger.debug("[AudioDeviceVolume] Setting scalar failed: status \(status)")
        }
    }

    private func isSettable(_ address: AudioObjectPropertyAddress, on device: AudioObjectID) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }

        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(device, &address, &settable)
        return status == noErr && settable.boolValue
    }
}
