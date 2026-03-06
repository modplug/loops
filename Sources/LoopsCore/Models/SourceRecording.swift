import Foundation

public struct WaveformExtrema: Codable, Equatable, Sendable {
    public var minimum: Float
    public var maximum: Float

    public init(minimum: Float, maximum: Float) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct SourceRecording: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<SourceRecording>
    /// Relative to project bundle's audio/ directory
    public var filename: String
    public var sampleRate: Double
    public var sampleCount: Int64
    public var waveformPeaks: [Float]?
    public var waveformExtrema: [WaveformExtrema]?
    public var waveformRMS: [Float]?

    public var durationSeconds: Double { Double(sampleCount) / sampleRate }

    public init(
        id: ID<SourceRecording> = ID(),
        filename: String,
        sampleRate: Double,
        sampleCount: Int64,
        waveformPeaks: [Float]? = nil,
        waveformExtrema: [WaveformExtrema]? = nil,
        waveformRMS: [Float]? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sampleRate = sampleRate
        self.sampleCount = sampleCount
        self.waveformPeaks = waveformPeaks
        self.waveformExtrema = waveformExtrema
        self.waveformRMS = waveformRMS
    }
}
