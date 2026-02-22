import SwiftUI
import LoopsCore

/// Note layout constants for a piano keyboard.
enum PianoLayout {
    /// Returns true if the given MIDI note is a black key.
    static func isBlackKey(note: UInt8) -> Bool {
        let pc = note % 12
        return pc == 1 || pc == 3 || pc == 6 || pc == 8 || pc == 10
    }

    /// Returns the white key index (0-based) within an octave for a white key note.
    /// Only valid for white keys (C=0, D=1, E=2, F=3, G=4, A=5, B=6).
    static func whiteKeyIndex(note: UInt8) -> Int {
        let pc = Int(note % 12)
        switch pc {
        case 0: return 0   // C
        case 2: return 1   // D
        case 4: return 2   // E
        case 5: return 3   // F
        case 7: return 4   // G
        case 9: return 5   // A
        case 11: return 6  // B
        default: return 0
        }
    }

    /// Maps a black key to its horizontal offset relative to the preceding white key.
    /// Returns the white key index that the black key sits between (to its left).
    static func blackKeyWhiteIndex(note: UInt8) -> Int {
        let pc = Int(note % 12)
        switch pc {
        case 1: return 0   // C#: between C and D
        case 3: return 1   // D#: between D and E
        case 6: return 3   // F#: between F and G
        case 8: return 4   // G#: between G and A
        case 10: return 5  // A#: between A and B
        default: return 0
        }
    }

    /// Note name for display (e.g. "C3", "F#4").
    static func noteName(_ note: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(note) / 12 - 1
        return "\(names[Int(note % 12)])\(octave)"
    }

    /// Calculates velocity (1–127) from vertical position on a key.
    /// Top of key = soft (1), bottom of key = loud (127).
    static func velocity(yFraction: CGFloat) -> UInt8 {
        let clamped = min(max(yFraction, 0), 1)
        return UInt8(1 + clamped * 126)
    }
}

/// A 2-octave virtual piano keyboard for triggering MIDI notes.
public struct VirtualKeyboardView: View {
    /// Current base octave (MIDI octave numbering: octave 3 = middle C region).
    @State private var baseOctave: Int = 3

    /// Set of currently pressed MIDI note numbers for visual feedback.
    @State private var pressedNotes: Set<UInt8> = []

    /// Callback when a note event should be sent.
    var onNoteEvent: ((MIDIActionMessage) -> Void)?

    /// MIDI channel for outgoing notes (default 0).
    var channel: UInt8 = 0

    private let octaveCount = 2
    private let whiteKeyWidth: CGFloat = 28
    private let whiteKeyHeight: CGFloat = 80
    private let blackKeyWidth: CGFloat = 18
    private let blackKeyHeight: CGFloat = 50

    /// The lowest MIDI note in the current view.
    private var lowestNote: UInt8 {
        UInt8(clamping: (baseOctave + 1) * 12) // MIDI octave: C(oct+1) = (oct+1)*12
    }

    /// The highest MIDI note in the current view (exclusive).
    private var highestNote: UInt8 {
        UInt8(clamping: (baseOctave + 1 + octaveCount) * 12)
    }

    /// All MIDI notes in the current range.
    private var noteRange: [UInt8] {
        Array(lowestNote..<highestNote)
    }

    /// White keys in the current range.
    private var whiteKeys: [UInt8] {
        noteRange.filter { !PianoLayout.isBlackKey(note: $0) }
    }

    /// Black keys in the current range.
    private var blackKeys: [UInt8] {
        noteRange.filter { PianoLayout.isBlackKey(note: $0) }
    }

    /// Total white key count determines keyboard width.
    private var totalWhiteKeys: Int {
        whiteKeys.count
    }

    public init(
        onNoteEvent: ((MIDIActionMessage) -> Void)? = nil,
        channel: UInt8 = 0
    ) {
        self.onNoteEvent = onNoteEvent
        self.channel = channel
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Octave down
            Button(action: {
                if baseOctave > 0 { baseOctave -= 1 }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(baseOctave <= 0)
            .help("Octave Down")

            // Octave label
            Text("\(PianoLayout.noteName(lowestNote))–\(PianoLayout.noteName(highestNote > 0 ? highestNote - 1 : 0))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60)

            // Piano keys
            ZStack(alignment: .topLeading) {
                // White keys
                HStack(spacing: 1) {
                    ForEach(whiteKeys, id: \.self) { note in
                        whiteKeyView(note: note)
                    }
                }

                // Black keys (positioned absolutely)
                ForEach(blackKeys, id: \.self) { note in
                    blackKeyView(note: note)
                }
            }
            .frame(
                width: CGFloat(totalWhiteKeys) * (whiteKeyWidth + 1) - 1,
                height: whiteKeyHeight
            )
            .clipped()

            // Octave up
            Button(action: {
                if baseOctave < 8 { baseOctave += 1 }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(baseOctave >= 8)
            .help("Octave Up")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Key Views

    private func whiteKeyView(note: UInt8) -> some View {
        let isPressed = pressedNotes.contains(note)
        return Rectangle()
            .fill(isPressed ? Color.accentColor.opacity(0.4) : Color.white)
            .frame(width: whiteKeyWidth, height: whiteKeyHeight)
            .border(Color.gray.opacity(0.5), width: 0.5)
            .overlay(alignment: .bottom) {
                Text(note % 12 == 0 ? PianoLayout.noteName(note) : "")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressedNotes.contains(note) {
                            let yFraction = value.location.y / whiteKeyHeight
                            let vel = PianoLayout.velocity(yFraction: yFraction)
                            pressedNotes.insert(note)
                            onNoteEvent?(.noteOn(channel: channel, note: note, velocity: vel))
                        }
                    }
                    .onEnded { _ in
                        pressedNotes.remove(note)
                        onNoteEvent?(.noteOff(channel: channel, note: note, velocity: 0))
                    }
            )
    }

    private func blackKeyView(note: UInt8) -> some View {
        let isPressed = pressedNotes.contains(note)
        let whiteIdx = PianoLayout.blackKeyWhiteIndex(note: note)
        // Calculate offset relative to the start of the keyboard.
        // The black key sits at the right edge of the white key at whiteIdx.
        let globalWhiteIdx = whiteIdx + Int(note / 12 - lowestNote / 12) * 7
        let xOffset = CGFloat(globalWhiteIdx + 1) * (whiteKeyWidth + 1) - blackKeyWidth / 2 - 1

        return Rectangle()
            .fill(isPressed ? Color.accentColor : Color.black)
            .frame(width: blackKeyWidth, height: blackKeyHeight)
            .cornerRadius(2)
            .offset(x: xOffset)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressedNotes.contains(note) {
                            let yFraction = value.location.y / blackKeyHeight
                            let vel = PianoLayout.velocity(yFraction: yFraction)
                            pressedNotes.insert(note)
                            onNoteEvent?(.noteOn(channel: channel, note: note, velocity: vel))
                        }
                    }
                    .onEnded { _ in
                        pressedNotes.remove(note)
                        onNoteEvent?(.noteOff(channel: channel, note: note, velocity: 0))
                    }
            )
    }
}
