import CoreGraphics
import LoopsCore

struct PlaybackGridMIDIResolvedLayout {
    let lowPitch: UInt8
    let highPitch: UInt8
    let rowHeight: CGFloat
    let rows: Int
}

enum PlaybackGridMIDIViewResolver {
    static func resolveLayout(
        notes: [MIDINoteEvent],
        trackID: ID<Track>,
        laneHeight: CGFloat,
        snapshot: PlaybackGridSnapshot
    ) -> PlaybackGridMIDIResolvedLayout {
        let hasExplicitConfig = snapshot.inlineMIDIConfigs[trackID] != nil
        let (baseLow, baseHigh) = basePitchRange(notes: notes, trackID: trackID, snapshot: snapshot)
        var low = Int(baseLow)
        var high = Int(baseHigh)
        var rows = max(high - low + 1, 1)

        let configuredRowHeight = snapshot.inlineMIDIConfigs[trackID]?.rowHeight
        let rowHeight: CGFloat
        if hasExplicitConfig {
            if let configuredRowHeight, configuredRowHeight > 0 {
                rowHeight = max(2, configuredRowHeight)
                let maxVisibleRows = max(1, Int(floor(laneHeight / rowHeight)))
                if rows > maxVisibleRows {
                    // Inline MIDI lane has no vertical scroll yet.
                    // Mirror the header keyboard behavior by keeping the top pitch
                    // anchored and reducing the visible window to what the lane can
                    // display at the configured row height.
                    high = Int(baseHigh)
                    low = max(Int(baseLow), high - maxVisibleRows + 1)
                    rows = max(high - low + 1, 1)
                }
            } else {
                rowHeight = max(2, laneHeight / CGFloat(max(rows, 1)))
            }
        } else {
            // Auto mode keeps the visible density readable by capping the
            // effective row count to what a target row height can display.
            let targetRowHeight: CGFloat = 13
            let maxVisibleRows = max(6, Int(floor(laneHeight / targetRowHeight)))
            if rows > maxVisibleRows {
                if let minNote = notes.map(\.pitch).min(),
                   let maxNote = notes.map(\.pitch).max() {
                    let noteLow = Int(minNote)
                    let noteHigh = Int(maxNote)
                    let noteSpan = max(1, noteHigh - noteLow + 1)

                    if noteSpan >= maxVisibleRows {
                        // Note span exceeds viewport: anchor the lowest note and keep
                        // a stable window size.
                        low = noteLow
                        high = low + maxVisibleRows - 1
                    } else {
                        // Center note content inside the visible window while ensuring
                        // all existing notes remain visible.
                        let slack = maxVisibleRows - noteSpan
                        low = noteLow - (slack / 2)
                        low = max(0, min(127 - maxVisibleRows + 1, low))
                        high = low + maxVisibleRows - 1
                        if high < noteHigh {
                            high = noteHigh
                            low = max(0, high - maxVisibleRows + 1)
                        }
                    }
                } else {
                    let center = (low + high) / 2
                    low = center - (maxVisibleRows / 2)
                    low = max(0, min(127 - maxVisibleRows + 1, low))
                    high = min(127, low + maxVisibleRows - 1)
                }
                rows = max(high - low + 1, 1)
            }
            rowHeight = max(4, laneHeight / CGFloat(rows))
        }

        return PlaybackGridMIDIResolvedLayout(
            lowPitch: UInt8(clamping: low),
            highPitch: UInt8(clamping: high),
            rowHeight: rowHeight,
            rows: rows
        )
    }

    static func basePitchRange(
        notes: [MIDINoteEvent],
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> (UInt8, UInt8) {
        if let config = snapshot.inlineMIDIConfigs[trackID] {
            return (config.lowPitch, config.highPitch)
        }
        guard !notes.isEmpty else { return (36, 84) }
        var minPitch: UInt8 = 127
        var maxPitch: UInt8 = 0
        for note in notes {
            if note.pitch < minPitch { minPitch = note.pitch }
            if note.pitch > maxPitch { maxPitch = note.pitch }
        }
        let low = UInt8(clamping: max(0, Int(minPitch) - 6))
        let high = UInt8(clamping: min(127, Int(max(maxPitch, minPitch + 12)) + 6))
        return (low, high)
    }

    static func resolveTrackLayout(
        track: Track,
        laneHeight: CGFloat,
        snapshot: PlaybackGridSnapshot
    ) -> PlaybackGridMIDIResolvedLayout {
        resolveLayout(
            notes: trackMIDINotes(track),
            trackID: track.id,
            laneHeight: laneHeight,
            snapshot: snapshot
        )
    }

    static func resolveTrackLayout(
        trackLayout: PlaybackGridTrackLayout,
        laneHeight: CGFloat,
        snapshot: PlaybackGridSnapshot
    ) -> PlaybackGridMIDIResolvedLayout {
        var notes: [MIDINoteEvent] = []
        for container in trackLayout.containers {
            guard let resolved = container.resolvedMIDINotes, !resolved.isEmpty else { continue }
            notes.append(contentsOf: resolved)
        }
        return resolveLayout(
            notes: notes,
            trackID: trackLayout.track.id,
            laneHeight: laneHeight,
            snapshot: snapshot
        )
    }

    static func trackMIDINotes(_ track: Track) -> [MIDINoteEvent] {
        var notes: [MIDINoteEvent] = []
        for container in track.containers {
            guard let sequence = container.midiSequence, !sequence.notes.isEmpty else { continue }
            notes.append(contentsOf: sequence.notes)
        }
        return notes
    }

    static func noteRect(
        note: MIDINoteEvent,
        containerLengthBars: Double,
        laneRect: CGRect,
        timeSignature: TimeSignature,
        resolved: PlaybackGridMIDIResolvedLayout,
        minimumWidth: CGFloat = 6
    ) -> CGRect? {
        let lowPitch = resolved.lowPitch
        let highPitch = resolved.highPitch
        let pitchOffset = Int(note.pitch) - Int(lowPitch)
        guard pitchOffset >= 0, pitchOffset < resolved.rows else { return nil }

        let beatsPerBar = CGFloat(timeSignature.beatsPerBar)
        let totalBeats = max(CGFloat(containerLengthBars) * beatsPerBar, 0.0001)
        let rowHeight = max(resolved.rowHeight, 2)
        let noteHeight = max(4, rowHeight - 2)

        let xFraction = CGFloat(note.startBeat) / totalBeats
        let widthFraction = CGFloat(note.duration) / totalBeats
        let noteX = laneRect.minX + xFraction * laneRect.width + 0.5
        let noteW = max(minimumWidth, widthFraction * laneRect.width - 1)
        let rowFromTop = CGFloat(Int(highPitch) - Int(note.pitch))
        let noteY = laneRect.minY + (rowFromTop * rowHeight) + 1

        let unclipped = CGRect(x: noteX, y: noteY, width: noteW, height: noteHeight)
        let clipRect = laneRect.insetBy(dx: 0.5, dy: 1)
        let clipped = unclipped.intersection(clipRect)
        guard !clipped.isNull, !clipped.isEmpty, clipped.width >= 2, clipped.height >= 2 else { return nil }
        return clipped
    }
}
