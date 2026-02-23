import SwiftUI
import LoopsCore

/// Dedicated observable for MIDI parameter learn state, extracted from ProjectViewModel.
/// Isolates MIDI learn mode changes so toggling learn mode doesn't invalidate
/// unrelated parts of the view tree (timeline, mixer).
@Observable
@MainActor
public final class MIDILearnState {

    /// Whether MIDI parameter learn mode is active.
    public var isMIDIParameterLearning: Bool = false

    /// The target path being learned (set during MIDI learn mode).
    public var midiLearnTargetPath: EffectPath?

    /// Starts MIDI parameter learn mode for the given target path.
    public func startLearn(targetPath: EffectPath) {
        isMIDIParameterLearning = true
        midiLearnTargetPath = targetPath
    }

    /// Cancels MIDI parameter learn mode.
    public func cancelLearn() {
        isMIDIParameterLearning = false
        midiLearnTargetPath = nil
    }

    /// Clears learn state (called after completing a learn operation).
    public func clearLearn() {
        isMIDIParameterLearning = false
        midiLearnTargetPath = nil
    }

    public init() {}
}
