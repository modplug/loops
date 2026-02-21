import Foundation

public struct SourceRecording: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<SourceRecording>
    /// Relative to project bundle's audio/ directory
    public var filename: String
    public var sampleRate: Double
    public var sampleCount: Int64
    public var waveformPeaks: [Float]?

    public var durationSeconds: Double { Double(sampleCount) / sampleRate }

    public init(
        id: ID<SourceRecording> = ID(),
        filename: String,
        sampleRate: Double,
        sampleCount: Int64,
        waveformPeaks: [Float]? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sampleRate = sampleRate
        self.sampleCount = sampleCount
        self.waveformPeaks = waveformPeaks
    }
}
