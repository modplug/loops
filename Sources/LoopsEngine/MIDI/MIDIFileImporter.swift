import Foundation
import LoopsCore

/// Parses standard MIDI files (.mid / .midi) into MIDISequence objects.
public struct MIDIFileImporter: Sendable {

    public init() {}

    /// Result of importing a MIDI file — one sequence per track.
    public struct ImportResult: Sendable {
        public let sequences: [MIDISequence]
        public let ticksPerQuarterNote: UInt16
        public let tempoMicrosPerQuarterNote: UInt32?
    }

    /// Imports a standard MIDI file and returns note sequences.
    public func importFile(at url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    /// Parses raw MIDI file data.
    public func parse(data: Data) throws -> ImportResult {
        var offset = 0

        // Read header chunk
        guard data.count >= 14 else {
            throw MIDIImportError.invalidFile
        }

        let headerTag = String(data: data[0..<4], encoding: .ascii)
        guard headerTag == "MThd" else {
            throw MIDIImportError.invalidFile
        }

        let headerLength = readUInt32(data, offset: 4)
        guard headerLength >= 6 else {
            throw MIDIImportError.invalidFile
        }

        let format = readUInt16(data, offset: 8)
        let numTracks = readUInt16(data, offset: 10)
        let division = readUInt16(data, offset: 12)

        // Only support ticks-per-quarter-note timing (bit 15 = 0)
        guard division & 0x8000 == 0 else {
            throw MIDIImportError.unsupportedTimingFormat
        }
        let ticksPerQuarterNote = division

        offset = 8 + Int(headerLength)

        var sequences: [MIDISequence] = []
        var tempoMicros: UInt32?

        for _ in 0..<numTracks {
            guard offset + 8 <= data.count else { break }

            let trackTag = String(data: data[offset..<offset + 4], encoding: .ascii)
            guard trackTag == "MTrk" else {
                throw MIDIImportError.invalidTrackChunk
            }

            let trackLength = Int(readUInt32(data, offset: offset + 4))
            offset += 8

            let trackEnd = min(offset + trackLength, data.count)
            let trackData = data[offset..<trackEnd]

            let (notes, tempo) = parseTrack(trackData, ticksPerQuarterNote: ticksPerQuarterNote)
            if let tempo { tempoMicros = tempo }

            if !notes.isEmpty {
                sequences.append(MIDISequence(notes: notes))
            }

            offset = trackEnd
        }

        // For format 0, all events are in a single track
        // For format 1, track 0 is usually tempo/meta, tracks 1+ have notes
        _ = format

        return ImportResult(
            sequences: sequences,
            ticksPerQuarterNote: ticksPerQuarterNote,
            tempoMicrosPerQuarterNote: tempoMicros
        )
    }

    // MARK: - Track Parsing

    private func parseTrack(_ data: Data.SubSequence, ticksPerQuarterNote: UInt16) -> ([MIDINoteEvent], UInt32?) {
        var notes: [MIDINoteEvent] = []
        var pendingNoteOns: [(pitch: UInt8, velocity: UInt8, channel: UInt8, tickStart: UInt64)] = []
        var offset = data.startIndex
        var absoluteTick: UInt64 = 0
        var runningStatus: UInt8 = 0
        var tempo: UInt32?
        let tpq = Double(ticksPerQuarterNote)

        while offset < data.endIndex {
            // Read delta time (variable-length quantity)
            let (delta, newOffset) = readVariableLength(data, from: offset)
            absoluteTick += UInt64(delta)
            offset = newOffset

            guard offset < data.endIndex else { break }

            var statusByte = data[offset]

            // Handle running status
            if statusByte < 0x80 {
                statusByte = runningStatus
            } else {
                offset = data.index(after: offset)
            }

            let channel = statusByte & 0x0F
            let messageType = statusByte & 0xF0

            switch messageType {
            case 0x90: // Note On
                guard offset + 1 < data.endIndex else { break }
                let note = data[offset]
                let velocity = data[data.index(after: offset)]
                offset = data.index(offset, offsetBy: 2)
                runningStatus = statusByte

                if velocity == 0 {
                    // Note On with velocity 0 = Note Off
                    finishNote(pitch: note, channel: channel, endTick: absoluteTick, tpq: tpq, pendingNoteOns: &pendingNoteOns, notes: &notes)
                } else {
                    pendingNoteOns.append((pitch: note, velocity: velocity, channel: channel, tickStart: absoluteTick))
                }

            case 0x80: // Note Off
                guard offset + 1 < data.endIndex else { break }
                let note = data[offset]
                _ = data[data.index(after: offset)] // release velocity
                offset = data.index(offset, offsetBy: 2)
                runningStatus = statusByte

                finishNote(pitch: note, channel: channel, endTick: absoluteTick, tpq: tpq, pendingNoteOns: &pendingNoteOns, notes: &notes)

            case 0xA0: // Polyphonic Key Pressure
                guard offset + 1 < data.endIndex else { break }
                offset = data.index(offset, offsetBy: 2)
                runningStatus = statusByte

            case 0xB0: // Control Change
                guard offset + 1 < data.endIndex else { break }
                offset = data.index(offset, offsetBy: 2)
                runningStatus = statusByte

            case 0xC0: // Program Change
                guard offset < data.endIndex else { break }
                offset = data.index(after: offset)
                runningStatus = statusByte

            case 0xD0: // Channel Pressure
                guard offset < data.endIndex else { break }
                offset = data.index(after: offset)
                runningStatus = statusByte

            case 0xE0: // Pitch Bend
                guard offset + 1 < data.endIndex else { break }
                offset = data.index(offset, offsetBy: 2)
                runningStatus = statusByte

            case 0xF0: // System messages
                if statusByte == 0xFF { // Meta event
                    guard offset + 1 < data.endIndex else { break }
                    let metaType = data[offset]
                    offset = data.index(after: offset)
                    let (length, newOff) = readVariableLength(data, from: offset)
                    offset = newOff

                    if metaType == 0x51 && length == 3 { // Tempo
                        guard offset + 2 < data.endIndex else { break }
                        let t = UInt32(data[offset]) << 16 | UInt32(data[data.index(after: offset)]) << 8 | UInt32(data[data.index(offset, offsetBy: 2)])
                        tempo = t
                    }

                    if metaType == 0x2F { // End of Track
                        break
                    }

                    offset = data.index(offset, offsetBy: min(Int(length), data.endIndex - offset))
                } else if statusByte == 0xF0 || statusByte == 0xF7 { // SysEx
                    let (length, newOff) = readVariableLength(data, from: offset)
                    offset = data.index(newOff, offsetBy: min(Int(length), data.endIndex - newOff))
                }
                runningStatus = 0

            default:
                break
            }
        }

        return (notes, tempo)
    }

    private func finishNote(
        pitch: UInt8,
        channel: UInt8,
        endTick: UInt64,
        tpq: Double,
        pendingNoteOns: inout [(pitch: UInt8, velocity: UInt8, channel: UInt8, tickStart: UInt64)],
        notes: inout [MIDINoteEvent]
    ) {
        if let idx = pendingNoteOns.lastIndex(where: { $0.pitch == pitch && $0.channel == channel }) {
            let pending = pendingNoteOns.remove(at: idx)
            let startBeat = Double(pending.tickStart) / tpq
            let endBeat = Double(endTick) / tpq
            let duration = max(0.01, endBeat - startBeat)
            notes.append(MIDINoteEvent(
                pitch: pending.pitch,
                velocity: pending.velocity,
                startBeat: startBeat,
                duration: duration,
                channel: pending.channel
            ))
        }
    }

    // MARK: - Binary Helpers

    private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 |
        UInt32(data[offset + 1]) << 16 |
        UInt32(data[offset + 2]) << 8 |
        UInt32(data[offset + 3])
    }

    private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private func readVariableLength(_ data: Data.SubSequence, from start: Data.Index) -> (UInt32, Data.Index) {
        var value: UInt32 = 0
        var offset = start
        while offset < data.endIndex {
            let byte = data[offset]
            value = (value << 7) | UInt32(byte & 0x7F)
            offset = data.index(after: offset)
            if byte & 0x80 == 0 { break }
        }
        return (value, offset)
    }
}

/// Errors that can occur during MIDI file import.
public enum MIDIImportError: Error, Sendable {
    case invalidFile
    case invalidTrackChunk
    case unsupportedTimingFormat
}
