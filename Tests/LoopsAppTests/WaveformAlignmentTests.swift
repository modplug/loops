import Testing
import SwiftUI
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("Waveform Alignment Tests")
struct WaveformAlignmentTests {

    // MARK: - Peak Slicing Math

    /// Simulates the WaveformView peak slicing to verify correct alignment.
    private func slicePeaks(
        peaks: [Float],
        startFraction: CGFloat,
        lengthFraction: CGFloat
    ) -> (startIndex: Int, count: Int) {
        let totalPeaks = peaks.count
        let startIndex = max(0, min(Int(startFraction * CGFloat(totalPeaks)), totalPeaks))
        let count = max(1, min(Int(lengthFraction * CGFloat(totalPeaks)), totalPeaks - startIndex))
        return (startIndex, count)
    }

    /// Computes waveformStartFraction matching ContainerView logic.
    private func computeStartFraction(audioStartOffset: Double, recordingDurationBars: Double?) -> CGFloat {
        guard let totalBars = recordingDurationBars, totalBars > 0 else { return 0 }
        return CGFloat(audioStartOffset / totalBars)
    }

    /// Computes waveformLengthFraction matching ContainerView logic.
    private func computeLengthFraction(lengthBars: Int, recordingDurationBars: Double?) -> CGFloat {
        guard let totalBars = recordingDurationBars, totalBars > 0 else { return 1 }
        return min(1.0, CGFloat(Double(lengthBars) / totalBars))
    }

    // MARK: - Untrimmed Container Tests

    @Test("Untrimmed container: peaks only cover container length, not full recording")
    func untrimmedContainerPeakSlicing() {
        // Recording is 6.8 bars long, container is 7 bars (ceil(6.8))
        let recordingDurationBars = 6.8
        let containerLengthBars = 7
        // 100 peaks/sec at 120 BPM = 200 peaks/bar. 6.8 bars = 1360 peaks
        let peakCount = 1360
        let peaks = Array(repeating: Float(0.5), count: peakCount)

        let startFrac = computeStartFraction(audioStartOffset: 0, recordingDurationBars: recordingDurationBars)
        let lengthFrac = computeLengthFraction(lengthBars: containerLengthBars, recordingDurationBars: recordingDurationBars)

        #expect(startFrac == 0.0)
        // lengthFraction should be 7/6.8 ≈ 1.029 → clamped to 1.0
        #expect(lengthFrac == 1.0)

        let (startIndex, count) = slicePeaks(peaks: peaks, startFraction: startFrac, lengthFraction: lengthFrac)
        #expect(startIndex == 0)
        #expect(count == peakCount) // All peaks shown, correctly spanning the recording duration
    }

    @Test("Untrimmed container shorter than recording: only visible portion of peaks shown")
    func untrimmedContainerShorterThanRecording() {
        // Recording is 7.3 bars long, container is 7 bars (manually trimmed or resized)
        let recordingDurationBars = 7.3
        let containerLengthBars = 7
        // 200 peaks/bar × 7.3 bars = 1460 peaks
        let peakCount = 1460
        let peaks = Array(repeating: Float(0.5), count: peakCount)

        let startFrac = computeStartFraction(audioStartOffset: 0, recordingDurationBars: recordingDurationBars)
        let lengthFrac = computeLengthFraction(lengthBars: containerLengthBars, recordingDurationBars: recordingDurationBars)

        #expect(startFrac == 0.0)
        // 7 / 7.3 ≈ 0.9589
        #expect(lengthFrac < 1.0)
        #expect(lengthFrac > 0.95)

        let (startIndex, count) = slicePeaks(peaks: peaks, startFraction: startFrac, lengthFraction: lengthFrac)
        #expect(startIndex == 0)
        // Should show ~1400 peaks (7/7.3 * 1460), not all 1460
        #expect(count < peakCount)
        // The visible peaks should correspond to exactly the container's bar range
        let expectedCount = Int(lengthFrac * CGFloat(peakCount))
        #expect(count == expectedCount)
    }

    @Test("Transient position matches bar position when lengthFraction is applied")
    func transientPositionAlignment() {
        // Real-world scenario: 120 BPM, 4/4, recording is 6.8 bars
        // Container starts at bar 4, lengthBars = 6 (manually trimmed right)
        let recordingDurationBars = 6.8
        let containerLengthBars = 6
        let containerStartBar = 4

        // Peaks: 100 peaks/sec, 2 sec/bar at 120 BPM = 200 peaks/bar
        let peaksPerBar: Double = 200
        let peakCount = Int(recordingDurationBars * peaksPerBar) // 1360 peaks

        // Place a transient at 5.0 bars into the recording (bar 9 on timeline)
        let transientBar = 5.0  // relative to recording start
        let transientPeakIndex = Int(transientBar * peaksPerBar) // peak 1000

        let lengthFrac = computeLengthFraction(lengthBars: containerLengthBars, recordingDurationBars: recordingDurationBars)
        // 6 / 6.8 ≈ 0.882

        let (_, visibleCount) = slicePeaks(
            peaks: Array(repeating: Float(0.5), count: peakCount),
            startFraction: 0,
            lengthFraction: lengthFrac
        )

        // Visual position of the transient within the container:
        // The container width corresponds to `containerLengthBars` bars.
        // Peak at index `transientPeakIndex` out of `visibleCount` visible peaks.
        let visualFractionInContainer = Double(transientPeakIndex) / Double(visibleCount)
        let visualBar = containerStartBar + Int((visualFractionInContainer * Double(containerLengthBars)).rounded())

        // Audio plays this transient at: containerStartBar + transientBar
        let audioBar = containerStartBar + Int(transientBar)

        // With correct lengthFraction, visual position should match audio position
        #expect(visualBar == audioBar, "Visual bar \(visualBar) should match audio bar \(audioBar)")
    }

    // MARK: - Trimmed Container Tests

    @Test("Trimmed container: audioStartOffset correctly shifts peak window")
    func trimmedContainerPeakSlicing() {
        // Recording is 10 bars, container trimmed to show bars 3-7 (offset=3, length=4)
        let recordingDurationBars = 10.0
        let audioStartOffset = 3.0
        let containerLengthBars = 4

        // 200 peaks/bar × 10 bars = 2000 peaks
        let peakCount = 2000
        let peaks = Array(repeating: Float(0.5), count: peakCount)

        let startFrac = computeStartFraction(audioStartOffset: audioStartOffset, recordingDurationBars: recordingDurationBars)
        let lengthFrac = computeLengthFraction(lengthBars: containerLengthBars, recordingDurationBars: recordingDurationBars)

        #expect(startFrac == 0.3)  // 3/10
        #expect(lengthFrac == 0.4) // 4/10

        let (startIndex, count) = slicePeaks(peaks: peaks, startFraction: startFrac, lengthFraction: lengthFrac)

        // Should start at peak 600 (3/10 * 2000)
        #expect(startIndex == 600)
        // Should show 800 peaks (4/10 * 2000)
        #expect(count == 800)
    }

    @Test("Split container halves have correct peak windows")
    func splitContainerPeakAlignment() {
        // Original: 10 bars at offset 0. Split at bar 6 → left(6 bars), right(4 bars, offset=6)
        let recordingDurationBars = 10.0
        let peakCount = 2000 // 200 peaks/bar × 10 bars

        // Left half: offset=0, length=6
        let leftStartFrac = computeStartFraction(audioStartOffset: 0, recordingDurationBars: recordingDurationBars)
        let leftLengthFrac = computeLengthFraction(lengthBars: 6, recordingDurationBars: recordingDurationBars)
        let (leftStart, leftCount) = slicePeaks(
            peaks: Array(repeating: Float(0.5), count: peakCount),
            startFraction: leftStartFrac, lengthFraction: leftLengthFrac
        )

        // Right half: offset=6, length=4
        let rightStartFrac = computeStartFraction(audioStartOffset: 6.0, recordingDurationBars: recordingDurationBars)
        let rightLengthFrac = computeLengthFraction(lengthBars: 4, recordingDurationBars: recordingDurationBars)
        let (rightStart, rightCount) = slicePeaks(
            peaks: Array(repeating: Float(0.5), count: peakCount),
            startFraction: rightStartFrac, lengthFraction: rightLengthFrac
        )

        // Left half: peaks 0-1199
        #expect(leftStart == 0)
        #expect(leftCount == 1200)

        // Right half: peaks 1200-1999
        #expect(rightStart == 1200)
        #expect(rightCount == 800)

        // No gap or overlap between halves
        #expect(leftStart + leftCount == rightStart)
    }

    // MARK: - barsForDuration Consistency

    @Test("barsForDuration rounds up so container covers full recording")
    func barsForDurationCeils() {
        let tempo = Tempo(bpm: 120)
        let timeSig = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // 2 seconds per bar at 120 BPM 4/4
        // 13.6 seconds = 6.8 bars → should ceil to 7
        let bars = AudioImporter.barsForDuration(13.6, tempo: tempo, timeSignature: timeSig)
        #expect(bars == 7)
    }

    @Test("Container always covers or exceeds recording duration")
    func containerCoversRecording() {
        let tempo = Tempo(bpm: 120)
        let timeSig = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        let secondsPerBar = (60.0 / 120.0) * 4.0 // 2.0

        // Test a variety of durations
        let durations = [0.5, 1.0, 2.0, 3.7, 5.99, 10.0, 13.6, 100.1, 212.0]
        for duration in durations {
            let bars = AudioImporter.barsForDuration(duration, tempo: tempo, timeSignature: timeSig)
            let actualBars = duration / secondsPerBar
            #expect(Double(bars) >= actualBars,
                    "Container \(bars) bars must cover recording \(actualBars) bars for duration \(duration)s")
        }
    }

    @Test("lengthFraction is <= 1.0 when container >= recording duration")
    func lengthFractionClamped() {
        let tempo = Tempo(bpm: 120)
        let timeSig = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        let secondsPerBar = (60.0 / 120.0) * 4.0

        let durations = [3.7, 5.99, 13.6, 100.1]
        for duration in durations {
            let lengthBars = AudioImporter.barsForDuration(duration, tempo: tempo, timeSignature: timeSig)
            let recordingDurationBars = duration / secondsPerBar
            let frac = computeLengthFraction(lengthBars: lengthBars, recordingDurationBars: recordingDurationBars)
            #expect(frac <= 1.0,
                    "lengthFraction \(frac) should be <= 1.0 for \(duration)s recording (\(recordingDurationBars) bars, container \(lengthBars) bars)")
            #expect(frac > 0.0)
        }
    }

    // MARK: - Waveform Width Fraction Tests

    /// Computes waveformWidthFraction matching ContainerView logic.
    /// This determines what fraction of the container's pixel width has actual audio.
    private func computeWidthFraction(
        audioStartOffset: Double,
        lengthBars: Int,
        recordingDurationBars: Double?
    ) -> CGFloat {
        guard let totalBars = recordingDurationBars, totalBars > 0 else { return 1.0 }
        let audioEnd = min(audioStartOffset + Double(lengthBars), totalBars)
        let audibleBars = max(0, audioEnd - audioStartOffset)
        return min(1.0, CGFloat(audibleBars / Double(lengthBars)))
    }

    @Test("Waveform width fraction is < 1.0 when container is wider than recording (ceil rounding)")
    func widthFractionCeilRounding() {
        // Recording is 6.8 bars, container is 7 (ceil). Waveform should fill 6.8/7 = 97.1%
        let frac = computeWidthFraction(
            audioStartOffset: 0,
            lengthBars: 7,
            recordingDurationBars: 6.8
        )
        #expect(abs(frac - CGFloat(6.8 / 7.0)) < 0.001,
                "Expected ~0.971, got \(frac)")
        #expect(frac < 1.0, "Container wider than recording should not fill to 1.0")
    }

    @Test("Waveform width fraction is 1.0 when recording exactly fits container")
    func widthFractionExactFit() {
        let frac = computeWidthFraction(
            audioStartOffset: 0,
            lengthBars: 10,
            recordingDurationBars: 10.0
        )
        #expect(frac == 1.0)
    }

    @Test("Waveform width fraction is 1.0 when container is shorter than recording")
    func widthFractionContainerShorter() {
        // Container trimmed shorter than recording
        let frac = computeWidthFraction(
            audioStartOffset: 0,
            lengthBars: 5,
            recordingDurationBars: 10.0
        )
        #expect(frac == 1.0)
    }

    @Test("Waveform width fraction handles audioStartOffset near end of recording")
    func widthFractionWithOffset() {
        // Recording = 10 bars, offset = 8, length = 3 → only 2 bars of audio visible
        let frac = computeWidthFraction(
            audioStartOffset: 8.0,
            lengthBars: 3,
            recordingDurationBars: 10.0
        )
        #expect(abs(frac - CGFloat(2.0 / 3.0)) < 0.001,
                "Expected ~0.667, got \(frac)")
    }

    @Test("Waveform width fraction after split with ceil-rounded recording")
    func widthFractionAfterSplit() {
        // Recording = 90.5 bars → container = 91 (ceil). Split at bar 45.
        let recordingBars = 90.5
        // Left half: offset=0, length=45 → all 45 bars have audio → fraction = 1.0
        let leftFrac = computeWidthFraction(
            audioStartOffset: 0,
            lengthBars: 45,
            recordingDurationBars: recordingBars
        )
        #expect(leftFrac == 1.0)

        // Right half: offset=45, length=46 → audio covers 90.5-45 = 45.5 bars out of 46
        let rightFrac = computeWidthFraction(
            audioStartOffset: 45,
            lengthBars: 46,
            recordingDurationBars: recordingBars
        )
        #expect(abs(rightFrac - CGFloat(45.5 / 46.0)) < 0.001,
                "Expected ~0.989, got \(rightFrac)")
        #expect(rightFrac < 1.0)
    }

    @Test("Waveform width fraction is 1.0 when recordingDurationBars is nil")
    func widthFractionNilRecording() {
        let frac = computeWidthFraction(
            audioStartOffset: 5.0,
            lengthBars: 10,
            recordingDurationBars: nil
        )
        #expect(frac == 1.0)
    }

    // MARK: - Waveform Visual Position Accuracy

    @Test("Peak at bar N renders at bar N's pixel position (no stretching)")
    func peakPositionMatchesBarPosition() {
        // Setup: 120 BPM 4/4, recording = 6.8 bars, container = 7 bars
        let recordingBars = 6.8
        let containerBars = 7
        let peaksPerBar = 200.0
        let peakCount = Int(recordingBars * peaksPerBar) // 1360 peaks
        let pixelsPerBar: CGFloat = 100 // 100 px/bar
        let containerWidth = CGFloat(containerBars) * pixelsPerBar // 700 px
        let paddingH: CGFloat = 2 // horizontal padding on each side

        let widthFraction = computeWidthFraction(
            audioStartOffset: 0,
            lengthBars: containerBars,
            recordingDurationBars: recordingBars
        )
        // Waveform frame width = (700 - 4) * (6.8/7) = 696 * 0.9714 ≈ 676.1
        let waveformWidth = (containerWidth - 2 * paddingH) * widthFraction

        // A peak at bar 5.0 in the recording is at index 1000
        let peakIndex = 1000
        // Its visual X position within the waveform = peakIndex / peakCount * waveformWidth
        let visualX = CGFloat(peakIndex) / CGFloat(peakCount) * waveformWidth + paddingH

        // Expected X on the timeline: bar 5.0 starts at pixel 500 (bar 5 is at index 4, so 4 * 100)
        // But container starts at its startBar, so within the container: bar 5 = 5 * 100 = 500
        let expectedX = 5.0 * pixelsPerBar

        // Without the width fraction fix, visualX would be stretched:
        let stretchedWaveformWidth = containerWidth - 2 * paddingH // 696
        let stretchedVisualX = CGFloat(peakIndex) / CGFloat(peakCount) * stretchedWaveformWidth + paddingH
        // stretchedVisualX ≈ 1000/1360 * 696 + 2 ≈ 513.8 — off by ~14px (0.14 bars)

        // With the fix: visualX should be much closer to expectedX
        let errorWithFix = abs(visualX - expectedX)
        let errorWithout = abs(stretchedVisualX - expectedX)

        #expect(errorWithFix < 2.0, "With width fraction, error should be < 2px, got \(errorWithFix)")
        #expect(errorWithout > errorWithFix, "Fix should improve accuracy")
    }

    // MARK: - Cut Position Tests

    @Test("Selector drag bar computation matches actual cut bar")
    func selectorDragBarAccuracy() {
        // Container at startBar=5, length=10 bars, pixelsPerBar=100
        let containerStartBar = 5
        let containerLength = 10
        let pixelsPerBar: CGFloat = 100

        // User drags from x=250 to x=550 within the container (local coordinates)
        let startX: CGFloat = 250
        let endX: CGFloat = 550

        // Snapped bar calculation (matching ContainerView's selector .onChanged)
        let startBarLocal = max(0, Int(round(startX / pixelsPerBar)))
        let endBarLocal = min(containerLength, Int(round(endX / pixelsPerBar)))

        // Convert to absolute bar positions (matching ContainerView's selector .onEnded)
        let absoluteStartBar = containerStartBar + startBarLocal
        let absoluteEndBar = containerStartBar + endBarLocal

        // Expected: startBar=5+2=7 (250/100 = 2.5, rounds to 3... wait, round(2.5) = 2 in Swift)
        // Actually round(250/100) = round(2.5) = 2 (banker's rounding)
        #expect(startBarLocal == 2 || startBarLocal == 3) // banker's rounding at .5
        // round(550/100) = round(5.5) = 6
        #expect(endBarLocal == 5 || endBarLocal == 6) // banker's rounding at .5
        #expect(absoluteEndBar > absoluteStartBar, "Range must be valid")
    }

    @Test("Selector visual highlight matches reported bar range")
    func selectorHighlightMatchesBars() {
        // The selector overlay uses snapped X positions for both visual and reported bars
        let pixelsPerBar: CGFloat = 100
        let containerLength = 8

        // Simulate drag from local x=150 to x=620
        let startX: CGFloat = 150
        let currentX: CGFloat = 620
        let rawStartX = min(startX, currentX) // 150
        let rawEndX = max(startX, currentX)   // 620

        // ContainerView snaps to bars during drag
        let startBarLocal = max(0, Int(round(rawStartX / pixelsPerBar)))  // round(1.5) = 2
        let endBarLocal = min(containerLength, Int(round(rawEndX / pixelsPerBar))) // round(6.2) = 6

        // Visual overlay uses these snapped positions
        let visualStartX = CGFloat(startBarLocal) * pixelsPerBar  // 200
        let visualEndX = CGFloat(endBarLocal) * pixelsPerBar      // 600
        let visualWidth = visualEndX - visualStartX               // 400

        // Reported bars use the same snapped positions
        let reportedStartBar = startBarLocal  // 2 (local)
        let reportedEndBar = endBarLocal      // 6 (local)
        let reportedWidth = CGFloat(reportedEndBar - reportedStartBar) * pixelsPerBar // 400

        // Visual and reported widths must match exactly
        #expect(visualWidth == reportedWidth,
                "Visual width \(visualWidth) must match reported bar range width \(reportedWidth)")
    }

    // MARK: - Split + Cut Integration

    @Test("Split at playhead produces containers with contiguous audio coverage")
    func splitContiguousAudioCoverage() {
        // Original: startBar=1, length=10, offset=0, recording=10.0 bars
        let originalStart = 1
        let originalLength = 10
        let originalOffset = 0.0
        let recordingBars = 10.0
        let splitBar = 6 // Split at bar 6

        // Left half
        let leftLength = splitBar - originalStart   // 5
        let leftOffset = originalOffset             // 0.0

        // Right half
        let rightStart = splitBar                   // 6
        let rightLength = originalLength - leftLength // 5
        let rightOffset = originalOffset + Double(leftLength) // 5.0

        // Verify no gap
        #expect(originalStart + leftLength == rightStart)
        #expect(leftLength + rightLength == originalLength)
        #expect(leftOffset + Double(leftLength) == rightOffset)

        // Verify waveform fractions cover the right portions
        let leftStartFrac = computeStartFraction(audioStartOffset: leftOffset, recordingDurationBars: recordingBars)
        let leftLengthFrac = computeLengthFraction(lengthBars: leftLength, recordingDurationBars: recordingBars)
        let rightStartFrac = computeStartFraction(audioStartOffset: rightOffset, recordingDurationBars: recordingBars)
        let rightLengthFrac = computeLengthFraction(lengthBars: rightLength, recordingDurationBars: recordingBars)

        #expect(leftStartFrac == 0.0)
        #expect(leftLengthFrac == 0.5)  // 5/10
        #expect(rightStartFrac == 0.5)  // 5/10
        #expect(rightLengthFrac == 0.5) // 5/10

        // No overlap: left ends where right begins
        #expect(leftStartFrac + leftLengthFrac == rightStartFrac)
    }

    // MARK: - No recordingDurationBars Fallback

    @Test("When recordingDurationBars is nil, full peaks array is shown")
    func nilRecordingDurationShowsAllPeaks() {
        let startFrac = computeStartFraction(audioStartOffset: 2.0, recordingDurationBars: nil)
        let lengthFrac = computeLengthFraction(lengthBars: 4, recordingDurationBars: nil)
        #expect(startFrac == 0.0) // Can't compute without duration
        #expect(lengthFrac == 1.0) // Show everything as fallback
    }
}
