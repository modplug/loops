/// LoopsEngine — audio engine, MIDI, AU hosting, recording, and persistence.
/// Depends on LoopsCore. Imports AVFoundation, CoreMIDI, AudioToolbox, CoreAudio.
import Foundation
import AVFoundation
import CoreMIDI
import AudioToolbox
import CoreAudio
import LoopsCore

/// Namespace for the LoopsEngine module.
public enum LoopsEngine {
    public static let version = LoopsCore.version
}
