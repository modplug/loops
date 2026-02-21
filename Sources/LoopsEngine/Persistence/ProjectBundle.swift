import Foundation
import LoopsCore

/// Manages the on-disk structure of a .loops project bundle.
///
/// Bundle structure:
/// ```
/// MyProject.loops/
///   project.json     — All metadata (Project struct serialized)
///   audio/           — All audio files (UUID-named .caf files)
/// ```
public struct ProjectBundle: Sendable {
    public let bundleURL: URL

    public var projectJSONURL: URL {
        bundleURL.appendingPathComponent("project.json")
    }

    public var audioDirectoryURL: URL {
        bundleURL.appendingPathComponent("audio")
    }

    public init(bundleURL: URL) {
        self.bundleURL = bundleURL
    }

    /// Creates the bundle directory structure if it doesn't exist.
    public func createIfNeeded() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: bundleURL.path) {
            do {
                try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            } catch {
                throw LoopsError.projectSaveFailed(
                    path: bundleURL.path,
                    reason: "Failed to create bundle directory: \(error.localizedDescription)"
                )
            }
        }
        let audioDir = audioDirectoryURL
        if !fileManager.fileExists(atPath: audioDir.path) {
            do {
                try fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
            } catch {
                throw LoopsError.projectSaveFailed(
                    path: audioDir.path,
                    reason: "Failed to create audio directory: \(error.localizedDescription)"
                )
            }
        }
    }
}
