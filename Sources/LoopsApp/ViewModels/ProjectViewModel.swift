import SwiftUI
import LoopsCore
import LoopsEngine

/// Manages the current project state and file operations.
@Observable
@MainActor
public final class ProjectViewModel {
    public var project: Project
    public var projectURL: URL?
    public var hasUnsavedChanges: Bool = false

    private let persistence = ProjectPersistence()

    public init(project: Project = Project()) {
        self.project = project
    }

    /// Creates a new empty project with a default song.
    public func newProject() {
        let defaultSong = Song(name: "Song 1")
        project = Project(songs: [defaultSong])
        projectURL = nil
        hasUnsavedChanges = false
    }

    /// Saves the project to the current URL, or prompts for a location.
    /// Returns true if saved successfully, false if no URL is set.
    public func save() throws -> Bool {
        guard let url = projectURL else {
            return false
        }
        try persistence.save(project, to: url)
        hasUnsavedChanges = false
        return true
    }

    /// Saves the project to a specific URL.
    public func save(to url: URL) throws {
        try persistence.save(project, to: url)
        projectURL = url
        hasUnsavedChanges = false
    }

    /// Loads a project from a bundle URL.
    public func open(from url: URL) throws {
        project = try persistence.load(from: url)
        projectURL = url
        hasUnsavedChanges = false
    }
}
