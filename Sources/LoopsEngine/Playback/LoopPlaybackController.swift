import Foundation
import AVFoundation
import LoopsCore

/// Controls loop behavior within containers during playback.
/// Handles hard cut, crossfade, and overdub boundary modes.
public final class LoopPlaybackController: @unchecked Sendable {
    public init() {}

    /// Calculates the effective frame count and start offset for a container's
    /// loop playback at the given position.
    public func loopParameters(
        container: Container,
        audioFileLength: Int64,
        positionInContainer: Int64
    ) -> (startFrame: Int64, frameCount: Int64)? {
        guard audioFileLength > 0 else { return nil }

        let containerLengthSamples = Int64(container.lengthBars) // Placeholder — needs sample conversion

        switch container.loopSettings.boundaryMode {
        case .hardCut:
            let posInLoop = positionInContainer % audioFileLength
            let remainingInLoop = audioFileLength - posInLoop
            return (posInLoop, remainingInLoop)

        case .crossfade:
            // Basic implementation — crossfade handled at a higher level
            let posInLoop = positionInContainer % audioFileLength
            let remainingInLoop = audioFileLength - posInLoop
            return (posInLoop, remainingInLoop)

        case .overdub:
            // Overdub plays all layers — start from beginning each pass
            let posInLoop = positionInContainer % audioFileLength
            return (posInLoop, audioFileLength - posInLoop)
        }
    }
}
