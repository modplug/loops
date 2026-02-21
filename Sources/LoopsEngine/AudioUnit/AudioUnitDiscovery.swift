import Foundation
import AVFoundation
import AudioToolbox
import LoopsCore

/// Discovered Audio Unit component information.
public struct AudioUnitInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let manufacturerName: String
    public let componentInfo: AudioComponentInfo
    public let componentType: UInt32

    public init(name: String, manufacturerName: String, componentInfo: AudioComponentInfo, componentType: UInt32) {
        self.id = "\(componentInfo.componentType)-\(componentInfo.componentSubType)-\(componentInfo.componentManufacturer)"
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentInfo = componentInfo
        self.componentType = componentType
    }
}

/// Discovers available Audio Unit effect and instrument plugins.
public final class AudioUnitDiscovery: Sendable {
    public init() {}

    /// Returns all available AU effect plugins.
    public func effects() -> [AudioUnitInfo] {
        discover(type: kAudioUnitType_Effect)
    }

    /// Returns all available AU instrument plugins.
    public func instruments() -> [AudioUnitInfo] {
        discover(type: kAudioUnitType_MusicDevice)
    }

    private func discover(type: UInt32) -> [AudioUnitInfo] {
        let description = AudioComponentDescription(
            componentType: type,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let manager = AVAudioUnitComponentManager.shared()
        let components = manager.components(matching: description)

        return components.map { component in
            let info = AudioComponentInfo(
                componentType: component.audioComponentDescription.componentType,
                componentSubType: component.audioComponentDescription.componentSubType,
                componentManufacturer: component.audioComponentDescription.componentManufacturer
            )
            return AudioUnitInfo(
                name: component.name,
                manufacturerName: component.manufacturerName,
                componentInfo: info,
                componentType: type
            )
        }.sorted { $0.name < $1.name }
    }
}
