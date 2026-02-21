import Foundation
import CoreAudio
import LoopsCore

/// Represents an audio device discovered via CoreAudio.
public struct AudioDevice: Identifiable, Sendable, Equatable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let hasInput: Bool
    public let hasOutput: Bool
    public let supportedSampleRates: [Double]

    public init(id: AudioDeviceID, uid: String, name: String, hasInput: Bool, hasOutput: Bool, supportedSampleRates: [Double]) {
        self.id = id
        self.uid = uid
        self.name = name
        self.hasInput = hasInput
        self.hasOutput = hasOutput
        self.supportedSampleRates = supportedSampleRates
    }
}

/// Enumerates and manages CoreAudio devices.
public final class DeviceManager: Sendable {

    public init() {}

    /// Returns all audio devices on the system.
    public func allDevices() -> [AudioDevice] {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &propertySize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &propertySize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceInfo(for: $0) }
    }

    /// Returns only input-capable devices.
    public func inputDevices() -> [AudioDevice] {
        allDevices().filter { $0.hasInput }
    }

    /// Returns only output-capable devices.
    public func outputDevices() -> [AudioDevice] {
        allDevices().filter { $0.hasOutput }
    }

    /// Returns the system default input device ID.
    public func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Returns the system default output device ID.
    public func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Looks up a device by its UID string.
    public func device(forUID uid: String) -> AudioDevice? {
        allDevices().first { $0.uid == uid }
    }

    // MARK: - Private

    private func deviceInfo(for deviceID: AudioDeviceID) -> AudioDevice? {
        guard let name = deviceName(for: deviceID),
              let uid = deviceUID(for: deviceID) else {
            return nil
        }

        let hasInput = channelCount(for: deviceID, scope: kAudioObjectPropertyScopeInput) > 0
        let hasOutput = channelCount(for: deviceID, scope: kAudioObjectPropertyScopeOutput) > 0

        let sampleRates = supportedSampleRates(for: deviceID)

        return AudioDevice(
            id: deviceID,
            uid: uid,
            name: name,
            hasInput: hasInput,
            hasOutput: hasOutput,
            supportedSampleRates: sampleRates
        )
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        return status == noErr ? name as String : nil
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        return status == noErr ? uid as String : nil
    }

    private func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return 0 }

        // Allocate raw memory with proper size for the variable-length AudioBufferList
        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }

        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let result = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
        guard result == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        var totalChannels = 0
        for buffer in bufferList {
            totalChannels += Int(buffer.mNumberChannels)
        }
        return totalChannels
    }

    private func supportedSampleRates(for deviceID: AudioDeviceID) -> [Double] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        let result = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges)
        guard result == noErr else { return [] }

        var rates = Set<Double>()
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                for rate in [44100.0, 48000.0, 88200.0, 96000.0] {
                    if rate >= range.mMinimum && rate <= range.mMaximum {
                        rates.insert(rate)
                    }
                }
            }
        }
        return rates.sorted()
    }
}
