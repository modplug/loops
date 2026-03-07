import Foundation
import Metal

final class PlaybackGridReusableBuffer {
    private(set) var buffer: MTLBuffer?
    private(set) var capacity = 0

    func write<T>(_ values: [T], device: MTLDevice) -> MTLBuffer? {
        guard !values.isEmpty else {
            buffer = nil
            capacity = 0
            return nil
        }

        let length = values.count * MemoryLayout<T>.stride
        if buffer == nil || capacity < length {
            capacity = max(length, max(4096, capacity * 2))
            buffer = device.makeBuffer(length: capacity, options: .storageModeShared)
        }

        guard let buffer else { return nil }
        values.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            memcpy(buffer.contents(), base, ptr.count)
        }
        return buffer
    }
}
