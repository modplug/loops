import Foundation
import AVFoundation
import LoopsCore

/// Schedules playback of recorded containers on AVAudioPlayerNodes,
/// synchronized to the timeline's bar/beat grid.
///
/// Architecture: each active container gets its own
/// `AVAudioPlayerNode → [AU Effects] → Track AVAudioMixerNode → mainMixerNode`.
/// When a container's effect chain is bypassed (or empty), the player routes
/// directly to the track mixer.
public final class PlaybackScheduler: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let audioUnitHost: AudioUnitHost
    private var audioFiles: [ID<SourceRecording>: AVAudioFile] = [:]
    private let audioDirURL: URL

    /// Per-container audio subgraph.
    private struct ContainerSubgraph {
        let playerNode: AVAudioPlayerNode
        let effectUnits: [AVAudioUnit]
        let trackMixer: AVAudioMixerNode
    }

    /// Track-level mixer nodes (one per track, routes to mainMixerNode).
    private var trackMixers: [ID<Track>: AVAudioMixerNode] = [:]

    /// All active container subgraphs, keyed by container ID.
    private var containerSubgraphs: [ID<Container>: ContainerSubgraph] = [:]

    public init(engine: AVAudioEngine, audioDirURL: URL) {
        self.engine = engine
        self.audioUnitHost = AudioUnitHost(engine: engine)
        self.audioDirURL = audioDirURL
    }

    /// Prepares playback for a song by creating track mixers and loading audio files.
    /// AU effects for containers are pre-instantiated here.
    public func prepare(song: Song, sourceRecordings: [ID<SourceRecording>: SourceRecording]) async {
        cleanup()

        // Load audio files
        for (id, recording) in sourceRecordings {
            let fileURL = audioDirURL.appendingPathComponent(recording.filename)
            if let file = try? AVAudioFile(forReading: fileURL) {
                audioFiles[id] = file
            }
        }

        // Create a mixer node per track, connected to the main mixer
        for track in song.tracks {
            let trackMixer = AVAudioMixerNode()
            engine.attach(trackMixer)
            engine.connect(trackMixer, to: engine.mainMixerNode, format: nil)
            trackMixer.volume = track.isMuted ? 0.0 : track.volume
            trackMixer.pan = track.pan
            trackMixers[track.id] = trackMixer

            // Pre-instantiate per-container subgraphs
            for container in track.containers {
                guard container.sourceRecordingID != nil else { continue }
                await buildContainerSubgraph(container: container, trackMixer: trackMixer)
            }
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
            if track.isMuted { continue }

            // Schedule each container that has a recording
            for container in track.containers {
                guard let recordingID = container.sourceRecordingID,
                      let audioFile = audioFiles[recordingID],
                      let subgraph = containerSubgraphs[container.id] else { continue }

                let containerStartSample = Int64(Double(container.startBar - 1) * samplesPerBar)
                let containerEndSample = Int64(Double(container.endBar - 1) * samplesPerBar)
                let playheadSample = Int64((fromBar - 1.0) * samplesPerBar)

                // Skip containers that end before the playhead
                if containerEndSample <= playheadSample { continue }

                let startOffset: AVAudioFramePosition
                let frameCount: AVAudioFrameCount

                if playheadSample >= containerStartSample {
                    // Playhead is inside this container
                    startOffset = AVAudioFramePosition(playheadSample - containerStartSample)
                    let remaining = containerEndSample - playheadSample
                    let fileFrames = audioFile.length - startOffset
                    frameCount = AVAudioFrameCount(min(remaining, fileFrames))
                } else {
                    // Container starts in the future
                    startOffset = 0
                    let containerLength = containerEndSample - containerStartSample
                    let fileFrames = audioFile.length
                    frameCount = AVAudioFrameCount(min(containerLength, fileFrames))
                }

                guard frameCount > 0 else { continue }

                // For fill loop mode: schedule repeating segments
                if container.loopSettings.loopCount == .fill {
                    scheduleLoopingPlayback(
                        player: subgraph.playerNode,
                        audioFile: audioFile,
                        containerStartSample: containerStartSample,
                        containerEndSample: containerEndSample,
                        playheadSample: playheadSample,
                        samplesPerBar: samplesPerBar
                    )
                } else {
                    subgraph.playerNode.scheduleSegment(
                        audioFile,
                        startingFrame: startOffset,
                        frameCount: frameCount,
                        at: nil
                    )
                }

                subgraph.playerNode.play()
            }
        }
    }

    /// Stops all playback.
    public func stop() {
        for (_, subgraph) in containerSubgraphs {
            subgraph.playerNode.stop()
        }
    }

    /// Cleans up all nodes and audio files.
    public func cleanup() {
        for (_, subgraph) in containerSubgraphs {
            subgraph.playerNode.stop()
            engine.disconnectNodeOutput(subgraph.playerNode)
            engine.detach(subgraph.playerNode)
            for unit in subgraph.effectUnits {
                engine.disconnectNodeOutput(unit)
                engine.detach(unit)
            }
        }
        containerSubgraphs.removeAll()

        for (_, mixer) in trackMixers {
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }
        trackMixers.removeAll()

        audioFiles.removeAll()
    }

    /// Updates track mix parameters (volume, pan, mute).
    public func updateTrackMix(trackID: ID<Track>, volume: Float, pan: Float, isMuted: Bool) {
        guard let mixer = trackMixers[trackID] else { return }
        mixer.volume = isMuted ? 0.0 : volume
        mixer.pan = pan
    }

    // MARK: - Private

    /// Builds the per-container audio subgraph:
    /// `AVAudioPlayerNode → [AU Effects (if not bypassed)] → trackMixer`
    private func buildContainerSubgraph(container: Container, trackMixer: AVAudioMixerNode) async {
        let player = AVAudioPlayerNode()
        engine.attach(player)

        var effectUnits: [AVAudioUnit] = []

        // Load AU effects if the chain is not bypassed
        if !container.isEffectChainBypassed {
            for effect in container.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                guard !effect.isBypassed else { continue }
                if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                    engine.attach(unit)
                    // Restore preset if available
                    if let presetData = effect.presetData {
                        try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                    }
                    effectUnits.append(unit)
                }
            }
        }

        // Build the chain: player → [effects...] → trackMixer
        if effectUnits.isEmpty {
            engine.connect(player, to: trackMixer, format: nil)
        } else {
            engine.connect(player, to: effectUnits[0], format: nil)
            for i in 0..<(effectUnits.count - 1) {
                engine.connect(effectUnits[i], to: effectUnits[i + 1], format: nil)
            }
            engine.connect(effectUnits[effectUnits.count - 1], to: trackMixer, format: nil)
        }

        containerSubgraphs[container.id] = ContainerSubgraph(
            playerNode: player,
            effectUnits: effectUnits,
            trackMixer: trackMixer
        )
    }

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
