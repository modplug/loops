import Foundation
import AVFoundation
import LoopsCore

/// Supported export audio formats.
public enum ExportFormat: String, CaseIterable, Sendable {
    case wav16 = "WAV 16-bit"
    case wav24 = "WAV 24-bit"
    case aiff = "AIFF"

    public var fileExtension: String {
        switch self {
        case .wav16, .wav24: return "wav"
        case .aiff: return "aiff"
        }
    }

    public var bitDepth: Int {
        switch self {
        case .wav16: return 16
        case .wav24, .aiff: return 24
        }
    }

    public var isFloat: Bool { false }

    public var isBigEndian: Bool { self == .aiff }
}

/// Supported export sample rates.
public enum ExportSampleRate: Double, CaseIterable, Sendable {
    case rate44100 = 44100
    case rate48000 = 48000

    public var displayName: String {
        switch self {
        case .rate44100: return "44.1 kHz"
        case .rate48000: return "48 kHz"
        }
    }
}

/// Configuration for an audio export operation.
public struct ExportConfiguration: Sendable {
    public var format: ExportFormat
    public var sampleRate: ExportSampleRate
    public var destinationURL: URL

    public init(format: ExportFormat, sampleRate: ExportSampleRate, destinationURL: URL) {
        self.format = format
        self.sampleRate = sampleRate
        self.destinationURL = destinationURL
    }
}

/// Renders a song's audio offline to a file.
public final class OfflineRenderer {
    private let audioDirURL: URL
    private let chunkSize: AVAudioFrameCount = 4096

    public init(audioDirURL: URL) {
        self.audioDirURL = audioDirURL
    }

    /// Calculates total song length in bars from the furthest container end.
    public static func songLengthBars(song: Song) -> Int {
        var maxEnd = 0
        for track in song.tracks {
            for container in track.containers {
                maxEnd = max(maxEnd, container.endBar)
            }
        }
        return maxEnd > 0 ? maxEnd - 1 : 0
    }

    /// Calculates the number of samples in one bar.
    public static func samplesPerBar(bpm: Double, timeSignature: TimeSignature, sampleRate: Double) -> Double {
        let secondsPerBeat = 60.0 / bpm
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        return beatsPerBar * secondsPerBeat * sampleRate
    }

    /// Renders the song to an audio file.
    /// - Parameters:
    ///   - song: The song to render.
    ///   - sourceRecordings: Map of recording IDs to source recordings.
    ///   - config: Export configuration.
    ///   - progress: Optional callback reporting 0.0...1.0 progress.
    /// - Returns: The URL of the rendered file.
    @discardableResult
    public func render(
        song: Song,
        sourceRecordings: [ID<SourceRecording>: SourceRecording],
        config: ExportConfiguration,
        progress: ((Double) -> Void)? = nil
    ) throws -> URL {
        let totalBars = Self.songLengthBars(song: song)
        guard totalBars > 0 else {
            throw LoopsError.exportFailed(reason: "Song has no content to export")
        }

        let sampleRate = config.sampleRate.rawValue
        let spb = Self.samplesPerBar(
            bpm: song.tempo.bpm,
            timeSignature: song.timeSignature,
            sampleRate: sampleRate
        )
        let totalFrames = AVAudioFrameCount(Double(totalBars) * spb)

        // Determine which tracks are audible
        let hasSolo = song.tracks.contains { $0.isSoloed }
        let audibleTracks = song.tracks.filter { track in
            if track.isMuted { return false }
            if hasSolo && !track.isSoloed { return false }
            return true
        }

        // Preload audio buffers for each source recording
        var bufferCache: [ID<SourceRecording>: AVAudioPCMBuffer] = [:]
        for track in audibleTracks {
            for container in track.containers {
                guard let recID = container.sourceRecordingID,
                      let recording = sourceRecordings[recID],
                      bufferCache[recID] == nil else { continue }

                let fileURL = audioDirURL.appendingPathComponent(recording.filename)
                guard let audioFile = try? AVAudioFile(forReading: fileURL) else { continue }

                let processingFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: audioFile.fileFormat.sampleRate,
                    channels: audioFile.fileFormat.channelCount,
                    interleaved: false
                )!
                let buf = AVAudioPCMBuffer(
                    pcmFormat: processingFormat,
                    frameCapacity: AVAudioFrameCount(audioFile.length)
                )!
                try? audioFile.read(into: buf)
                bufferCache[recID] = buf
            }
        }

        // Create output file
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!

        let outputSettings = createOutputSettings(config: config)
        let outputFile = try AVAudioFile(
            forWriting: config.destinationURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Render in chunks
        var framesWritten: AVAudioFrameCount = 0
        while framesWritten < totalFrames {
            let framesToProcess = min(chunkSize, totalFrames - framesWritten)
            let chunk = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToProcess)!
            chunk.frameLength = framesToProcess

            // Clear buffer
            if let data = chunk.floatChannelData {
                for ch in 0..<2 {
                    for i in 0..<Int(framesToProcess) {
                        data[ch][i] = 0
                    }
                }
            }

            // Mix all audible tracks
            for track in audibleTracks {
                mixTrack(
                    track: track,
                    into: chunk,
                    startFrame: framesWritten,
                    samplesPerBar: spb,
                    sampleRate: sampleRate,
                    sourceRecordings: sourceRecordings,
                    bufferCache: bufferCache
                )
            }

            try outputFile.write(from: chunk)
            framesWritten += framesToProcess

            let p = Double(framesWritten) / Double(totalFrames)
            progress?(min(p, 1.0))
        }

        return config.destinationURL
    }

    // MARK: - Private

    private func mixTrack(
        track: Track,
        into output: AVAudioPCMBuffer,
        startFrame: AVAudioFrameCount,
        samplesPerBar: Double,
        sampleRate: Double,
        sourceRecordings: [ID<SourceRecording>: SourceRecording],
        bufferCache: [ID<SourceRecording>: AVAudioPCMBuffer]
    ) {
        guard let outData = output.floatChannelData else { return }
        let outFrames = Int(output.frameLength)

        let volume = track.volume
        let pan = track.pan
        let leftGain = volume * (pan <= 0 ? 1.0 : 1.0 - pan)
        let rightGain = volume * (pan >= 0 ? 1.0 : 1.0 + pan)

        for container in track.containers {
            guard let recID = container.sourceRecordingID,
                  let buffer = bufferCache[recID] else { continue }

            let containerVolume = container.volumeOverride ?? 1.0
            let containerPan = container.panOverride ?? 0.0
            let cLeftGain = leftGain * containerVolume * (containerPan <= 0 ? 1.0 : 1.0 - containerPan)
            let cRightGain = rightGain * containerVolume * (containerPan >= 0 ? 1.0 : 1.0 + containerPan)

            let containerStartSample = Int(Double(container.startBar - 1) * samplesPerBar)
            let containerLengthSamples = Int(Double(container.lengthBars) * samplesPerBar)
            let containerEndSample = containerStartSample + containerLengthSamples

            let chunkStart = Int(startFrame)
            let chunkEnd = chunkStart + outFrames

            // Check overlap
            guard containerStartSample < chunkEnd && containerEndSample > chunkStart else { continue }

            let overlapStart = max(containerStartSample, chunkStart)
            let overlapEnd = min(containerEndSample, chunkEnd)

            guard let srcData = buffer.floatChannelData else { continue }
            let srcChannels = Int(buffer.format.channelCount)
            let srcFrames = Int(buffer.frameLength)

            for frame in overlapStart..<overlapEnd {
                let outIdx = frame - chunkStart
                let srcIdx = (frame - containerStartSample) % max(srcFrames, 1)
                guard srcIdx < srcFrames else { continue }

                let sample = srcData[0][srcIdx]
                outData[0][outIdx] += sample * cLeftGain
                outData[1][outIdx] += (srcChannels > 1 ? srcData[1][srcIdx] : sample) * cRightGain
            }
        }
    }

    private func createOutputSettings(config: ExportConfiguration) -> [String: Any] {
        let sampleRate = config.sampleRate.rawValue
        let bitDepth = config.format.bitDepth
        let formatID: AudioFormatID = config.format == .aiff ? kAudioFormatLinearPCM : kAudioFormatLinearPCM

        var formatFlags: AudioFormatFlags = kLinearPCMFormatFlagIsPacked
        if config.format.isBigEndian {
            formatFlags |= kLinearPCMFormatFlagIsBigEndian
        }
        formatFlags |= kLinearPCMFormatFlagIsSignedInteger

        return [
            AVFormatIDKey: formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: config.format.isBigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }
}
