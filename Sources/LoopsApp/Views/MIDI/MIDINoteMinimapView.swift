import SwiftUI
import LoopsCore

/// Renders a compact preview of MIDI notes inside a container on the timeline.
/// Shows small rectangles for each note, with pitch mapped to vertical position.
struct MIDINoteMinimapView: View {
    let notes: [MIDINoteEvent]
    let containerLengthBars: Int
    let beatsPerBar: Int
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard !notes.isEmpty else { return }

            let pitches = notes.map(\.pitch)
            let minPitch = pitches.min() ?? 0
            let maxPitch = pitches.max() ?? 127
            let pitchRange = max(1, CGFloat(maxPitch - minPitch))
            let totalBeats = CGFloat(containerLengthBars * beatsPerBar)

            for note in notes {
                let x = CGFloat(note.startBeat) / totalBeats * size.width
                let w = max(1, CGFloat(note.duration) / totalBeats * size.width)
                let normalizedPitch = CGFloat(note.pitch - minPitch) / pitchRange
                let y = (1 - normalizedPitch) * (size.height - 2)
                let h: CGFloat = max(1, size.height / pitchRange)

                context.fill(
                    Path(CGRect(x: x, y: y, width: w, height: min(h, 3))),
                    with: .color(color.opacity(0.7))
                )
            }
        }
    }
}
