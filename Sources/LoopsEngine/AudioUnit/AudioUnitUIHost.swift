import Foundation
import AVFoundation
import AudioToolbox
import CoreAudioKit
import LoopsCore

/// Manages loading and presenting Audio Unit plugin UIs.
@MainActor
public final class AudioUnitUIHost {
    /// Requests the view controller for an AUAudioUnit's custom UI.
    /// Returns nil if the AU doesn't provide a custom view.
    public static func requestViewController(for audioUnit: AUAudioUnit) async -> NSViewController? {
        await withCheckedContinuation { continuation in
            audioUnit.requestViewController { viewController in
                continuation.resume(returning: viewController)
            }
        }
    }
}
