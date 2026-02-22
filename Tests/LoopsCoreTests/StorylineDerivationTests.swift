import Testing
import Foundation
@testable import LoopsCore

@Suite("StorylineDerivation Tests")
struct StorylineDerivationTests {

    // MARK: - Helpers

    private func makeTrack(
        name: String = "Track 1",
        kind: TrackKind = .audio,
        containers: [Container] = [],
        isRecordArmed: Bool = false
    ) -> Track {
        Track(
            name: name,
            kind: kind,
            containers: containers,
            isRecordArmed: isRecordArmed
        )
    }

    private func makeContainer(
        name: String = "Container",
        startBar: Int = 1,
        lengthBars: Int = 4,
        onEnterActions: [ContainerAction] = [],
        onExitActions: [ContainerAction] = [],
        insertEffects: [InsertEffect] = [],
        automationLanes: [AutomationLane] = [],
        isRecordArmed: Bool = false
    ) -> Container {
        Container(
            name: name,
            startBar: startBar,
            lengthBars: lengthBars,
            isRecordArmed: isRecordArmed,
            insertEffects: insertEffects,
            onEnterActions: onEnterActions,
            onExitActions: onExitActions,
            automationLanes: automationLanes
        )
    }

    private func makeSection(
        name: String = "Section",
        startBar: Int = 1,
        lengthBars: Int = 4,
        notes: String? = nil
    ) -> SectionRegion {
        SectionRegion(name: name, startBar: startBar, lengthBars: lengthBars, notes: notes)
    }

    // MARK: - Tests

    @Test("Storyline derivation with sections, containers, and actions produces correct summary")
    func deriveSectionsWithContainersAndActions() {
        let enterAction = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 42),
            destination: .externalPort(name: "Keyboard")
        )
        let container1 = makeContainer(name: "Loop A", startBar: 1, lengthBars: 4)
        let container2 = makeContainer(name: "Keys Pad", startBar: 1, lengthBars: 4, onEnterActions: [enterAction])

        let track1 = makeTrack(name: "Drums", containers: [container1])
        let track2 = makeTrack(name: "Keys", kind: .midi, containers: [container2])

        let section = makeSection(name: "Intro", startBar: 1, lengthBars: 4)

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track1, track2])
        #expect(entries.count == 1)
        #expect(entries[0].section.name == "Intro")
        #expect(entries[0].trackSummaries.count == 2)

        // Drums track
        #expect(entries[0].trackSummaries[0].trackName == "Drums")
        #expect(entries[0].trackSummaries[0].containers.count == 1)
        #expect(entries[0].trackSummaries[0].containers[0].containerName == "Loop A")

        // Keys track
        #expect(entries[0].trackSummaries[1].trackName == "Keys")
        #expect(entries[0].trackSummaries[1].containers[0].enterActionDescriptions.count == 1)
        #expect(entries[0].trackSummaries[1].containers[0].enterActionDescriptions[0].contains("PC #42"))
    }

    @Test("Section with no containers produces empty entry")
    func sectionWithNoContainers() {
        let section = makeSection(name: "Empty Section", startBar: 1, lengthBars: 4)
        let track = makeTrack(name: "Guitar", containers: [])

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track])
        #expect(entries.count == 1)
        #expect(entries[0].trackSummaries.isEmpty)
        #expect(entries[0].summary == "Empty")
    }

    @Test("Section spanning multiple tracks aggregates all container actions")
    func sectionSpansMultipleTracks() {
        let midi1 = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 1),
            destination: .externalPort(name: "Synth")
        )
        let midi2 = ContainerAction.makeSendMIDI(
            message: .controlChange(channel: 0, controller: 64, value: 127),
            destination: .externalPort(name: "Pedal")
        )
        let container1 = makeContainer(name: "Riff", startBar: 1, lengthBars: 8, onEnterActions: [midi1])
        let container2 = makeContainer(name: "Bass Line", startBar: 1, lengthBars: 8, onExitActions: [midi2])
        let container3 = makeContainer(name: "Beat", startBar: 1, lengthBars: 8)

        let track1 = makeTrack(name: "Guitar", containers: [container1])
        let track2 = makeTrack(name: "Bass", containers: [container2])
        let track3 = makeTrack(name: "Drums", containers: [container3])

        let section = makeSection(name: "Verse", startBar: 1, lengthBars: 8)

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track1, track2, track3])
        #expect(entries.count == 1)
        #expect(entries[0].trackSummaries.count == 3)

        // Guitar has enter action
        #expect(entries[0].trackSummaries[0].containers[0].enterActionDescriptions.count == 1)
        // Bass has exit action
        #expect(entries[0].trackSummaries[1].containers[0].exitActionDescriptions.count == 1)
        #expect(entries[0].trackSummaries[1].containers[0].exitActionDescriptions[0].contains("CC #64"))
        // Drums has no actions
        #expect(entries[0].trackSummaries[2].containers[0].enterActionDescriptions.isEmpty)
    }

    @Test("Notes field Codable round-trip")
    func notesCodableRoundTrip() throws {
        let section = SectionRegion(
            name: "Chorus",
            startBar: 9,
            lengthBars: 8,
            color: "#FF0000",
            notes: "Wait for crowd before starting"
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(section)
        let decoded = try decoder.decode(SectionRegion.self, from: data)
        #expect(decoded.notes == "Wait for crowd before starting")

        // Nil notes also round-trips
        let noNotes = SectionRegion(name: "Bridge", startBar: 17, lengthBars: 4)
        let data2 = try encoder.encode(noNotes)
        let decoded2 = try decoder.decode(SectionRegion.self, from: data2)
        #expect(decoded2.notes == nil)
    }

    @Test("Sections sorted by startBar regardless of creation order")
    func sectionsSortedByStartBar() {
        let section3 = makeSection(name: "Outro", startBar: 17, lengthBars: 4)
        let section1 = makeSection(name: "Intro", startBar: 1, lengthBars: 4)
        let section2 = makeSection(name: "Verse", startBar: 5, lengthBars: 8)

        let entries = StorylineDerivation.derive(
            sections: [section3, section1, section2],
            tracks: []
        )
        #expect(entries.count == 3)
        #expect(entries[0].section.name == "Intro")
        #expect(entries[1].section.name == "Verse")
        #expect(entries[2].section.name == "Outro")
    }

    @Test("Container partially overlapping section is included")
    func containerPartiallyOverlapping() {
        // Container spans bars 3-7, section spans bars 5-9
        let container = makeContainer(name: "Overlap", startBar: 3, lengthBars: 4)
        let track = makeTrack(name: "Guitar", containers: [container])
        let section = makeSection(name: "Verse", startBar: 5, lengthBars: 4)

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track])
        #expect(entries[0].trackSummaries.count == 1)
        #expect(entries[0].trackSummaries[0].containers[0].containerName == "Overlap")
    }

    @Test("Container outside section range is excluded")
    func containerOutsideSectionRange() {
        // Container spans bars 10-14, section spans bars 1-4
        let container = makeContainer(name: "Far Away", startBar: 10, lengthBars: 4)
        let track = makeTrack(name: "Guitar", containers: [container])
        let section = makeSection(name: "Intro", startBar: 1, lengthBars: 4)

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track])
        #expect(entries[0].trackSummaries.isEmpty)
    }

    @Test("Record armed track appears in storyline even without containers")
    func recordArmedTrackAppears() {
        let track = makeTrack(name: "Guitar", containers: [], isRecordArmed: true)
        let section = makeSection(name: "Intro", startBar: 1, lengthBars: 4)

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track])
        #expect(entries[0].trackSummaries.count == 1)
        #expect(entries[0].trackSummaries[0].isRecordArmed)
        #expect(entries[0].summary.contains("record armed"))
    }

    @Test("Effects and automation lanes are reported")
    func effectsAndAutomationReported() {
        let effect = InsertEffect(
            component: AudioComponentInfo(componentType: 0x61756678, componentSubType: 0x64656C79, componentManufacturer: 0x6170706C),
            displayName: "Reverb"
        )
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: ID(), effectIndex: 0, parameterAddress: 0),
            breakpoints: []
        )
        let container = makeContainer(
            name: "Pad",
            startBar: 1,
            lengthBars: 4,
            insertEffects: [effect],
            automationLanes: [lane]
        )
        let track = makeTrack(name: "Synth", kind: .midi, containers: [container])
        let section = makeSection(name: "Intro", startBar: 1, lengthBars: 4)

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track])
        let containerSummary = entries[0].trackSummaries[0].containers[0]
        #expect(containerSummary.effectNames == ["Reverb"])
        #expect(containerSummary.automationLaneCount == 1)
    }

    @Test("Trigger actions produce descriptive summary")
    func triggerActionsSummary() {
        let targetID = ID<Container>()
        let triggerAction = ContainerAction.makeTriggerContainer(targetID: targetID, action: .start)
        let container = makeContainer(name: "Trigger Box", startBar: 1, lengthBars: 4, onEnterActions: [triggerAction])
        let track = makeTrack(name: "Control", containers: [container])
        let section = makeSection(name: "Intro", startBar: 1, lengthBars: 4)

        let entries = StorylineDerivation.derive(sections: [section], tracks: [track])
        let desc = entries[0].trackSummaries[0].containers[0].enterActionDescriptions[0]
        #expect(desc == "Trigger Start")
    }

    @Test("Multiple sections with mixed content")
    func multipleSectionsWithMixedContent() {
        let c1 = makeContainer(name: "Riff A", startBar: 1, lengthBars: 4)
        let c2 = makeContainer(name: "Riff B", startBar: 5, lengthBars: 8)
        let track = makeTrack(name: "Guitar", containers: [c1, c2])

        let s1 = makeSection(name: "Intro", startBar: 1, lengthBars: 4)
        let s2 = makeSection(name: "Verse", startBar: 5, lengthBars: 8)
        let s3 = makeSection(name: "Bridge", startBar: 13, lengthBars: 4)

        let entries = StorylineDerivation.derive(sections: [s1, s2, s3], tracks: [track])
        #expect(entries.count == 3)
        // Intro has Riff A
        #expect(entries[0].trackSummaries[0].containers[0].containerName == "Riff A")
        // Verse has Riff B
        #expect(entries[1].trackSummaries[0].containers[0].containerName == "Riff B")
        // Bridge has no containers
        #expect(entries[2].trackSummaries.isEmpty)
    }
}
