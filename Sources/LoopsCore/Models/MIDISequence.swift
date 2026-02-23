import Foundation

/// Grid resolution for MIDI note quantization.
public enum SnapResolution: String, Codable, Equatable, Sendable, CaseIterable {
    case whole = "1"
    case half = "1/2"
    case quarter = "1/4"
    case eighth = "1/8"
    case sixteenth = "1/16"
    case thirtySecond = "1/32"

    /// Number of subdivisions per beat (quarter note).
    public var subdivisionsPerBeat: Double {
        switch self {
        case .whole: return 0.25
        case .half: return 0.5
        case .quarter: return 1.0
        case .eighth: return 2.0
        case .sixteenth: return 4.0
        case .thirtySecond: return 8.0
        }
    }

    /// Duration of one snap unit in beats.
    public var beatsPerUnit: Double {
        1.0 / subdivisionsPerBeat
    }

    /// Snaps a beat position to this resolution.
    public func snap(_ beat: Double) -> Double {
        let unit = beatsPerUnit
        return (beat / unit).rounded() * unit
    }
}

/// A single MIDI note event within a sequence.
public struct MIDINoteEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDINoteEvent>
    /// MIDI note number 0–127.
    public var pitch: UInt8
    /// MIDI velocity 1–127 (0 = note off).
    public var velocity: UInt8
    /// Start position in beats relative to the container start (0-based).
    public var startBeat: Double
    /// Duration in beats.
    public var duration: Double
    /// MIDI channel 0–15.
    public var channel: UInt8

    public init(
        id: ID<MIDINoteEvent> = ID(),
        pitch: UInt8,
        velocity: UInt8 = 100,
        startBeat: Double,
        duration: Double = 1.0,
        channel: UInt8 = 0
    ) {
        self.id = id
        self.pitch = pitch
        self.velocity = velocity
        self.startBeat = startBeat
        self.duration = duration
        self.channel = channel
    }

    /// End position in beats.
    public var endBeat: Double { startBeat + duration }
}

/// A collection of MIDI note events stored on a container.
public struct MIDISequence: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDISequence>
    /// Ordered note events.
    public var notes: [MIDINoteEvent]

    public init(
        id: ID<MIDISequence> = ID(),
        notes: [MIDINoteEvent] = []
    ) {
        self.id = id
        self.notes = notes
    }

    /// Returns notes sorted by start beat.
    public var sortedNotes: [MIDINoteEvent] {
        notes.sorted { $0.startBeat < $1.startBeat }
    }

    /// Returns notes that overlap the given beat range.
    public func notes(inRange startBeat: Double, endBeat: Double) -> [MIDINoteEvent] {
        notes.filter { note in
            note.endBeat > startBeat && note.startBeat < endBeat
        }
    }

    /// The highest pitch in the sequence (for display range).
    public var highestPitch: UInt8? {
        notes.map(\.pitch).max()
    }

    /// The lowest pitch in the sequence (for display range).
    public var lowestPitch: UInt8? {
        notes.map(\.pitch).min()
    }

    /// Total duration in beats (from 0 to the end of the last note).
    public var durationBeats: Double {
        notes.map(\.endBeat).max() ?? 0
    }
}
