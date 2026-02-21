import Foundation
import AVFoundation
import LoopsCore

/// Writes audio buffers to a CAF file in PCM Float32 format.
public final class CAFWriter {
    private var audioFile: AVAudioFile?
    public private(set) var sampleCount: Int64 = 0
    public let fileURL: URL

    public init(url: URL, sampleRate: Double, channelCount: UInt32 = 1) throws {
        self.fileURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: true
            )
        } catch {
            throw LoopsError.audioFileCreationFailed(path: url.path)
        }
    }

    /// Writes a buffer of audio data to the file.
    public func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let file = audioFile else { return }
        do {
            try file.write(from: buffer)
            sampleCount += Int64(buffer.frameLength)
        } catch {
            throw LoopsError.recordingWriteFailed(error.localizedDescription)
        }
    }

    /// Closes the file and returns the final sample count.
    public func close() -> Int64 {
        audioFile = nil
        return sampleCount
    }
}
