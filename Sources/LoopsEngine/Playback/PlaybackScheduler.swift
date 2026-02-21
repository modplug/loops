import Foundation
import AVFoundation
import LoopsCore

/// Schedules playback of recorded containers on AVAudioPlayerNodes,
/// synchronized to the timeline's bar/beat grid.
public final class PlaybackScheduler: @unchecked Sendable {
    private let engine: AVAudioEngine
    private var playerNodes: [ID<Track>: AVAudioPlayerNode] = [:]
    private var audioFiles: [ID<SourceRecording>: AVAudioFile] = [:]
    private let audioDirURL: URL

    public init(engine: AVAudioEngine, audioDirURL: URL) {
        self.engine = engine
        self.audioDirURL = audioDirURL
    }

    /// Prepares playback for a song by creating player nodes for each track
    /// and loading audio files for all source recordings.
    public func prepare(song: Song, sourceRecordings: [ID<SourceRecording>: SourceRecording]) {
        cleanup()

        // Load audio files
        for (id, recording) in sourceRecordings {
            let fileURL = audioDirURL.appendingPathComponent(recording.filename)
            if let file = try? AVAudioFile(forReading: fileURL) {
                audioFiles[id] = file
            }
        }

        // Create player nodes for each track
        for track in song.tracks {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            playerNodes[track.id] = player

            // Apply track mix settings
            player.volume = track.isMuted ? 0.0 : track.volume
            player.pan = track.pan
        }
    }

    /// Schedules and starts playback from the given bar position.
    public func play(
        song: Song,
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        sampleRate: Double
    ) {
        let samplesPerBar = self.samplesPerBar(bpm: bpm, timeSignature: timeSignature, sampleRate: sampleRate)

        for track in song.tracks {
            guard let player = playerNodes[track.id] else { continue }
            if track.isMuted { continue }

            // Schedule each container that has a recording
            for container in track.containers {
                guard let recordingID = container.sourceRecordingID,
                      let audioFile = audioFiles[recordingID] else { continue }

                let containerStartSample = Int64(Double(container.startBar - 1) * samplesPerBar)
                let containerEndSample = Int64(Double(container.endBar - 1) * samplesPerBar)
                let playheadSample = Int64((fromBar - 1.0) * samplesPerBar)

                // Skip containers that end before the playhead
                if containerEndSample <= playheadSample { continue }

                let startOffset: AVAudioFramePosition
                let frameCount: AVAudioFrameCount
                let scheduleDelay: AVAudioFramePosition

                if playheadSample >= containerStartSample {
                    // Playhead is inside this container
                    startOffset = AVAudioFramePosition(playheadSample - containerStartSample)
                    let remaining = containerEndSample - playheadSample
                    let fileFrames = audioFile.length - startOffset
                    frameCount = AVAudioFrameCount(min(remaining, fileFrames))
                    scheduleDelay = 0
                } else {
                    // Container starts in the future
                    startOffset = 0
                    let containerLength = containerEndSample - containerStartSample
                    let fileFrames = audioFile.length
                    frameCount = AVAudioFrameCount(min(containerLength, fileFrames))
                    scheduleDelay = AVAudioFramePosition(containerStartSample - playheadSample)
                }

                guard frameCount > 0 else { continue }

                // For fill loop mode: schedule repeating segments
                if container.loopSettings.loopCount == .fill {
                    scheduleLoopingPlayback(
                        player: player,
                        audioFile: audioFile,
                        containerStartSample: containerStartSample,
                        containerEndSample: containerEndSample,
                        playheadSample: playheadSample,
                        samplesPerBar: samplesPerBar
                    )
                } else {
                    player.scheduleSegment(
                        audioFile,
                        startingFrame: startOffset,
                        frameCount: frameCount,
                        at: nil
                    )
                }
            }

            player.play()
        }
    }

    /// Stops all playback.
    public func stop() {
        for (_, player) in playerNodes {
            player.stop()
        }
    }

    /// Cleans up all player nodes and audio files.
    public func cleanup() {
        for (_, player) in playerNodes {
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        playerNodes.removeAll()
        audioFiles.removeAll()
    }

    /// Updates track mix parameters (volume, pan, mute).
    public func updateTrackMix(trackID: ID<Track>, volume: Float, pan: Float, isMuted: Bool) {
        guard let player = playerNodes[trackID] else { return }
        player.volume = isMuted ? 0.0 : volume
        player.pan = pan
    }

    // MARK: - Private

    private func samplesPerBar(bpm: Double, timeSignature: TimeSignature, sampleRate: Double) -> Double {
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBeat = 60.0 / bpm
        return beatsPerBar * secondsPerBeat * sampleRate
    }

    private func scheduleLoopingPlayback(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        containerStartSample: Int64,
        containerEndSample: Int64,
        playheadSample: Int64,
        samplesPerBar: Double
    ) {
        let containerLengthSamples = containerEndSample - containerStartSample
        let fileLengthSamples = audioFile.length

        guard fileLengthSamples > 0, containerLengthSamples > 0 else { return }

        var position = max(playheadSample, containerStartSample) - containerStartSample
        let endPosition = containerLengthSamples

        while position < endPosition {
            let positionInLoop = position % fileLengthSamples
            let remainingInLoop = fileLengthSamples - positionInLoop
            let remainingInContainer = endPosition - position
            let framesToPlay = min(remainingInLoop, remainingInContainer)

            guard framesToPlay > 0 else { break }

            player.scheduleSegment(
                audioFile,
                startingFrame: AVAudioFramePosition(positionInLoop),
                frameCount: AVAudioFrameCount(framesToPlay),
                at: nil
            )

            position += framesToPlay
        }
    }
}
