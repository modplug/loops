import Foundation

public enum MappableControl: String, Codable, Sendable, CaseIterable {
    case playPause, stop, recordArm, nextSong, previousSong, metronomeToggle
}

public enum MIDITrigger: Codable, Equatable, Hashable, Sendable {
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

/// Maps a MIDI CC trigger to an effect parameter, with value scaling.
public struct MIDIParameterMapping: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDIParameterMapping>
    public var trigger: MIDITrigger
    public var targetPath: EffectPath
    public var minValue: Float
    public var maxValue: Float

    public init(
        id: ID<MIDIParameterMapping> = ID(),
        trigger: MIDITrigger,
        targetPath: EffectPath,
        minValue: Float = 0.0,
        maxValue: Float = 1.0
    ) {
        self.id = id
        self.trigger = trigger
        self.targetPath = targetPath
        self.minValue = minValue
        self.maxValue = maxValue
    }

    /// Scales a CC value (0–127) to the parameter's min–max range.
    public func scaledValue(ccValue: UInt8) -> Float {
        minValue + (Float(ccValue) / 127.0) * (maxValue - minValue)
    }
}
