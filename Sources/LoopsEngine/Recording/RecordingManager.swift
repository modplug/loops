import Foundation
import AVFoundation
import LoopsCore

/// Thread-safe recording manager that installs taps on the audio engine's
/// input node to capture audio into CAF files.
public actor RecordingManager {
    public private(set) var isRecording: Bool = false
    private var currentWriter: CAFWriter?
    private var currentBufferQueue: RecordBufferQueue?
    private var inputNode: AVAudioInputNode?
    private let audioDirURL: URL

    /// Creates a RecordingManager that writes recordings to the given audio directory.
    public init(audioDirURL: URL) {
        self.audioDirURL = audioDirURL
    }

    /// Starts recording from the engine's input node.
    /// Returns the filename of the recording being created.
    public func startRecording(
        inputNode: AVAudioInputNode,
        sampleRate: Double
    ) throws -> String {
        guard !isRecording else { return "" }

        let filename = UUID().uuidString + ".caf"
        let fileURL = audioDirURL.appendingPathComponent(filename)

        let writer = try CAFWriter(url: fileURL, sampleRate: sampleRate)
        let bufferQueue = RecordBufferQueue(
            writer: writer,
            label: "com.loops.recording.queue.\(filename)"
        )
        currentWriter = writer
        currentBufferQueue = bufferQueue
        self.inputNode = inputNode

        let format = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let copiedBuffer = Self.copy(buffer: buffer) else { return }
            _ = bufferQueue.enqueue(copiedBuffer)
        }

        isRecording = true
        return filename
    }

    /// Stops the current recording and returns the SourceRecording metadata.
    public func stopRecording(sampleRate: Double) -> SourceRecording? {
        guard isRecording, let writer = currentWriter else { return nil }

        inputNode?.removeTap(onBus: 0)
        let sampleCount = currentBufferQueue?.finish() ?? writer.close()

        let recording = SourceRecording(
            filename: writer.fileURL.lastPathComponent,
            sampleRate: sampleRate,
            sampleCount: sampleCount
        )

        currentWriter = nil
        currentBufferQueue = nil
        inputNode = nil
        isRecording = false

        return recording
    }

    private nonisolated static func copy(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copied.frameLength = buffer.frameLength

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        for channel in 0..<channelCount {
            guard let src = buffer.floatChannelData?[channel],
                  let dst = copied.floatChannelData?[channel] else { continue }
            dst.update(from: src, count: frameCount)
        }
        return copied
    }
}
