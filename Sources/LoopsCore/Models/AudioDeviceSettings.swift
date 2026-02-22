import Foundation

public struct AudioDeviceSettings: Codable, Equatable, Sendable {
    /// UID of the single selected audio interface (nil = system default).
    public var deviceUID: String?
    /// Preferred sample rate (nil = device default).
    public var sampleRate: Double?
    /// 64, 128, 256, 512, or 1024
    public var bufferSize: Int
    /// Named input ports on the selected device.
    public var inputPorts: [InputPort]
    /// Named output ports on the selected device.
    public var outputPorts: [OutputPort]

    public init(
        deviceUID: String? = nil,
        sampleRate: Double? = nil,
        bufferSize: Int = 256,
        inputPorts: [InputPort] = [],
        outputPorts: [OutputPort] = []
    ) {
        self.deviceUID = deviceUID
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.inputPorts = inputPorts
        self.outputPorts = outputPorts
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case deviceUID
        case sampleRate
        case bufferSize
        // Legacy keys
        case inputDeviceUID
        case outputDeviceUID
        // New keys
        case inputPorts
        case outputPorts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        bufferSize = try container.decodeIfPresent(Int.self, forKey: .bufferSize) ?? 256
        sampleRate = try container.decodeIfPresent(Double.self, forKey: .sampleRate)
        inputPorts = try container.decodeIfPresent([InputPort].self, forKey: .inputPorts) ?? []
        outputPorts = try container.decodeIfPresent([OutputPort].self, forKey: .outputPorts) ?? []

        // Try new single-device key first, then fall back to legacy output device UID
        if let uid = try container.decodeIfPresent(String.self, forKey: .deviceUID) {
            deviceUID = uid
        } else if let legacyOutput = try container.decodeIfPresent(String.self, forKey: .outputDeviceUID) {
            deviceUID = legacyOutput
        } else {
            deviceUID = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(deviceUID, forKey: .deviceUID)
        try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
        try container.encode(bufferSize, forKey: .bufferSize)
        try container.encode(inputPorts, forKey: .inputPorts)
        try container.encode(outputPorts, forKey: .outputPorts)
    }
}
