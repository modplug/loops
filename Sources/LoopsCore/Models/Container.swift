import Foundation

/// Phantom type for link group identification.
public enum LinkGroup {}

public struct Container: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Container>
    public var name: String
    /// 1-based
    public var startBar: Int
    public var lengthBars: Int
    public var sourceRecordingID: ID<SourceRecording>?
    /// All containers with same linkGroupID share a recording.
    public var linkGroupID: ID<LinkGroup>?
    public var loopSettings: LoopSettings
    public var isRecordArmed: Bool
    public var volumeOverride: Float?
    public var panOverride: Float?

    public var endBar: Int { startBar + lengthBars }

    public init(
        id: ID<Container> = ID(),
        name: String = "Container",
        startBar: Int = 1,
        lengthBars: Int = 4,
        sourceRecordingID: ID<SourceRecording>? = nil,
        linkGroupID: ID<LinkGroup>? = nil,
        loopSettings: LoopSettings = LoopSettings(),
        isRecordArmed: Bool = false,
        volumeOverride: Float? = nil,
        panOverride: Float? = nil
    ) {
        self.id = id
        self.name = name
        self.startBar = startBar
        self.lengthBars = lengthBars
        self.sourceRecordingID = sourceRecordingID
        self.linkGroupID = linkGroupID
        self.loopSettings = loopSettings
        self.isRecordArmed = isRecordArmed
        self.volumeOverride = volumeOverride
        self.panOverride = panOverride
    }
}
