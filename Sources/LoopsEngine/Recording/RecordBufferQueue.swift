import Foundation
import AVFoundation

final class RecordBufferQueue {
    private let writer: CAFWriter
    private let queue: DispatchQueue
    private let lock = NSLock()
    private let maxPendingBuffers: Int
    private let writeDelayNanoseconds: UInt64
    private var pendingBuffers = 0
    private(set) var droppedBufferCount = 0
    private(set) var droppedSampleCount: Int64 = 0

    init(
        writer: CAFWriter,
        label: String,
        maxPendingBuffers: Int = 32,
        writeDelayNanoseconds: UInt64 = 0
    ) {
        self.writer = writer
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
        self.maxPendingBuffers = maxPendingBuffers
        self.writeDelayNanoseconds = writeDelayNanoseconds
    }

    @discardableResult
    func enqueue(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        guard pendingBuffers < maxPendingBuffers else {
            droppedBufferCount += 1
            droppedSampleCount += Int64(buffer.frameLength)
            lock.unlock()
            return false
        }
        pendingBuffers += 1
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                self.lock.unlock()
            }
            if self.writeDelayNanoseconds > 0 {
                Thread.sleep(forTimeInterval: Double(self.writeDelayNanoseconds) / 1_000_000_000.0)
            }
            try? self.writer.write(buffer)
        }
        return true
    }

    func finish() -> Int64 {
        queue.sync {}
        return writer.close()
    }
}
