import Foundation

public enum LoopsError: Error, Sendable {
    case engineStartFailed(underlying: String)
    case deviceNotFound(uid: String)
    case unsupportedSampleRate(Double)
    case tapInstallationFailed(String)
    case recordingWriteFailed(String)
    case audioFileCreationFailed(path: String)
    case projectLoadFailed(path: String, reason: String)
    case projectSaveFailed(path: String, reason: String)
    case schemaVersionMismatch(expected: Int, found: Int)
    case audioUnitLoadFailed(component: String)
    case audioUnitPresetRestoreFailed(String)
    case midiClientCreationFailed(status: Int32)
    case midiPortCreationFailed(status: Int32)
    case containerOverlap(trackID: String, bar: Int)
    case songNotFound(ID<Song>)
    case trackNotFound(ID<Track>)
}
