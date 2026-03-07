import Foundation

/// Grid resolution for MIDI note quantization and timeline snapping.
public enum SnapResolution: String, Codable, Equatable, Sendable, CaseIterable {
    case whole = "1"
    case half = "1/2"
    case quarter = "1/4"
    case eighth = "1/8"
    case sixteenth = "1/16"
    case thirtySecond = "1/32"
    case quarterTriplet = "1/4T"
    case eighthTriplet = "1/8T"
    case sixteenthTriplet = "1/16T"
    case thirtySecondTriplet = "1/32T"

    /// Number of subdivisions per beat (quarter note).
    public var subdivisionsPerBeat: Double {
        switch self {
        case .whole: return 0.25
        case .half: return 0.5
        case .quarter: return 1.0
        case .eighth: return 2.0
        case .sixteenth: return 4.0
        case .thirtySecond: return 8.0
        case .quarterTriplet: return 2.0 / 3.0
        case .eighthTriplet: return 3.0
        case .sixteenthTriplet: return 6.0
        case .thirtySecondTriplet: return 12.0
        }
    }

    /// Duration of one snap unit in beats.
    public var beatsPerUnit: Double {
        1.0 / subdivisionsPerBeat
    }

    /// Whether this is a triplet resolution.
    public var isTriplet: Bool {
        switch self {
        case .quarterTriplet, .eighthTriplet, .sixteenthTriplet, .thirtySecondTriplet:
            return true
        default:
            return false
        }
    }

    /// The straight (non-triplet) resolutions, in order from coarsest to finest.
    public static var straightCases: [SnapResolution] {
        [.whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond]
    }

    /// The triplet resolutions, in order from coarsest to finest.
    public static var tripletCases: [SnapResolution] {
        [.quarterTriplet, .eighthTriplet, .sixteenthTriplet, .thirtySecondTriplet]
    }

    /// Snaps a beat position to this resolution.
    public func snap(_ beat: Double) -> Double {
        let unit = beatsPerUnit
        return (beat / unit).rounded() * unit
    }
}

/// Grid mode for timeline snapping: adaptive (zoom-dependent) or fixed resolution.
public enum GridMode: Equatable, Sendable {
    case adaptive
    case fixed(SnapResolution)
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

/// A MIDI controller event within a sequence.
public struct MIDIControllerEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDIControllerEvent>
    /// MIDI controller number 0-127.
    public var controller: UInt8
    /// MIDI value 0-127.
    public var value: UInt8
    /// Beat position relative to the container start (0-based).
    public var beat: Double
    /// MIDI channel 0-15.
    public var channel: UInt8

    public init(
        id: ID<MIDIControllerEvent> = ID(),
        controller: UInt8,
        value: UInt8,
        beat: Double,
        channel: UInt8 = 0
    ) {
        self.id = id
        self.controller = controller
        self.value = value
        self.beat = beat
        self.channel = channel
    }
}

/// A collection of MIDI note events stored on a container.
public struct MIDISequence: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDISequence>
    /// Ordered note events.
    public var notes: [MIDINoteEvent]
    /// Ordered MIDI controller events.
    public var controllerEvents: [MIDIControllerEvent]

    public init(
        id: ID<MIDISequence> = ID(),
        notes: [MIDINoteEvent] = [],
        controllerEvents: [MIDIControllerEvent] = []
    ) {
        self.id = id
        self.notes = notes
        self.controllerEvents = controllerEvents
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case notes
        case controllerEvents
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(ID.self, forKey: .id) ?? ID()
        notes = try container.decodeIfPresent([MIDINoteEvent].self, forKey: .notes) ?? []
        controllerEvents = try container.decodeIfPresent([MIDIControllerEvent].self, forKey: .controllerEvents) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(notes, forKey: .notes)
        if !controllerEvents.isEmpty {
            try container.encode(controllerEvents, forKey: .controllerEvents)
        }
    }

    /// Returns notes sorted by start beat.
    public var sortedNotes: [MIDINoteEvent] {
        notes.sorted { $0.startBeat < $1.startBeat }
    }

    /// Returns controller events sorted by beat.
    public var sortedControllerEvents: [MIDIControllerEvent] {
        controllerEvents.sorted { lhs, rhs in
            if lhs.beat == rhs.beat {
                if lhs.controller == rhs.controller {
                    return lhs.channel < rhs.channel
                }
                return lhs.controller < rhs.controller
            }
            return lhs.beat < rhs.beat
        }
    }

    /// Returns notes that overlap the given beat range.
    public func notes(inRange startBeat: Double, endBeat: Double) -> [MIDINoteEvent] {
        notes.filter { note in
            note.endBeat > startBeat && note.startBeat < endBeat
        }
    }

    /// Returns controller events that fall inside the given beat range.
    public func controllerEvents(
        inRange startBeat: Double,
        endBeat: Double,
        controller: UInt8? = nil
    ) -> [MIDIControllerEvent] {
        controllerEvents.filter { event in
            guard event.beat >= startBeat && event.beat < endBeat else { return false }
            if let controller {
                return event.controller == controller
            }
            return true
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
        max(
            notes.map(\.endBeat).max() ?? 0,
            controllerEvents.map(\.beat).max() ?? 0
        )
    }
}
