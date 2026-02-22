     import Foundation
import AVFoundation
import AudioToolbox
import LoopsCore

/// Manages loading and hosting Audio Unit plugins within the AVAudioEngine graph.
public final class AudioUnitHost: @unchecked Sendable {
    private let engine: AVAudioEngine

    public init(engine: AVAudioEngine) {
        self.engine = engine
    }

    /// Loads an Audio Unit with the given component description.
    /// Returns the instantiated AVAudioUnit on success.
    public func loadAudioUnit(component: AudioComponentInfo) async throws -> AVAudioUnit {
        let description = AudioComponentDescription(
            componentType: component.componentType,
            componentSubType: component.componentSubType,
            componentManufacturer: component.componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: []) { audioUnit, error in
                if let audioUnit = audioUnit {
                    continuation.resume(returning: audioUnit)
                } else {
                    let desc = "\(component.componentType)-\(component.componentSubType)"
                    continuation.resume(throwing: LoopsError.audioUnitLoadFailed(component: desc))
                }
            }
        }
    }

    /// Saves the full state of an Audio Unit for persistence.
    public func saveState(audioUnit: AVAudioUnit) -> Data? {
        guard let state = audioUnit.auAudioUnit.fullState else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: false)
    }

    /// Restores the full state of an Audio Unit from persisted data.
    public func restoreState(audioUnit: AVAudioUnit, data: Data) throws {
        guard let state = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSArray.self], from: data) as? [String: Any] else {
            throw LoopsError.audioUnitPresetRestoreFailed("Failed to decode preset data")
        }
        audioUnit.auAudioUnit.fullState = state
    }
}
