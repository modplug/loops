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

/// Describes a single parameter exposed by an Audio Unit.
public struct AudioUnitParameterInfo: Identifiable, Sendable {
    public let id: String
    public let address: UInt64
    public let displayName: String
    public let groupName: String
    public let minValue: Float
    public let maxValue: Float
    public let defaultValue: Float
    public let unit: String

    public init(address: UInt64, displayName: String, groupName: String = "", minValue: Float, maxValue: Float, defaultValue: Float, unit: String) {
        self.id = "\(address)"
        self.address = address
        self.displayName = displayName
        self.groupName = groupName
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.unit = unit
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

    /// Enumerates all parameters for an Audio Unit component.
    /// Must be called from a background thread — instantiates the AU temporarily.
    public func parameters(for component: AudioComponentInfo) async -> [AudioUnitParameterInfo] {
        let description = AudioComponentDescription(
            componentType: component.componentType,
            componentSubType: component.componentSubType,
            componentManufacturer: component.componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        do {
            let audioUnit = try await AUAudioUnit.instantiate(with: description, options: [])
            let tree = audioUnit.parameterTree
            guard let allParams = tree?.allParameters else { return [] }

            // Build address→group mapping from the tree's group structure
            var addressToGroup: [AUParameterAddress: String] = [:]
            func walkGroups(_ group: AUParameterGroup) {
                for child in group.children {
                    if let param = child as? AUParameter {
                        addressToGroup[param.address] = group.displayName
                    } else if let subGroup = child as? AUParameterGroup {
                        walkGroups(subGroup)
                    }
                }
            }
            if let tree {
                for child in tree.children {
                    if let group = child as? AUParameterGroup {
                        walkGroups(group)
                    }
                }
            }

            return allParams.map { param in
                AudioUnitParameterInfo(
                    address: param.address,
                    displayName: param.displayName,
                    groupName: addressToGroup[param.address] ?? "",
                    minValue: param.minValue,
                    maxValue: param.maxValue,
                    defaultValue: param.value,
                    unit: param.unitName ?? ""
                )
            }
        } catch {
            return []
        }
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
