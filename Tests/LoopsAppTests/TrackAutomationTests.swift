import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("Track Volume & Pan Automation Tests")
struct TrackAutomationTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - EffectPath Track Parameter Sentinels

    @Test("EffectPath trackVolume creates correct sentinel values")
    func effectPathTrackVolume() {
        let trackID = ID<Track>()
        let path = EffectPath.trackVolume(trackID: trackID)
        #expect(path.trackID == trackID)
        #expect(path.containerID == nil)
        #expect(path.effectIndex == EffectPath.trackParameterEffectIndex)
        #expect(path.parameterAddress == EffectPath.volumeAddress)
        #expect(path.isTrackVolume)
        #expect(!path.isTrackPan)
        #expect(path.isTrackParameter)
    }

    @Test("EffectPath trackPan creates correct sentinel values")
    func effectPathTrackPan() {
        let trackID = ID<Track>()
        let path = EffectPath.trackPan(trackID: trackID)
        #expect(path.trackID == trackID)
        #expect(path.containerID == nil)
        #expect(path.effectIndex == EffectPath.trackParameterEffectIndex)
        #expect(path.parameterAddress == EffectPath.panAddress)
        #expect(!path.isTrackVolume)
        #expect(path.isTrackPan)
        #expect(path.isTrackParameter)
    }

    @Test("EffectPath with volume address Codable round-trip")
    func effectPathVolumeRoundTrip() throws {
        let path = EffectPath.trackVolume(trackID: ID<Track>())
        let decoded = try roundTrip(path)
        #expect(path == decoded)
        #expect(decoded.isTrackVolume)
    }

    @Test("EffectPath with pan address Codable round-trip")
    func effectPathPanRoundTrip() throws {
        let path = EffectPath.trackPan(trackID: ID<Track>())
        let decoded = try roundTrip(path)
        #expect(path == decoded)
        #expect(decoded.isTrackPan)
    }

    @Test("Regular EffectPath is not a track parameter")
    func regularEffectPathNotTrackParameter() {
        let path = EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 42)
        #expect(!path.isTrackVolume)
        #expect(!path.isTrackPan)
        #expect(!path.isTrackParameter)
    }

    // MARK: - Track Model with Automation Lanes

    @Test("Track with trackAutomationLanes Codable round-trip")
    func trackAutomationLanesRoundTrip() throws {
        let trackID = ID<Track>()
        let volumeLane = AutomationLane(
            targetPath: .trackVolume(trackID: trackID),
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.5),
                AutomationBreakpoint(position: 4.0, value: 1.0)
            ]
        )
        let panLane = AutomationLane(
            targetPath: .trackPan(trackID: trackID),
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.5),
                AutomationBreakpoint(position: 8.0, value: 0.0)
            ]
        )
        let track = Track(
            id: trackID,
            name: "Test",
            kind: .audio,
            trackAutomationLanes: [volumeLane, panLane],
            orderIndex: 0
        )
        let decoded = try roundTrip(track)
        #expect(decoded.trackAutomationLanes.count == 2)
        #expect(decoded.trackAutomationLanes[0].targetPath.isTrackVolume)
        #expect(decoded.trackAutomationLanes[1].targetPath.isTrackPan)
        #expect(decoded.trackAutomationLanes[0].breakpoints.count == 2)
        #expect(decoded.trackAutomationLanes[1].breakpoints.count == 2)
    }

    @Test("Track without trackAutomationLanes decodes with empty array (backward compat)")
    func trackBackwardCompatDecode() throws {
        // Encode a track as JSON manually without trackAutomationLanes key
        let track = Track(name: "Old Track", kind: .audio, orderIndex: 0)
        let data = try encoder.encode(track)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "trackAutomationLanes")
        let modifiedData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Track.self, from: modifiedData)
        #expect(decoded.trackAutomationLanes.isEmpty)
    }

    // MARK: - Track Volume Automation Interpolation

    @Test("Track volume automation interpolation at specific bar positions")
    func trackVolumeAutomationInterpolation() {
        let trackID = ID<Track>()
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: trackID),
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.0),
                AutomationBreakpoint(position: 4.0, value: 1.0)
            ]
        )

        // At bar 0 (start) → 0.0
        let v0 = lane.interpolatedValue(atBar: 0.0)
        #expect(v0 != nil)
        #expect(abs(v0! - 0.0) < 0.001)

        // At bar 2 (midpoint) → 0.5
        let v2 = lane.interpolatedValue(atBar: 2.0)
        #expect(v2 != nil)
        #expect(abs(v2! - 0.5) < 0.001)

        // At bar 4 (end) → 1.0
        let v4 = lane.interpolatedValue(atBar: 4.0)
        #expect(v4 != nil)
        #expect(abs(v4! - 1.0) < 0.001)

        // At bar 1 (quarter) → 0.25
        let v1 = lane.interpolatedValue(atBar: 1.0)
        #expect(v1 != nil)
        #expect(abs(v1! - 0.25) < 0.001)
    }

    @Test("Track pan automation interpolation")
    func trackPanAutomationInterpolation() {
        let trackID = ID<Track>()
        let lane = AutomationLane(
            targetPath: .trackPan(trackID: trackID),
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.0),   // Full left (-1.0 when mapped)
                AutomationBreakpoint(position: 8.0, value: 1.0)    // Full right (+1.0 when mapped)
            ]
        )

        // At bar 4 (midpoint) → 0.5 normalized, which maps to 0.0 pan (center)
        let v4 = lane.interpolatedValue(atBar: 4.0)
        #expect(v4 != nil)
        #expect(abs(v4! - 0.5) < 0.001)

        // At bar 0 → 0.0 normalized (full left)
        let v0 = lane.interpolatedValue(atBar: 0.0)
        #expect(v0 != nil)
        #expect(abs(v0! - 0.0) < 0.001)
    }

    @Test("No automation → nil value")
    func noAutomationReturnsNil() {
        let trackID = ID<Track>()
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: trackID),
            breakpoints: []
        )
        #expect(lane.interpolatedValue(atBar: 2.0) == nil)
    }

    // MARK: - ProjectViewModel Track Automation CRUD

    @Test("Add track automation lane")
    @MainActor
    func addTrackAutomationLane() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.isTrackVolume)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Remove track automation lane")
    @MainActor
    func removeTrackAutomationLane() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        vm.removeTrackAutomationLane(trackID: trackID, laneID: lane.id)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.isEmpty)
    }

    @Test("Add breakpoint to track automation lane")
    @MainActor
    func addTrackBreakpoint() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let bp = AutomationBreakpoint(position: 2.0, value: 0.7)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints[0].value == 0.7)
    }

    @Test("Update breakpoint in track automation lane")
    @MainActor
    func updateTrackBreakpoint() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let bp = AutomationBreakpoint(position: 2.0, value: 0.5)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp)
        var updated = bp
        updated.value = 0.8
        updated.position = 3.0
        vm.updateTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: updated)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints[0].value == 0.8)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints[0].position == 3.0)
    }

    @Test("Remove breakpoint from track automation lane")
    @MainActor
    func removeTrackBreakpoint() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let bp = AutomationBreakpoint(position: 2.0, value: 0.5)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 1)
        vm.removeTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpointID: bp.id)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.isEmpty)
    }

    @Test("Track automation undo/redo for add lane")
    @MainActor
    func trackAutomationUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.isEmpty)
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
    }

    @Test("Track automation undo/redo for add breakpoint")
    @MainActor
    func trackBreakpointUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let bp = AutomationBreakpoint(position: 2.0, value: 0.5)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 1)
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.isEmpty)
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 1)
    }

    // MARK: - TimelineViewModel Integration

    @Test("TimelineViewModel lane count includes track automation lanes")
    @MainActor
    func timelineViewModelLaneCountIncludesTrackAutomation() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        let containerEffectPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)
        let containerLane = AutomationLane(targetPath: containerEffectPath)
        let container = Container(name: "C1", startBar: 1, lengthBars: 4, automationLanes: [containerLane])
        let volumeLane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        let track = Track(
            id: trackID,
            name: "T1",
            kind: .audio,
            containers: [container],
            trackAutomationLanes: [volumeLane]
        )

        let count = vm.automationLaneCount(for: track)
        #expect(count == 2) // 1 container lane + 1 track volume lane
    }

    @Test("TimelineViewModel track height includes track automation sub-lanes")
    @MainActor
    func timelineViewModelTrackHeightWithTrackAutomation() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        let volumeLane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        let panLane = AutomationLane(targetPath: .trackPan(trackID: trackID))
        let track = Track(
            id: trackID,
            name: "T1",
            kind: .audio,
            trackAutomationLanes: [volumeLane, panLane]
        )

        let baseHeight: CGFloat = 80

        // Not expanded → base height
        let h1 = vm.trackHeight(for: track, baseHeight: baseHeight)
        #expect(h1 == baseHeight)

        // Expanded → base + 2 sub-lane heights (volume + pan)
        vm.automationExpanded.insert(track.id)
        let h2 = vm.trackHeight(for: track, baseHeight: baseHeight)
        #expect(h2 == baseHeight + 2 * TimelineViewModel.automationSubLaneHeight)
    }

    // MARK: - DuplicateSong copies track automation

    @Test("DuplicateSong copies trackAutomationLanes")
    @MainActor
    func duplicateSongCopiesTrackAutomation() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: trackID),
            breakpoints: [AutomationBreakpoint(position: 0.0, value: 0.5)]
        )
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let songID = vm.project.songs[0].id
        vm.duplicateSong(id: songID)
        #expect(vm.project.songs.count == 2)
        let copiedTrack = vm.project.songs[1].tracks[0]
        #expect(copiedTrack.trackAutomationLanes.count == 1)
        #expect(copiedTrack.trackAutomationLanes[0].breakpoints.count == 1)
    }

    @Test("DuplicateTrack copies trackAutomationLanes")
    @MainActor
    func duplicateTrackCopiesTrackAutomation() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: trackID),
            breakpoints: [AutomationBreakpoint(position: 0.0, value: 0.7)]
        )
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let newID = vm.duplicateTrack(trackID: trackID)
        #expect(newID != nil)
        let copiedTrack = vm.project.songs[0].tracks.first(where: { $0.id == newID })
        #expect(copiedTrack != nil)
        #expect(copiedTrack!.trackAutomationLanes.count == 1)
        #expect(copiedTrack!.trackAutomationLanes[0].breakpoints[0].value == 0.7)
    }

    @Test("Invalid track ID does not crash for track automation operations")
    @MainActor
    func invalidTrackIDNoOp() {
        let vm = ProjectViewModel()
        vm.newProject()
        let fakeTrackID = ID<Track>()
        let lane = AutomationLane(targetPath: .trackVolume(trackID: fakeTrackID))
        vm.addTrackAutomationLane(trackID: fakeTrackID, lane: lane)
        // Should not crash, just no-op
        vm.removeTrackAutomationLane(trackID: fakeTrackID, laneID: lane.id)
        let bp = AutomationBreakpoint(position: 0, value: 0.5)
        vm.addTrackAutomationBreakpoint(trackID: fakeTrackID, laneID: lane.id, breakpoint: bp)
        vm.removeTrackAutomationBreakpoint(trackID: fakeTrackID, laneID: lane.id, breakpointID: bp.id)
        vm.updateTrackAutomationBreakpoint(trackID: fakeTrackID, laneID: lane.id, breakpoint: bp)
    }

    // MARK: - Effect Parameter Automation (Issue #94)

    @Test("EffectPath isTrackEffectParameter identifies track-level effect parameters")
    func effectPathIsTrackEffectParameter() {
        let trackID = ID<Track>()
        // Track-level effect parameter (effectIndex >= 0, no containerID)
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        #expect(effectPath.isTrackEffectParameter)
        #expect(!effectPath.isTrackParameter)
        #expect(!effectPath.isTrackVolume)
        #expect(!effectPath.isTrackPan)

        // Container-level effect parameter is NOT a track effect parameter
        let containerPath = EffectPath(trackID: trackID, containerID: ID<Container>(), effectIndex: 0, parameterAddress: 42)
        #expect(!containerPath.isTrackEffectParameter)

        // Track volume sentinel is NOT a track effect parameter
        let volumePath = EffectPath.trackVolume(trackID: trackID)
        #expect(!volumePath.isTrackEffectParameter)

        // Track pan sentinel is NOT a track effect parameter
        let panPath = EffectPath.trackPan(trackID: trackID)
        #expect(!panPath.isTrackEffectParameter)
    }

    @Test("EffectPath for track effect parameter Codable round-trip")
    func effectPathTrackEffectParameterRoundTrip() throws {
        let trackID = ID<Track>()
        let path = EffectPath(trackID: trackID, containerID: nil, effectIndex: 2, parameterAddress: 100)
        let decoded = try roundTrip(path)
        #expect(decoded == path)
        #expect(decoded.isTrackEffectParameter)
        #expect(decoded.effectIndex == 2)
        #expect(decoded.parameterAddress == 100)
    }

    @Test("Track effect parameter automation lane interpolation")
    func trackEffectParameterAutomationInterpolation() {
        let trackID = ID<Track>()
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        let lane = AutomationLane(
            targetPath: effectPath,
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.0),
                AutomationBreakpoint(position: 8.0, value: 1.0)
            ]
        )

        // At bar 0 → 0.0
        let v0 = lane.interpolatedValue(atBar: 0.0)
        #expect(v0 != nil)
        #expect(abs(v0! - 0.0) < 0.001)

        // At bar 4 (midpoint) → 0.5
        let v4 = lane.interpolatedValue(atBar: 4.0)
        #expect(v4 != nil)
        #expect(abs(v4! - 0.5) < 0.001)

        // At bar 8 (end) → 1.0
        let v8 = lane.interpolatedValue(atBar: 8.0)
        #expect(v8 != nil)
        #expect(abs(v8! - 1.0) < 0.001)
    }

    @Test("Add track effect parameter automation lane via ProjectViewModel")
    @MainActor
    func addTrackEffectParameterAutomationLane() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        let lane = AutomationLane(targetPath: effectPath)
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.isTrackEffectParameter)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.effectIndex == 0)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.parameterAddress == 42)
    }

    @Test("Add and remove breakpoints on track effect parameter automation lane")
    @MainActor
    func trackEffectParameterBreakpointCRUD() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 1, parameterAddress: 99)
        let lane = AutomationLane(targetPath: effectPath)
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)

        // Add breakpoints
        let bp1 = AutomationBreakpoint(position: 0.0, value: 0.2)
        let bp2 = AutomationBreakpoint(position: 4.0, value: 0.9)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp1)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp2)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 2)

        // Update breakpoint
        var updated = bp1
        updated.value = 0.5
        vm.updateTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: updated)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints[0].value == 0.5)

        // Remove breakpoint
        vm.removeTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpointID: bp2.id)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 1)
    }

    @Test("Track effect parameter automation undo/redo")
    @MainActor
    func trackEffectParameterAutomationUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        let lane = AutomationLane(
            targetPath: effectPath,
            breakpoints: [AutomationBreakpoint(position: 0.0, value: 0.5)]
        )
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.isEmpty)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.isTrackEffectParameter)
    }

    @Test("Track with effect parameter automation Codable round-trip")
    func trackWithEffectParameterAutomationRoundTrip() throws {
        let trackID = ID<Track>()
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        let lane = AutomationLane(
            targetPath: effectPath,
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.1),
                AutomationBreakpoint(position: 4.0, value: 0.8)
            ]
        )
        let volumeLane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        let track = Track(
            id: trackID,
            name: "FX Track",
            kind: .audio,
            trackAutomationLanes: [volumeLane, lane],
            orderIndex: 0
        )
        let decoded = try roundTrip(track)
        #expect(decoded.trackAutomationLanes.count == 2)
        #expect(decoded.trackAutomationLanes[0].targetPath.isTrackVolume)
        #expect(decoded.trackAutomationLanes[1].targetPath.isTrackEffectParameter)
        #expect(decoded.trackAutomationLanes[1].targetPath.parameterAddress == 42)
        #expect(decoded.trackAutomationLanes[1].breakpoints.count == 2)
    }

    @Test("TimelineViewModel lane count includes effect parameter automation lanes")
    @MainActor
    func laneCountIncludesEffectParameterLanes() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        let volumeLane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        let effectLane = AutomationLane(targetPath: effectPath)
        let track = Track(
            id: trackID,
            name: "T1",
            kind: .audio,
            trackAutomationLanes: [volumeLane, effectLane]
        )

        let count = vm.automationLaneCount(for: track)
        #expect(count == 2) // volume + effect parameter
    }

    @Test("Multiple effect parameter automation lanes for different effects")
    @MainActor
    func multipleEffectParameterLanes() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Add lanes for two different effect parameters
        let path1 = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 10)
        let path2 = EffectPath(trackID: trackID, containerID: nil, effectIndex: 1, parameterAddress: 20)
        let lane1 = AutomationLane(targetPath: path1)
        let lane2 = AutomationLane(targetPath: path2)
        vm.addTrackAutomationLane(trackID: trackID, lane: lane1)
        vm.addTrackAutomationLane(trackID: trackID, lane: lane2)

        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 2)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.effectIndex == 0)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[1].targetPath.effectIndex == 1)
    }

    @Test("DuplicateTrack copies effect parameter automation lanes")
    @MainActor
    func duplicateTrackCopiesEffectParameterLanes() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        let lane = AutomationLane(
            targetPath: effectPath,
            breakpoints: [AutomationBreakpoint(position: 0.0, value: 0.6)]
        )
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let newID = vm.duplicateTrack(trackID: trackID)
        #expect(newID != nil)
        let copiedTrack = vm.project.songs[0].tracks.first(where: { $0.id == newID })
        #expect(copiedTrack != nil)
        #expect(copiedTrack!.trackAutomationLanes.count == 1)
        #expect(copiedTrack!.trackAutomationLanes[0].targetPath.isTrackEffectParameter)
        #expect(copiedTrack!.trackAutomationLanes[0].breakpoints[0].value == 0.6)
    }

    // MARK: - Instrument Parameter Automation (Issue #95)

    @Test("EffectPath isTrackInstrumentParameter identifies instrument parameter paths")
    func effectPathIsTrackInstrumentParameter() {
        let trackID = ID<Track>()
        // Instrument parameter path (sentinel effectIndex = -2)
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 100)
        #expect(instPath.isTrackInstrumentParameter)
        #expect(!instPath.isTrackEffectParameter)
        #expect(!instPath.isTrackParameter)
        #expect(!instPath.isTrackVolume)
        #expect(!instPath.isTrackPan)
        #expect(instPath.effectIndex == EffectPath.instrumentParameterEffectIndex)
        #expect(instPath.parameterAddress == 100)
        #expect(instPath.containerID == nil)

        // Verify other path types are NOT instrument parameters
        let volumePath = EffectPath.trackVolume(trackID: trackID)
        #expect(!volumePath.isTrackInstrumentParameter)

        let panPath = EffectPath.trackPan(trackID: trackID)
        #expect(!panPath.isTrackInstrumentParameter)

        let effectPath = EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42)
        #expect(!effectPath.isTrackInstrumentParameter)

        let containerPath = EffectPath(trackID: trackID, containerID: ID<Container>(), effectIndex: EffectPath.instrumentParameterEffectIndex, parameterAddress: 42)
        #expect(!containerPath.isTrackInstrumentParameter) // container-level, not track-level
    }

    @Test("EffectPath trackInstrument factory creates correct sentinel values")
    func effectPathTrackInstrumentFactory() {
        let trackID = ID<Track>()
        let path = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 55)
        #expect(path.trackID == trackID)
        #expect(path.containerID == nil)
        #expect(path.effectIndex == -2)
        #expect(path.parameterAddress == 55)
        #expect(path.isTrackInstrumentParameter)
    }

    @Test("EffectPath instrument parameter Codable round-trip")
    func effectPathInstrumentParameterRoundTrip() throws {
        let trackID = ID<Track>()
        let path = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 200)
        let decoded = try roundTrip(path)
        #expect(decoded == path)
        #expect(decoded.isTrackInstrumentParameter)
        #expect(decoded.effectIndex == EffectPath.instrumentParameterEffectIndex)
        #expect(decoded.parameterAddress == 200)
    }

    @Test("Instrument parameter automation lane interpolation")
    func instrumentParameterAutomationInterpolation() {
        let trackID = ID<Track>()
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 100)
        let lane = AutomationLane(
            targetPath: instPath,
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.0),
                AutomationBreakpoint(position: 8.0, value: 1.0)
            ]
        )

        // At bar 0 → 0.0
        let v0 = lane.interpolatedValue(atBar: 0.0)
        #expect(v0 != nil)
        #expect(abs(v0! - 0.0) < 0.001)

        // At bar 4 (midpoint) → 0.5
        let v4 = lane.interpolatedValue(atBar: 4.0)
        #expect(v4 != nil)
        #expect(abs(v4! - 0.5) < 0.001)

        // At bar 8 (end) → 1.0
        let v8 = lane.interpolatedValue(atBar: 8.0)
        #expect(v8 != nil)
        #expect(abs(v8! - 1.0) < 0.001)
    }

    @Test("Add track instrument parameter automation lane via ProjectViewModel")
    @MainActor
    func addTrackInstrumentParameterAutomationLane() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 100)
        let lane = AutomationLane(targetPath: instPath)
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.isTrackInstrumentParameter)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.parameterAddress == 100)
    }

    @Test("Add and remove breakpoints on instrument parameter automation lane")
    @MainActor
    func instrumentParameterBreakpointCRUD() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 50)
        let lane = AutomationLane(targetPath: instPath)
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)

        // Add breakpoints
        let bp1 = AutomationBreakpoint(position: 0.0, value: 0.3)
        let bp2 = AutomationBreakpoint(position: 4.0, value: 0.7)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp1)
        vm.addTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: bp2)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 2)

        // Update breakpoint
        var updated = bp1
        updated.value = 0.6
        vm.updateTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpoint: updated)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints[0].value == 0.6)

        // Remove breakpoint
        vm.removeTrackAutomationBreakpoint(trackID: trackID, laneID: lane.id, breakpointID: bp2.id)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].breakpoints.count == 1)
    }

    @Test("Instrument parameter automation undo/redo")
    @MainActor
    func instrumentParameterAutomationUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 100)
        let lane = AutomationLane(
            targetPath: instPath,
            breakpoints: [AutomationBreakpoint(position: 0.0, value: 0.5)]
        )
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.isEmpty)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.isTrackInstrumentParameter)
    }

    @Test("Track with instrument parameter automation Codable round-trip")
    func trackWithInstrumentParameterAutomationRoundTrip() throws {
        let trackID = ID<Track>()
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 100)
        let instLane = AutomationLane(
            targetPath: instPath,
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.2),
                AutomationBreakpoint(position: 8.0, value: 0.9)
            ]
        )
        let volumeLane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        let track = Track(
            id: trackID,
            name: "MIDI Inst",
            kind: .midi,
            trackAutomationLanes: [volumeLane, instLane],
            orderIndex: 0
        )
        let decoded = try roundTrip(track)
        #expect(decoded.trackAutomationLanes.count == 2)
        #expect(decoded.trackAutomationLanes[0].targetPath.isTrackVolume)
        #expect(decoded.trackAutomationLanes[1].targetPath.isTrackInstrumentParameter)
        #expect(decoded.trackAutomationLanes[1].targetPath.parameterAddress == 100)
        #expect(decoded.trackAutomationLanes[1].breakpoints.count == 2)
    }

    @Test("TimelineViewModel lane count includes instrument parameter automation lanes")
    @MainActor
    func laneCountIncludesInstrumentParameterLanes() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        let volumeLane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 100)
        let instLane = AutomationLane(targetPath: instPath)
        let track = Track(
            id: trackID,
            name: "T1",
            kind: .midi,
            trackAutomationLanes: [volumeLane, instLane]
        )

        let count = vm.automationLaneCount(for: track)
        #expect(count == 2) // volume + instrument parameter
    }

    @Test("DuplicateTrack copies instrument parameter automation lanes")
    @MainActor
    func duplicateTrackCopiesInstrumentParameterLanes() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        let instPath = EffectPath.trackInstrument(trackID: trackID, parameterAddress: 100)
        let lane = AutomationLane(
            targetPath: instPath,
            breakpoints: [AutomationBreakpoint(position: 0.0, value: 0.4)]
        )
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let newID = vm.duplicateTrack(trackID: trackID)
        #expect(newID != nil)
        let copiedTrack = vm.project.songs[0].tracks.first(where: { $0.id == newID })
        #expect(copiedTrack != nil)
        #expect(copiedTrack!.trackAutomationLanes.count == 1)
        #expect(copiedTrack!.trackAutomationLanes[0].targetPath.isTrackInstrumentParameter)
        #expect(copiedTrack!.trackAutomationLanes[0].breakpoints[0].value == 0.4)
    }

    @Test("Mixed instrument, effect, and volume automation lanes coexist on track")
    @MainActor
    func mixedInstrumentEffectVolumeLanes() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id

        // Add volume, instrument, and effect parameter lanes
        let volumeLane = AutomationLane(targetPath: .trackVolume(trackID: trackID))
        let instLane = AutomationLane(targetPath: .trackInstrument(trackID: trackID, parameterAddress: 100))
        let effectLane = AutomationLane(targetPath: EffectPath(trackID: trackID, containerID: nil, effectIndex: 0, parameterAddress: 42))

        vm.addTrackAutomationLane(trackID: trackID, lane: volumeLane)
        vm.addTrackAutomationLane(trackID: trackID, lane: instLane)
        vm.addTrackAutomationLane(trackID: trackID, lane: effectLane)

        let track = vm.project.songs[0].tracks[0]
        #expect(track.trackAutomationLanes.count == 3)
        #expect(track.trackAutomationLanes[0].targetPath.isTrackVolume)
        #expect(track.trackAutomationLanes[1].targetPath.isTrackInstrumentParameter)
        #expect(track.trackAutomationLanes[2].targetPath.isTrackEffectParameter)
    }

    @Test("Search filtering returns correct results for partial instrument parameter name matches")
    func searchFilteringForInstrumentParameters() {
        // This tests the filtering logic used by ParameterPickerView
        let params = [
            AudioUnitParameterInfo(address: 0, displayName: "Cutoff Frequency", groupName: "Filter", minValue: 20, maxValue: 20000, defaultValue: 1000, unit: "Hz"),
            AudioUnitParameterInfo(address: 1, displayName: "Resonance", groupName: "Filter", minValue: 0, maxValue: 1, defaultValue: 0.5, unit: ""),
            AudioUnitParameterInfo(address: 2, displayName: "Attack Time", groupName: "Envelope", minValue: 0, maxValue: 10, defaultValue: 0.01, unit: "s"),
            AudioUnitParameterInfo(address: 3, displayName: "Release Time", groupName: "Envelope", minValue: 0, maxValue: 10, defaultValue: 0.5, unit: "s"),
        ]

        // Filter by display name
        let cutoffResults = params.filter {
            $0.displayName.localizedCaseInsensitiveContains("cutoff")
            || $0.groupName.localizedCaseInsensitiveContains("cutoff")
        }
        #expect(cutoffResults.count == 1)
        #expect(cutoffResults[0].address == 0)

        // Filter by group name
        let filterResults = params.filter {
            $0.displayName.localizedCaseInsensitiveContains("filter")
            || $0.groupName.localizedCaseInsensitiveContains("filter")
        }
        #expect(filterResults.count == 2) // Cutoff + Resonance both in Filter group

        // Filter by partial name
        let timeResults = params.filter {
            $0.displayName.localizedCaseInsensitiveContains("time")
            || $0.groupName.localizedCaseInsensitiveContains("time")
        }
        #expect(timeResults.count == 2) // Attack Time + Release Time
    }
}
