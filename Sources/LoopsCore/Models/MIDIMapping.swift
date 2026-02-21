import Foundation

public enum MappableControl: String, Codable, Sendable, CaseIterable {
    case playPause, stop, recordArm, nextSong, previousSong, metronomeToggle
}

public enum MIDITrigger: Codable, Equatable, Sendable {
    case controlChange(channel: UInt8, controller: UInt8)
    case noteOn(channel: UInt8, note: UInt8)
}

public struct MIDIMapping: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDIMapping>
    public var control: MappableControl
    public var trigger: MIDITrigger
    public var sourceDeviceName: String?

    public init(
        id: ID<MIDIMapping> = ID(),
        control: MappableControl,
        trigger: MIDITrigger,
        sourceDeviceName: String? = nil
    ) {
        self.id = id
        self.control = control
        self.trigger = trigger
        self.sourceDeviceName = sourceDeviceName
    }
}
