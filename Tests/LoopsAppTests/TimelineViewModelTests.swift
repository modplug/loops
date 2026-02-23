import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("TimelineViewModel Tests")
struct TimelineViewModelTests {

    @Test("Default state")
    @MainActor
    func defaultState() {
        let vm = TimelineViewModel()
        #expect(vm.pixelsPerBar == 120.0)
        #expect(vm.playheadBar == 1.0)
        #expect(vm.totalBars == 64)
    }

    @Test("Total width calculation")
    @MainActor
    func totalWidth() {
        let vm = TimelineViewModel()
        vm.totalBars = 32
        vm.pixelsPerBar = 100
        #expect(vm.totalWidth == 3200.0)
    }

    @Test("Bar to x-position conversion")
    @MainActor
    func barToXPosition() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        // Bar 1 starts at x=0
        #expect(vm.xPosition(forBar: 1.0) == 0.0)
        // Bar 2 starts at x=100
        #expect(vm.xPosition(forBar: 2.0) == 100.0)
        // Bar 5 starts at x=400
        #expect(vm.xPosition(forBar: 5.0) == 400.0)
    }

    @Test("X-position to bar conversion")
    @MainActor
    func xPositionToBar() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        #expect(vm.bar(forXPosition: 0) == 1.0)
        #expect(vm.bar(forXPosition: 100) == 2.0)
        #expect(vm.bar(forXPosition: 250) == 3.5)
    }

    @Test("Playhead x position")
    @MainActor
    func playheadXPosition() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        vm.playheadBar = 3.0
        #expect(vm.playheadX == 200.0)
    }

    @Test("Zoom in increases pixels per bar")
    @MainActor
    func zoomIn() {
        let vm = TimelineViewModel()
        let before = vm.pixelsPerBar
        vm.zoomIn()
        #expect(vm.pixelsPerBar > before)
    }

    @Test("Zoom out decreases pixels per bar")
    @MainActor
    func zoomOut() {
        let vm = TimelineViewModel()
        let before = vm.pixelsPerBar
        vm.zoomOut()
        #expect(vm.pixelsPerBar < before)
    }

    @Test("Zoom in respects maximum")
    @MainActor
    func zoomInMax() {
        let vm = TimelineViewModel()
        for _ in 0..<50 {
            vm.zoomIn()
        }
        #expect(vm.pixelsPerBar <= TimelineViewModel.maxPixelsPerBar)
    }

    @Test("Zoom out respects minimum")
    @MainActor
    func zoomOutMin() {
        let vm = TimelineViewModel()
        for _ in 0..<50 {
            vm.zoomOut()
        }
        #expect(vm.pixelsPerBar >= TimelineViewModel.minPixelsPerBar)
    }

    @Test("Pixels per beat calculation")
    @MainActor
    func pixelsPerBeat() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 120
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        #expect(vm.pixelsPerBeat(timeSignature: ts) == 30.0)

        let ts3 = TimeSignature(beatsPerBar: 3, beatUnit: 4)
        #expect(vm.pixelsPerBeat(timeSignature: ts3) == 40.0)
    }

    // MARK: - Selected Range (#69)

    @Test("Selected range defaults to nil")
    @MainActor
    func selectedRangeDefault() {
        let vm = TimelineViewModel()
        #expect(vm.selectedRange == nil)
        #expect(vm.selectedTrackIDs.isEmpty)
    }

    @Test("Set and clear selected range")
    @MainActor
    func setAndClearSelectedRange() {
        let vm = TimelineViewModel()
        vm.selectedRange = 3...8
        #expect(vm.selectedRange == 3...8)
        vm.clearSelectedRange()
        #expect(vm.selectedRange == nil)
    }

    @Test("Toggle track selection adds and removes")
    @MainActor
    func toggleTrackSelection() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        let trackID2 = ID<Track>()

        #expect(vm.selectedTrackIDs.isEmpty)
        vm.toggleTrackSelection(trackID: trackID)
        #expect(vm.selectedTrackIDs.contains(trackID))
        #expect(vm.selectedTrackIDs.count == 1)

        vm.toggleTrackSelection(trackID: trackID2)
        #expect(vm.selectedTrackIDs.count == 2)

        vm.toggleTrackSelection(trackID: trackID)
        #expect(!vm.selectedTrackIDs.contains(trackID))
        #expect(vm.selectedTrackIDs.count == 1)
    }

    // MARK: - Click-to-Position (#73)

    @Test("Snapped bar at x=0 returns bar 1")
    @MainActor
    func snappedBarAtOrigin() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        // x=0 → bar 1
        #expect(vm.snappedBar(forXPosition: 0, timeSignature: ts) == 1.0)
    }

    @Test("Snapped bar at x=pixelsPerBar returns bar 2")
    @MainActor
    func snappedBarAtOneBar() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        // x=100 → bar 2.0 (raw 2.0, snapped to whole bar)
        #expect(vm.snappedBar(forXPosition: 100, timeSignature: ts) == 2.0)
    }

    @Test("Snap-to-bar at low zoom: rounds to nearest whole bar")
    @MainActor
    func snapToBarLowZoom() {
        let vm = TimelineViewModel()
        // Low zoom: pixelsPerBar=60, 4/4 time → 15 pixels per beat (< 40 threshold)
        vm.pixelsPerBar = 60
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // x=20 → rawBar = 20/60 + 1 = 1.333 → rounds to 1.0
        #expect(vm.snappedBar(forXPosition: 20, timeSignature: ts) == 1.0)
        // x=40 → rawBar = 40/60 + 1 = 1.667 → rounds to 2.0
        #expect(vm.snappedBar(forXPosition: 40, timeSignature: ts) == 2.0)
        // x=150 → rawBar = 150/60 + 1 = 3.5 → rounds to 4.0
        #expect(vm.snappedBar(forXPosition: 150, timeSignature: ts) == 4.0)
    }

    @Test("Snap-to-beat at high zoom: rounds to nearest beat")
    @MainActor
    func snapToBeatHighZoom() {
        let vm = TimelineViewModel()
        // High zoom: pixelsPerBar=200, 4/4 time → 50 pixels per beat (>= 40 threshold)
        vm.pixelsPerBar = 200
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // x=0 → bar 1.0 (beat 1 of bar 1)
        #expect(vm.snappedBar(forXPosition: 0, timeSignature: ts) == 1.0)
        // x=50 → rawBar = 50/200 + 1 = 1.25 → 1 beat = 0.25 bar → snapped bar 1.25
        #expect(vm.snappedBar(forXPosition: 50, timeSignature: ts) == 1.25)
        // x=100 → rawBar = 100/200 + 1 = 1.5 → 2 beats = 0.5 bar → snapped bar 1.5
        #expect(vm.snappedBar(forXPosition: 100, timeSignature: ts) == 1.5)
        // x=175 → rawBar = 175/200 + 1 = 1.875 → 3.5 beats → rounds to 4 beats = 1.0 bar → bar 2.0
        #expect(vm.snappedBar(forXPosition: 175, timeSignature: ts) == 2.0)
    }

    @Test("Snap-to-bar at various pixelsPerBar values")
    @MainActor
    func snapAtVariousZoom() {
        let vm = TimelineViewModel()
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // At minimum zoom (30 ppb, 7.5 per beat → bar snap)
        vm.pixelsPerBar = 30
        let bar30 = vm.snappedBar(forXPosition: 45, timeSignature: ts)
        // rawBar = 45/30 + 1 = 2.5 → rounds to 3
        #expect(bar30 == 3.0)

        // At maximum zoom (500 ppb, 125 per beat → beat snap)
        vm.pixelsPerBar = 500
        let bar500 = vm.snappedBar(forXPosition: 125, timeSignature: ts)
        // rawBar = 125/500 + 1 = 1.25 → snaps to 1 beat = 0.25 bar → 1.25
        #expect(bar500 == 1.25)
    }

    @Test("Snapped bar clamps negative x to bar 1")
    @MainActor
    func snappedBarNegativeX() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        #expect(vm.snappedBar(forXPosition: -50, timeSignature: ts) == 1.0)
    }

    @Test("Snap-to-beat with 3/4 time signature")
    @MainActor
    func snapToBeatThreeFour() {
        let vm = TimelineViewModel()
        // High zoom: pixelsPerBar=180, 3/4 → 60 pixels per beat (>= 40)
        vm.pixelsPerBar = 180
        let ts = TimeSignature(beatsPerBar: 3, beatUnit: 4)

        // x=60 → rawBar = 60/180 + 1 = 1.333 → totalBeats = 0.333*3 = 1 beat → snapped 1/3 bar → 1.333
        let result = vm.snappedBar(forXPosition: 60, timeSignature: ts)
        #expect(abs(result - (1.0 + 1.0/3.0)) < 0.001)
    }

    // MARK: - Master Track Pinning (#92)

    @Test("TimelineView with explicit tracks uses those tracks for height")
    @MainActor
    func timelineViewExplicitTracksHeight() {
        let vm = TimelineViewModel()
        let pvm = ProjectViewModel()
        let audio1 = Track(name: "Audio 1", kind: .audio)
        let audio2 = Track(name: "Audio 2", kind: .audio)
        let master = Track(name: "Master", kind: .master)
        let song = Song(tracks: [audio1, audio2, master])

        // All tracks: 3 × 80 = 240
        let allView = TimelineView(viewModel: vm, projectViewModel: pvm, song: song)
        #expect(allView.totalContentHeight == 240.0)

        // Only regular tracks: 2 × 80 = 160
        let regularView = TimelineView(viewModel: vm, projectViewModel: pvm, song: song, tracks: [audio1, audio2])
        #expect(regularView.totalContentHeight == 160.0)

        // Only master track: 1 × 80 = 80
        let masterView = TimelineView(viewModel: vm, projectViewModel: pvm, song: song, tracks: [master])
        #expect(masterView.totalContentHeight == 80.0)
    }

    @Test("Song regular tracks exclude master")
    @MainActor
    func songRegularTracksExcludeMaster() {
        let pvm = ProjectViewModel()
        pvm.newProject()
        pvm.addTrack(kind: .audio)
        pvm.addTrack(kind: .midi)
        let song = pvm.project.songs[0]
        // Song has 3 tracks: Audio, MIDI, Master
        #expect(song.tracks.count == 3)
        let regularTracks = song.tracks.filter { $0.kind != .master }
        let masterTrack = song.tracks.first { $0.kind == .master }
        #expect(regularTracks.count == 2)
        #expect(masterTrack != nil)
        #expect(regularTracks.allSatisfy { $0.kind != .master })
    }

    @Test("TimelineView defaults to all song tracks when tracks not specified")
    @MainActor
    func timelineViewDefaultsToAllTracks() {
        let vm = TimelineViewModel()
        let pvm = ProjectViewModel()
        let audio = Track(name: "Audio", kind: .audio)
        let master = Track(name: "Master", kind: .master)
        let song = Song(tracks: [audio, master])

        let view = TimelineView(viewModel: vm, projectViewModel: pvm, song: song)
        // Default: uses song.tracks (both tracks)
        #expect(view.totalContentHeight == 160.0)
    }

    @Test("Mixer view separates regular and master tracks")
    @MainActor
    func mixerViewSeparatesRegularAndMaster() {
        let pvm = ProjectViewModel()
        pvm.newProject()
        pvm.addTrack(kind: .audio)
        pvm.addTrack(kind: .audio)
        let tracks = pvm.project.songs[0].tracks
        // 3 tracks: Audio, Audio, Master
        #expect(tracks.count == 3)
        let regularTracks = tracks.filter { $0.kind != .master }
        let masterTrack = tracks.first { $0.kind == .master }
        #expect(regularTracks.count == 2)
        #expect(masterTrack?.kind == .master)
    }

    // MARK: - Ensure Bar Visible (#96)

    @Test("ensureBarVisible expands totalBars when bar exceeds current range")
    @MainActor
    func ensureBarVisibleExpands() {
        let vm = TimelineViewModel()
        vm.totalBars = 64
        vm.ensureBarVisible(100)
        #expect(vm.totalBars == 108) // 100 + 8 padding
    }

    @Test("ensureBarVisible does not shrink when bar is within range")
    @MainActor
    func ensureBarVisibleNoShrink() {
        let vm = TimelineViewModel()
        vm.totalBars = 64
        vm.ensureBarVisible(32)
        #expect(vm.totalBars == 64) // unchanged
    }

    @Test("ensureBarVisible at boundary does not expand")
    @MainActor
    func ensureBarVisibleAtBoundary() {
        let vm = TimelineViewModel()
        vm.totalBars = 64
        vm.ensureBarVisible(64)
        #expect(vm.totalBars == 64) // exactly at boundary, no expansion needed
    }

    // MARK: - Per-Track Heights (#112)

    @Test("Per-track height defaults to 80pt")
    @MainActor
    func perTrackHeightDefault() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        #expect(vm.baseTrackHeight(for: trackID) == 80)
        #expect(vm.trackHeights.isEmpty)
    }

    @Test("Set per-track height stores and retrieves custom height")
    @MainActor
    func setPerTrackHeight() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        vm.setTrackHeight(120, for: trackID)
        #expect(vm.baseTrackHeight(for: trackID) == 120)
    }

    @Test("Minimum track height enforced at 40pt")
    @MainActor
    func minimumTrackHeight() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        vm.setTrackHeight(20, for: trackID)
        #expect(vm.baseTrackHeight(for: trackID) == TimelineViewModel.minimumTrackHeight)
        #expect(vm.baseTrackHeight(for: trackID) == 40)
    }

    @Test("Reset track height removes custom height")
    @MainActor
    func resetTrackHeight() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        vm.setTrackHeight(150, for: trackID)
        #expect(vm.baseTrackHeight(for: trackID) == 150)
        vm.resetTrackHeight(for: trackID)
        #expect(vm.baseTrackHeight(for: trackID) == TimelineViewModel.defaultTrackHeight)
        #expect(vm.trackHeights[trackID] == nil)
    }

    @Test("Per-track heights are independent across tracks")
    @MainActor
    func perTrackHeightsIndependent() {
        let vm = TimelineViewModel()
        let trackA = ID<Track>()
        let trackB = ID<Track>()
        vm.setTrackHeight(60, for: trackA)
        vm.setTrackHeight(140, for: trackB)
        #expect(vm.baseTrackHeight(for: trackA) == 60)
        #expect(vm.baseTrackHeight(for: trackB) == 140)
    }

    @Test("Track height with automation uses custom base height")
    @MainActor
    func trackHeightWithAutomationUsesCustomBase() {
        let vm = TimelineViewModel()
        var track = Track(name: "Audio", kind: .audio)
        let lane = AutomationLane(targetPath: EffectPath(trackID: track.id, effectIndex: 0, parameterAddress: 0), breakpoints: [])
        track.trackAutomationLanes = [lane]
        vm.setTrackHeight(100, for: track.id)
        vm.automationExpanded.insert(track.id)
        // base 100 + 1 lane * 40 = 140
        #expect(vm.trackHeight(for: track, baseHeight: vm.baseTrackHeight(for: track.id)) == 140)
    }

    @Test("TimelineView totalContentHeight uses per-track heights")
    @MainActor
    func timelineViewUsesPerTrackHeights() {
        let vm = TimelineViewModel()
        let pvm = ProjectViewModel()
        let audio1 = Track(name: "Audio 1", kind: .audio)
        let audio2 = Track(name: "Audio 2", kind: .audio)
        let song = Song(tracks: [audio1, audio2])

        // Default: 2 * 80 = 160
        let view1 = TimelineView(viewModel: vm, projectViewModel: pvm, song: song)
        #expect(view1.totalContentHeight == 160.0)

        // Custom: 60 + 120 = 180
        vm.setTrackHeight(60, for: audio1.id)
        vm.setTrackHeight(120, for: audio2.id)
        let view2 = TimelineView(viewModel: vm, projectViewModel: pvm, song: song)
        #expect(view2.totalContentHeight == 180.0)
    }

    // MARK: - Track Header Width (#115)

    @Test("Track header width defaults to 160pt")
    @MainActor
    func trackHeaderWidthDefault() {
        let vm = TimelineViewModel()
        #expect(vm.trackHeaderWidth == 160)
        #expect(vm.trackHeaderWidth == TimelineViewModel.defaultHeaderWidth)
    }

    @Test("Set track header width stores value")
    @MainActor
    func setTrackHeaderWidth() {
        let vm = TimelineViewModel()
        vm.setTrackHeaderWidth(200)
        #expect(vm.trackHeaderWidth == 200)
    }

    @Test("Track header width clamps to minimum")
    @MainActor
    func trackHeaderWidthClampsMin() {
        let vm = TimelineViewModel()
        vm.setTrackHeaderWidth(50)
        #expect(vm.trackHeaderWidth == TimelineViewModel.minHeaderWidth)
        #expect(vm.trackHeaderWidth == 100)
    }

    @Test("Track header width clamps to maximum")
    @MainActor
    func trackHeaderWidthClampsMax() {
        let vm = TimelineViewModel()
        vm.setTrackHeaderWidth(500)
        #expect(vm.trackHeaderWidth == TimelineViewModel.maxHeaderWidth)
        #expect(vm.trackHeaderWidth == 400)
    }

    @Test("Track header width at exact boundaries")
    @MainActor
    func trackHeaderWidthBoundaries() {
        let vm = TimelineViewModel()
        vm.setTrackHeaderWidth(100)
        #expect(vm.trackHeaderWidth == 100)
        vm.setTrackHeaderWidth(400)
        #expect(vm.trackHeaderWidth == 400)
    }

    @Test("Track header width persists during session")
    @MainActor
    func trackHeaderWidthPersistsDuringSession() {
        let vm = TimelineViewModel()
        vm.setTrackHeaderWidth(250)
        #expect(vm.trackHeaderWidth == 250)
        // Simulate other operations
        vm.zoomIn()
        vm.zoomOut()
        #expect(vm.trackHeaderWidth == 250)
    }
}
