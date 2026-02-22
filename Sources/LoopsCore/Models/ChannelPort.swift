import Foundation

/// Phantom type for input direction.
public enum InputDirection: Sendable {}

/// Phantom type for output direction.
public enum OutputDirection: Sendable {}

/// Channel layout: mono (single channel) or stereo (pair).
public enum ChannelLayout: String, Codable, Sendable {
    case mono
    case stereo
}

/// A named audio port representing one or two channels on a device.
///
/// Phantom-typed by `Direction` (`InputDirection` / `OutputDirection`)
/// so that input and output ports cannot be accidentally mixed.
///
/// The stable `id` format is `"{deviceUID}:{streamIndex}:{channelOffset}"`
/// and survives serialization across sessions.
public struct ChannelPort<Direction: Sendable>: Codable, Equatable, Sendable, Identifiable, Hashable {
    /// CoreAudio device UID that owns this port.
    public var deviceUID: String
    /// Index of the stream within the device's stream configuration.
    public var streamIndex: Int
    /// Channel offset within the stream (0-based).
    public var channelOffset: Int
    /// Whether this port is mono or stereo.
    public var layout: ChannelLayout
    /// Auto-generated name (e.g. "In 1/2", "Out 3").
    public var defaultName: String
    /// User-editable custom name (e.g. "Guitar", "Main Mix").
    public var customName: String?

    /// Stable identifier: `"{deviceUID}:{streamIndex}:{channelOffset}"`.
    public var id: String {
        "\(deviceUID):\(streamIndex):\(channelOffset)"
    }

    /// Display name: custom name if set, otherwise the default name.
    public var displayName: String {
        customName ?? defaultName
    }

    public init(
        deviceUID: String,
        streamIndex: Int,
        channelOffset: Int,
        layout: ChannelLayout,
        defaultName: String,
        customName: String? = nil
    ) {
        self.deviceUID = deviceUID
        self.streamIndex = streamIndex
        self.channelOffset = channelOffset
        self.layout = layout
        self.defaultName = defaultName
        self.customName = customName
    }
}

/// An input port on an audio device.
public typealias InputPort = ChannelPort<InputDirection>

/// An output port on an audio device.
public typealias OutputPort = ChannelPort<OutputDirection>
