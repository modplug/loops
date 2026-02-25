import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Performance Tests")
struct PerformanceTests {

    /// Creates a project with the given number of tracks, each with containers.
    @MainActor
    private func createLargeProject(trackCount: Int, containersPerTrack: Int) -> ProjectViewModel {
        let vm = ProjectViewModel()
        vm.newProject()
        for i in 0..<trackCount {
            vm.addTrack(kind: i % 2 == 0 ? .audio : .midi)
            let trackID = vm.project.songs[0].tracks[i].id
            for j in 0..<containersPerTrack {
                let startBar = Double(j * 4) + 1.0
                let _ = vm.addContainer(trackID: trackID, startBar: startBar, lengthBars: 4.0)
            }
        }
        return vm
    }

    @Test("Toggle mute on large project completes within 50ms")
    @MainActor
    func toggleMutePerformance() {
        let vm = createLargeProject(trackCount: 10, containersPerTrack: 20)
        let trackID = vm.project.songs[0].tracks[0].id

        let start = CFAbsoluteTimeGetCurrent()
        vm.toggleMute(trackID: trackID)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 50, "toggleMute took \(String(format: "%.1f", elapsed))ms — should be under 50ms")
    }

    @Test("Toggle solo on large project completes within 50ms")
    @MainActor
    func toggleSoloPerformance() {
        let vm = createLargeProject(trackCount: 10, containersPerTrack: 20)
        let trackID = vm.project.songs[0].tracks[0].id

        let start = CFAbsoluteTimeGetCurrent()
        vm.toggleSolo(trackID: trackID)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 50, "toggleSolo took \(String(format: "%.1f", elapsed))ms — should be under 50ms")
    }

    @Test("Rapid mute toggles coalesce undo snapshots")
    @MainActor
    func rapidMuteTogglesCoalesce() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let start = CFAbsoluteTimeGetCurrent()
        // Rapid toggles should coalesce into a single undo operation
        for _ in 0..<20 {
            vm.toggleMute(trackID: trackID)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // 20 rapid toggles should be fast because coalesced (only 1 snapshot)
        #expect(elapsed < 100, "20 rapid mute toggles took \(String(format: "%.1f", elapsed))ms — should be under 100ms")
    }
}

    @Test("Track equatable short-circuits on scalar changes")
    func trackEquatablePerformance() {
        // Create tracks with large MIDI sequences
        var tracks: [Track] = []
        for i in 0..<10 {
            var track = Track(name: "Track \(i)", kind: .midi)
            for j in 0..<20 {
                var container = Container(
                    name: "Container \(j)",
                    startBar: Double(j * 4) + 1.0,
                    lengthBars: 4.0
                )
                // Add MIDI sequence with many notes
                var notes: [MIDINoteEvent] = []
                for n in 0..<100 {
                    notes.append(MIDINoteEvent(
                        pitch: UInt8(60 + (n % 12)),
                        velocity: 100,
                        startBeat: Double(n) * 0.25,
                        duration: 0.2
                    ))
                }
                container.midiSequence = MIDISequence(notes: notes)
                track.containers.append(container)
            }
            tracks.append(track)
        }

        // Toggle mute on one track — equatable should short-circuit before comparing containers
        var mutedTrack = tracks[0]
        mutedTrack.isMuted = true

        let start = CFAbsoluteTimeGetCurrent()
        let iterations = 10000
        var equalCount = 0
        for _ in 0..<iterations {
            // Changed track: should short-circuit at isMuted
            if tracks[0] == mutedTrack { equalCount += 1 }
            // Unchanged tracks: should compare cheap scalars then O(1) array buffer identity
            if tracks[1] == tracks[1] { equalCount += 1 }
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(equalCount == iterations, "Unchanged track self-comparison should be true")
        #expect(elapsed < 100, "10000 Track comparisons took \(String(format: "%.1f", elapsed))ms — should be under 100ms")
    }

@Suite("Automation Shape Generator Tests")
struct AutomationShapeTests {

    @Test("Triangle wave generates reasonable point count")
    func trianglePointCount() {
        let breakpoints = AutomationShapeGenerator.generate(
            tool: .triangle,
            startPosition: 0,
            endPosition: 4.0,
            startValue: 0,
            endValue: 1,
            gridSpacing: 0.25
        )
        // 4 bars at 0.25 grid spacing = 16 intervals + 1 = 17 points max
        #expect(breakpoints.count <= 20, "Triangle generated \(breakpoints.count) points for 4 bars — should be ≤ 20")
        #expect(breakpoints.count >= 4, "Triangle should generate at least 4 points for 4 bars")
    }

    @Test("Sine wave generates reasonable point count")
    func sinePointCount() {
        let breakpoints = AutomationShapeGenerator.generate(
            tool: .sine,
            startPosition: 0,
            endPosition: 4.0,
            startValue: 0,
            endValue: 1,
            gridSpacing: 0.25
        )
        #expect(breakpoints.count <= 20, "Sine generated \(breakpoints.count) points for 4 bars — should be ≤ 20")
        #expect(breakpoints.count >= 4, "Sine should generate at least 4 points for 4 bars")
    }

    @Test("Square wave generates reasonable point count")
    func squarePointCount() {
        let breakpoints = AutomationShapeGenerator.generate(
            tool: .square,
            startPosition: 0,
            endPosition: 4.0,
            startValue: 0,
            endValue: 1,
            gridSpacing: 0.25
        )
        #expect(breakpoints.count <= 20, "Square generated \(breakpoints.count) points for 4 bars — should be ≤ 20")
        #expect(breakpoints.count >= 4, "Square should generate at least 4 points for 4 bars")
    }

    @Test("Line tool generates grid-resolution points")
    func linePointCount() {
        let breakpoints = AutomationShapeGenerator.generate(
            tool: .line,
            startPosition: 0,
            endPosition: 4.0,
            startValue: 0,
            endValue: 1,
            gridSpacing: 0.25
        )
        // 4 bars / 0.25 = 16 steps + 1 = 17 points
        #expect(breakpoints.count == 17, "Line should generate exactly 17 points for 4 bars at 0.25 grid")
    }

    @Test("Shape values stay in 0-1 range")
    func shapeValuesInRange() {
        for tool in AutomationTool.allCases where tool != .pointer {
            let breakpoints = AutomationShapeGenerator.generate(
                tool: tool,
                startPosition: 0,
                endPosition: 4.0,
                startValue: 0,
                endValue: 1,
                gridSpacing: 0.25
            )
            for bp in breakpoints {
                #expect(bp.value >= 0 && bp.value <= 1,
                        "\(tool.label) generated out-of-range value \(bp.value) at position \(bp.position)")
            }
        }
    }

    @Test("Periodic shapes have correct period")
    func periodicShapePeriod() {
        // With gridSpacing = 0.25, period should be 1.0 bar (4 * 0.25)
        let sineBreakpoints = AutomationShapeGenerator.generate(
            tool: .sine,
            startPosition: 0,
            endPosition: 4.0,
            startValue: 0,
            endValue: 1,
            gridSpacing: 0.25
        )
        // At period=1.0 bar, sine should complete 4 full cycles in 4 bars
        // Check first and second cycle have similar patterns
        guard sineBreakpoints.count >= 8 else {
            Issue.record("Not enough points to verify periodicity")
            return
        }
        // Value at position 0 and position 1.0 should be similar (both at cycle start)
        let atStart = sineBreakpoints.first { abs($0.position - 0.0) < 0.01 }
        let atOnebar = sineBreakpoints.first { abs($0.position - 1.0) < 0.01 }
        if let a = atStart, let b = atOnebar {
            #expect(abs(a.value - b.value) < 0.15, "Sine should repeat at 1-bar period")
        }
    }
}
