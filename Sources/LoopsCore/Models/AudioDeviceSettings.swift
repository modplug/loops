import Foundation

public struct AudioDeviceSettings: Codable, Equatable, Sendable {
    public var inputDeviceUID: String?
    public var outputDeviceUID: String?
    /// 64, 128, 256, 512, or 1024
    public var bufferSize: Int

    public init(
        inputDeviceUID: String? = nil,
        outputDeviceUID: String? = nil,
        bufferSize: Int = 256
    ) {
        self.inputDeviceUID = inputDeviceUID
        self.outputDeviceUID = outputDeviceUID
        self.bufferSize = bufferSize
    }
}
