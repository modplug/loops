import Foundation

/// Codable representation of AudioComponentDescription for AU identification.
public struct AudioComponentInfo: Codable, Equatable, Sendable {
    public var componentType: UInt32
    public var componentSubType: UInt32
    public var componentManufacturer: UInt32

    public init(componentType: UInt32, componentSubType: UInt32, componentManufacturer: UInt32) {
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
    }
}
