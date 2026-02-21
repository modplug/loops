import Foundation
import LoopsCore

/// Handles reading and writing Project data to .loops bundle directories.
public final class ProjectPersistence: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    /// Saves a project to the given bundle URL.
    ///
    /// Creates the bundle directory structure if needed, then writes
    /// project.json with the serialized Project data.
    public func save(_ project: Project, to bundleURL: URL) throws {
        let bundle = ProjectBundle(bundleURL: bundleURL)
        try bundle.createIfNeeded()

        let data: Data
        do {
            data = try encoder.encode(project)
        } catch {
            throw LoopsError.projectSaveFailed(
                path: bundleURL.path,
                reason: "JSON encoding failed: \(error.localizedDescription)"
            )
        }

        // Atomic write: write to temp file then rename
        let tempURL = bundle.projectJSONURL
            .deletingLastPathComponent()
            .appendingPathComponent(".project.json.tmp")

        do {
            try data.write(to: tempURL, options: .atomic)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: bundle.projectJSONURL.path) {
                try fileManager.removeItem(at: bundle.projectJSONURL)
            }
            try fileManager.moveItem(at: tempURL, to: bundle.projectJSONURL)
        } catch let moveError where moveError is LoopsError {
            throw moveError
        } catch {
            throw LoopsError.projectSaveFailed(
                path: bundleURL.path,
                reason: "File write failed: \(error.localizedDescription)"
            )
        }
    }

    /// Loads a project from the given bundle URL.
    public func load(from bundleURL: URL) throws -> Project {
        let bundle = ProjectBundle(bundleURL: bundleURL)
        let jsonURL = bundle.projectJSONURL

        let data: Data
        do {
            data = try Data(contentsOf: jsonURL)
        } catch {
            throw LoopsError.projectLoadFailed(
                path: bundleURL.path,
                reason: "Failed to read project.json: \(error.localizedDescription)"
            )
        }

        let project: Project
        do {
            project = try decoder.decode(Project.self, from: data)
        } catch {
            throw LoopsError.projectLoadFailed(
                path: bundleURL.path,
                reason: "JSON decoding failed: \(error.localizedDescription)"
            )
        }

        if project.schemaVersion != 1 {
            throw LoopsError.schemaVersionMismatch(expected: 1, found: project.schemaVersion)
        }

        return project
    }
}
