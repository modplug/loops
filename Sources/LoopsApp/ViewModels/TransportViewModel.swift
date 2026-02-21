import SwiftUI
import LoopsCore
import LoopsEngine

/// Bridges TransportManager state to the SwiftUI view layer.
@Observable
@MainActor
public final class TransportViewModel {
    public var isPlaying: Bool = false
    public var isRecordArmed: Bool = false
    public var isMetronomeEnabled: Bool = false
    public var playheadBar: Double = 1.0
    public var bpm: Double = 120.0
    public var timeSignature: TimeSignature = TimeSignature()

    private let transport: TransportManager

    public init(transport: TransportManager) {
        self.transport = transport
        syncFromTransport()
        transport.onPositionUpdate = { [weak self] bar in
            Task { @MainActor [weak self] in
                self?.playheadBar = bar
            }
        }
    }

    public func play() {
        transport.bpm = bpm
        transport.timeSignature = timeSignature
        transport.play()
        syncFromTransport()
    }

    public func pause() {
        transport.pause()
        syncFromTransport()
    }

    public func stop() {
        transport.stop()
        syncFromTransport()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func toggleRecordArm() {
        transport.toggleRecordArm()
        syncFromTransport()
    }

    public func toggleMetronome() {
        transport.toggleMetronome()
        syncFromTransport()
    }

    public func setPlayheadPosition(_ bar: Double) {
        transport.setPlayheadPosition(bar)
        syncFromTransport()
    }

    public func updateBPM(_ newBPM: Double) {
        bpm = min(max(newBPM, 20.0), 300.0)
        transport.bpm = bpm
    }

    private func syncFromTransport() {
        isPlaying = transport.state != .stopped
        isRecordArmed = transport.isRecordArmed
        isMetronomeEnabled = transport.isMetronomeEnabled
        playheadBar = transport.playheadBar
    }
}
