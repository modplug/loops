import Testing
import SwiftUI
@testable import LoopsApp
@testable import LoopsCore

@Suite("View Memoization Tests")
struct ViewMemoizationTests {

    // MARK: - ContainerView Equatable

    @Test("ContainerView: identical data inputs are equal regardless of closures")
    func containerViewEqualWithSameData() {
        let container = Container(name: "Test", startBar: 1, lengthBars: 4)
        let lhs = ContainerView(
            container: container,
            pixelsPerBar: 60,
            height: 76,
            selectionState: nil,
            trackColor: .blue,
            waveformPeaks: [0.1, 0.5, 0.3],
            isClone: false,
            overriddenFields: [],
            onSelect: { _ in /* different closure instance */ },
            onDelete: { /* different closure instance */ }
        )
        let rhs = ContainerView(
            container: container,
            pixelsPerBar: 60,
            height: 76,
            selectionState: nil,
            trackColor: .blue,
            waveformPeaks: [0.1, 0.5, 0.3],
            isClone: false,
            overriddenFields: []
        )
        #expect(lhs == rhs)
    }

    @Test("ContainerView: different container data makes views unequal")
    func containerViewUnequalContainer() {
        let c1 = Container(name: "A", startBar: 1, lengthBars: 4)
        let c2 = Container(name: "B", startBar: 1, lengthBars: 4)
        let lhs = ContainerView(container: c1, pixelsPerBar: 60)
        let rhs = ContainerView(container: c2, pixelsPerBar: 60)
        #expect(lhs != rhs)
    }

    @Test("ContainerView: different waveformPeaks makes views unequal")
    func containerViewUnequalPeaks() {
        let container = Container()
        let lhs = ContainerView(container: container, pixelsPerBar: 60, waveformPeaks: [0.1, 0.5])
        let rhs = ContainerView(container: container, pixelsPerBar: 60, waveformPeaks: [0.2, 0.6])
        #expect(lhs != rhs)
    }

    @Test("ContainerView: nil vs non-nil waveformPeaks makes views unequal")
    func containerViewUnequalPeaksNilVsValue() {
        let container = Container()
        let lhs = ContainerView(container: container, pixelsPerBar: 60, waveformPeaks: nil)
        let rhs = ContainerView(container: container, pixelsPerBar: 60, waveformPeaks: [0.1])
        #expect(lhs != rhs)
    }

    @Test("ContainerView: different pixelsPerBar makes views unequal")
    func containerViewUnequalZoom() {
        let container = Container()
        let lhs = ContainerView(container: container, pixelsPerBar: 60)
        let rhs = ContainerView(container: container, pixelsPerBar: 120)
        #expect(lhs != rhs)
    }

    @Test("ContainerView: different otherSongs makes views unequal")
    func containerViewUnequalOtherSongs() {
        let container = Container()
        let songID = ID<Song>()
        let lhs = ContainerView(container: container, pixelsPerBar: 60, otherSongs: [(id: songID, name: "Song A")])
        let rhs = ContainerView(container: container, pixelsPerBar: 60, otherSongs: [(id: songID, name: "Song B")])
        #expect(lhs != rhs)
    }

    @Test("ContainerView: different overriddenFields makes views unequal")
    func containerViewUnequalOverriddenFields() {
        let container = Container()
        let lhs = ContainerView(container: container, pixelsPerBar: 60, overriddenFields: [])
        let rhs = ContainerView(container: container, pixelsPerBar: 60, overriddenFields: [.name])
        #expect(lhs != rhs)
    }

    @Test("ContainerView: different recordingDurationBars makes views unequal")
    func containerViewUnequalRecordingDuration() {
        let container = Container()
        let lhs = ContainerView(container: container, pixelsPerBar: 60, recordingDurationBars: nil)
        let rhs = ContainerView(container: container, pixelsPerBar: 60, recordingDurationBars: 8.0)
        #expect(lhs != rhs)
    }

    @Test("ContainerView: different audioStartOffset makes views unequal via container")
    func containerViewUnequalAudioOffset() {
        let c1 = Container(name: "A", startBar: 1, lengthBars: 4, audioStartOffset: 0.0)
        let c2 = Container(name: "A", startBar: 1, lengthBars: 4, audioStartOffset: 2.0)
        let lhs = ContainerView(container: c1, pixelsPerBar: 60)
        let rhs = ContainerView(container: c2, pixelsPerBar: 60)
        #expect(lhs != rhs)
    }

    // MARK: - TrackLaneView Equatable

    @Test("TrackLaneView: identical data inputs are equal regardless of closures")
    func trackLaneViewEqualWithSameData() {
        let track = Track(name: "Track 1", kind: .audio)
        let lhs = TrackLaneView(
            track: track,
            pixelsPerBar: 60,
            totalBars: 32,
            height: 80,
            onContainerSelect: { _, _ in },
            hasClipboard: false,
            isAutomationExpanded: false
        )
        let rhs = TrackLaneView(
            track: track,
            pixelsPerBar: 60,
            totalBars: 32,
            height: 80,
            onContainerDelete: { _ in },
            hasClipboard: false,
            isAutomationExpanded: false
        )
        #expect(lhs == rhs)
    }

    @Test("TrackLaneView: different track data makes views unequal")
    func trackLaneViewUnequalTrack() {
        let t1 = Track(name: "Track 1", kind: .audio)
        let t2 = Track(name: "Track 2", kind: .midi)
        let lhs = TrackLaneView(track: t1, pixelsPerBar: 60, totalBars: 32)
        let rhs = TrackLaneView(track: t2, pixelsPerBar: 60, totalBars: 32)
        #expect(lhs != rhs)
    }

    @Test("TrackLaneView: different automationSubLanePaths makes views unequal")
    func trackLaneViewUnequalAutomation() {
        let track = Track(name: "Track 1", kind: .audio)
        let path = EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 0)
        let lhs = TrackLaneView(track: track, pixelsPerBar: 60, totalBars: 32, automationSubLanePaths: [])
        let rhs = TrackLaneView(track: track, pixelsPerBar: 60, totalBars: 32, automationSubLanePaths: [path])
        #expect(lhs != rhs)
    }

    @Test("TrackLaneView: different hasClipboard makes views unequal")
    func trackLaneViewUnequalClipboard() {
        let track = Track(name: "Track 1", kind: .audio)
        let lhs = TrackLaneView(track: track, pixelsPerBar: 60, totalBars: 32, hasClipboard: false)
        let rhs = TrackLaneView(track: track, pixelsPerBar: 60, totalBars: 32, hasClipboard: true)
        #expect(lhs != rhs)
    }

    @Test("TrackLaneView: same track with different container makes views unequal")
    func trackLaneViewUnequalContainerChange() {
        let container1 = Container(name: "A", startBar: 1, lengthBars: 4)
        let container2 = Container(name: "B", startBar: 5, lengthBars: 4)
        let t1 = Track(name: "Track 1", kind: .audio, containers: [container1])
        let t2 = Track(name: "Track 1", kind: .audio, containers: [container1, container2])
        let lhs = TrackLaneView(track: t1, pixelsPerBar: 60, totalBars: 32)
        let rhs = TrackLaneView(track: t2, pixelsPerBar: 60, totalBars: 32)
        #expect(lhs != rhs)
    }

    // MARK: - GridOverlayView Equatable

    @Test("GridOverlayView: identical inputs are equal")
    func gridOverlayViewEqual() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        let lhs = GridOverlayView(totalBars: 64, pixelsPerBar: 120, timeSignature: ts, height: 300, gridMode: .adaptive)
        let rhs = GridOverlayView(totalBars: 64, pixelsPerBar: 120, timeSignature: ts, height: 300, gridMode: .adaptive)
        #expect(lhs == rhs)
    }

    @Test("GridOverlayView: different pixelsPerBar makes views unequal")
    func gridOverlayViewUnequalZoom() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        let lhs = GridOverlayView(totalBars: 64, pixelsPerBar: 120, timeSignature: ts, height: 300)
        let rhs = GridOverlayView(totalBars: 64, pixelsPerBar: 240, timeSignature: ts, height: 300)
        #expect(lhs != rhs)
    }

    @Test("GridOverlayView: different totalBars makes views unequal")
    func gridOverlayViewUnequalBars() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        let lhs = GridOverlayView(totalBars: 64, pixelsPerBar: 120, timeSignature: ts, height: 300)
        let rhs = GridOverlayView(totalBars: 128, pixelsPerBar: 120, timeSignature: ts, height: 300)
        #expect(lhs != rhs)
    }

    @Test("GridOverlayView: different gridMode makes views unequal")
    func gridOverlayViewUnequalGridMode() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        let lhs = GridOverlayView(totalBars: 64, pixelsPerBar: 120, timeSignature: ts, height: 300, gridMode: .adaptive)
        let rhs = GridOverlayView(totalBars: 64, pixelsPerBar: 120, timeSignature: ts, height: 300, gridMode: .fixed(.quarter))
        #expect(lhs != rhs)
    }

    // MARK: - AutomationSubLaneView Equatable

    @Test("AutomationSubLaneView: identical inputs are equal regardless of closures")
    func automationSubLaneViewEqual() {
        let trackID = ID<Track>()
        let path = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        let container = Container(name: "C", startBar: 1, lengthBars: 4)
        let lhs = AutomationSubLaneView(
            targetPath: path, containers: [container], laneColorIndex: 0,
            pixelsPerBar: 120, totalBars: 64, height: 40, selectedBreakpointID: nil,
            onAddBreakpoint: { _, _, _ in }
        )
        let rhs = AutomationSubLaneView(
            targetPath: path, containers: [container], laneColorIndex: 0,
            pixelsPerBar: 120, totalBars: 64, height: 40, selectedBreakpointID: nil,
            onDeleteBreakpoint: { _, _, _ in }
        )
        #expect(lhs == rhs)
    }

    @Test("AutomationSubLaneView: different containers makes views unequal")
    func automationSubLaneViewUnequalContainers() {
        let trackID = ID<Track>()
        let path = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        let c1 = Container(name: "A", startBar: 1, lengthBars: 4)
        let c2 = Container(name: "B", startBar: 5, lengthBars: 4)
        let lhs = AutomationSubLaneView(
            targetPath: path, containers: [c1], laneColorIndex: 0,
            pixelsPerBar: 120, totalBars: 64, height: 40, selectedBreakpointID: nil
        )
        let rhs = AutomationSubLaneView(
            targetPath: path, containers: [c1, c2], laneColorIndex: 0,
            pixelsPerBar: 120, totalBars: 64, height: 40, selectedBreakpointID: nil
        )
        #expect(lhs != rhs)
    }

    @Test("AutomationSubLaneView: different selectedBreakpointID makes views unequal")
    func automationSubLaneViewUnequalSelection() {
        let trackID = ID<Track>()
        let path = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        let bpID = ID<AutomationBreakpoint>()
        let lhs = AutomationSubLaneView(
            targetPath: path, containers: [], laneColorIndex: 0,
            pixelsPerBar: 120, totalBars: 64, height: 40, selectedBreakpointID: nil
        )
        let rhs = AutomationSubLaneView(
            targetPath: path, containers: [], laneColorIndex: 0,
            pixelsPerBar: 120, totalBars: 64, height: 40, selectedBreakpointID: bpID
        )
        #expect(lhs != rhs)
    }
}
