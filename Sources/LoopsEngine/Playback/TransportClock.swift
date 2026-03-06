import Foundation
import QuartzCore
import LoopsCore

final class TransportClock {
    private let lock = NSLock()
    private var anchorTime: CFTimeInterval?
    private var anchorBar: Double = 1.0
    private var bpm: Double = 120.0
    private var timeSignature = TimeSignature()
    private var waitingForSync = false
    private var running = false

    func start(anchorBar: Double, bpm: Double, timeSignature: TimeSignature, waitForSync: Bool) {
        lock.lock()
        self.anchorBar = max(anchorBar, 1.0)
        self.bpm = bpm
        self.timeSignature = timeSignature
        waitingForSync = waitForSync
        running = true
        anchorTime = waitForSync ? nil : CACurrentMediaTime()
        lock.unlock()
    }

    func beginWaitForSync(currentBar: Double, bpm: Double, timeSignature: TimeSignature) {
        lock.lock()
        anchorBar = max(currentBar, 1.0)
        self.bpm = bpm
        self.timeSignature = timeSignature
        waitingForSync = true
        running = true
        anchorTime = nil
        lock.unlock()
    }

    func completeSync(
        currentBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        receipt: PlaybackStartReceipt?,
        audioOutputLatency: Double
    ) {
        lock.lock()
        anchorBar = max(currentBar, 1.0)
        self.bpm = bpm
        self.timeSignature = timeSignature
        waitingForSync = false
        running = true
        let delay = max(0, audioOutputLatency) + max(0, receipt?.startupCompensationSeconds ?? 0)
        anchorTime = CACurrentMediaTime() + delay
        lock.unlock()
    }

    func setBar(_ bar: Double, whileRunning: Bool, bpm: Double, timeSignature: TimeSignature) {
        lock.lock()
        anchorBar = max(bar, 1.0)
        self.bpm = bpm
        self.timeSignature = timeSignature
        running = whileRunning
        if whileRunning && !waitingForSync {
            anchorTime = CACurrentMediaTime()
        } else if !whileRunning {
            anchorTime = nil
        }
        lock.unlock()
    }

    func stop(at bar: Double) {
        lock.lock()
        anchorBar = max(bar, 1.0)
        waitingForSync = false
        running = false
        anchorTime = nil
        lock.unlock()
    }

    func currentBar(now: CFTimeInterval = CACurrentMediaTime()) -> Double {
        lock.lock()
        let currentAnchorBar = anchorBar
        let currentAnchorTime = anchorTime
        let currentBPM = bpm
        let currentTimeSignature = timeSignature
        let isWaiting = waitingForSync
        let isRunning = running
        lock.unlock()

        guard isRunning, !isWaiting, let currentAnchorTime else {
            return currentAnchorBar
        }

        let elapsed = max(0, now - currentAnchorTime)
        let secondsPerBeat = 60.0 / currentBPM
        let secondsPerBar = Double(currentTimeSignature.beatsPerBar) * secondsPerBeat
        guard secondsPerBar > 0 else { return currentAnchorBar }
        return currentAnchorBar + elapsed / secondsPerBar
    }

    func isWaitingForSync() -> Bool {
        lock.lock()
        let value = waitingForSync
        lock.unlock()
        return value
    }
}
