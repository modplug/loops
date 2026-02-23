import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Linked Clip Inspector Tests")
struct LinkedClipInspectorTests {

    // MARK: - Parent Container Resolution

    @Test("Linked clip with no overrides shows all fields as inherited")
    @MainActor
    func linkedClipNoOverrides() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Create a clone
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)
        #expect(cloneID != nil)

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(clone.isClone)
        #expect(clone.overriddenFields.isEmpty)

        // All fields should be inherited (not overridden)
        for field in ContainerField.allCases {
            #expect(!clone.overriddenFields.contains(field))
        }
    }

    @Test("Linked clip with overrides shows correct diff badges")
    @MainActor
    func linkedClipWithOverrides() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Create a clone
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Override the name
        vm.selectedContainerID = cloneID
        vm.updateContainerName(containerID: cloneID, name: "Custom Name")

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(clone.overriddenFields.contains(.name))
        #expect(clone.name == "Custom Name")

        // Other fields should still be inherited
        #expect(!clone.overriddenFields.contains(.effects))
        #expect(!clone.overriddenFields.contains(.fades))
        #expect(!clone.overriddenFields.contains(.automation))
    }

    @Test("Parent container reference resolves correctly")
    @MainActor
    func parentContainerResolves() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        vm.updateContainerName(containerID: parentID, name: "Parent Container")

        // Create a clone
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(clone.parentContainerID == parentID)

        // findContainer should resolve the parent
        let parent = vm.findContainer(id: parentID)
        #expect(parent != nil)
        #expect(parent?.name == "Parent Container")
        #expect(parent?.startBar == 1)
        #expect(parent?.endBar == 5)
    }

    @Test("Navigate to parent selects parent container")
    @MainActor
    func navigateToParent() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        #expect(vm.selectedContainerID == cloneID)

        // Navigate to parent
        vm.selectedContainerID = parentID
        #expect(vm.selectedContainerID == parentID)
        #expect(vm.selectedContainer?.id == parentID)
    }

    @Test("ContainerField displayName returns human-readable names")
    func containerFieldDisplayNames() {
        #expect(ContainerField.effects.displayName == "Effects")
        #expect(ContainerField.automation.displayName == "Automation")
        #expect(ContainerField.fades.displayName == "Fades")
        #expect(ContainerField.enterActions.displayName == "Enter Actions")
        #expect(ContainerField.exitActions.displayName == "Exit Actions")
        #expect(ContainerField.name.displayName == "Name")
        #expect(ContainerField.loopSettings.displayName == "Loop Settings")
        #expect(ContainerField.instrumentOverride.displayName == "Instrument")
    }

    @Test("Multiple overrides tracked correctly on clone")
    @MainActor
    func multipleOverrides() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Override name
        vm.updateContainerName(containerID: cloneID, name: "Override Name")
        // Override enter fade
        vm.setContainerEnterFade(containerID: cloneID, fade: FadeSettings(duration: 1.0, curve: .linear))
        // Override exit fade
        vm.setContainerExitFade(containerID: cloneID, fade: FadeSettings(duration: 2.0, curve: .exponential))

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(clone.overriddenFields.contains(.name))
        #expect(clone.overriddenFields.contains(.fades))
        #expect(!clone.overriddenFields.contains(.effects))
        #expect(!clone.overriddenFields.contains(.automation))
        #expect(!clone.overriddenFields.contains(.enterActions))
        #expect(!clone.overriddenFields.contains(.exitActions))
        #expect(!clone.overriddenFields.contains(.loopSettings))
        #expect(!clone.overriddenFields.contains(.instrumentOverride))
    }

    @Test("Clone resolution inherits non-overridden fields from parent")
    @MainActor
    func cloneResolutionInheritsFromParent() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        vm.updateContainerName(containerID: parentID, name: "Parent Name")

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Override only the fades
        vm.setContainerEnterFade(containerID: cloneID, fade: FadeSettings(duration: 1.0, curve: .linear))

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        let parent = vm.findContainer(id: parentID)!
        let resolved = clone.resolved(parent: parent)

        // Name should be inherited from parent (not overridden)
        #expect(resolved.name == "Parent Name")
        // Fades should be local (overridden)
        #expect(resolved.enterFade != nil)
        #expect(resolved.enterFade?.duration == 1.0)
    }

    @Test("Missing parent shows nil for parentContainer lookup")
    @MainActor
    func missingParentContainer() {
        // Create a container with a parentContainerID that doesn't exist
        let orphanParentID = ID<Container>()
        let container = Container(
            name: "Orphan Clone",
            startBar: 1,
            lengthBars: 4,
            parentContainerID: orphanParentID,
            overriddenFields: []
        )

        #expect(container.isClone)
        #expect(container.parentContainerID == orphanParentID)

        // Lookup in an empty context returns nil
        let vm = ProjectViewModel()
        vm.newProject()
        let result = vm.findContainer(id: orphanParentID)
        #expect(result == nil)
    }

    // MARK: - Reset Field to Parent Value

    @Test("Reset field removes it from overriddenFields")
    @MainActor
    func resetFieldRemovesOverride() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Override name
        vm.updateContainerName(containerID: cloneID, name: "Custom Name")
        let cloneBefore = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(cloneBefore.overriddenFields.contains(.name))

        // Reset the name field
        vm.resetContainerField(containerID: cloneID, field: .name)

        let cloneAfter = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(!cloneAfter.overriddenFields.contains(.name))
    }

    @Test("Reset field copies parent's current value into clone")
    @MainActor
    func resetFieldCopiesParentValue() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        vm.updateContainerName(containerID: parentID, name: "Parent Name")

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        vm.updateContainerName(containerID: cloneID, name: "Clone Override")

        let cloneBefore = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(cloneBefore.name == "Clone Override")

        // Reset — should copy parent's current value
        vm.resetContainerField(containerID: cloneID, field: .name)

        let cloneAfter = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(cloneAfter.name == "Parent Name")
    }

    @Test("After reset, clone inherits future parent edits via resolved()")
    @MainActor
    func resetFieldInheritsFutureParentEdits() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        vm.updateContainerName(containerID: parentID, name: "Original")

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        vm.updateContainerName(containerID: cloneID, name: "Override")
        vm.resetContainerField(containerID: cloneID, field: .name)

        // Now edit parent's name
        vm.updateContainerName(containerID: parentID, name: "Updated Parent")

        // Clone should inherit the new parent name via resolved()
        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        let parent = vm.findContainer(id: parentID)!
        let resolved = clone.resolved(parent: parent)
        #expect(resolved.name == "Updated Parent")
    }

    @Test("Undo reset restores override and original value")
    @MainActor
    func undoResetRestoresOverride() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        vm.updateContainerName(containerID: parentID, name: "Parent")

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        vm.updateContainerName(containerID: cloneID, name: "My Override")

        // Reset
        vm.resetContainerField(containerID: cloneID, field: .name)
        let afterReset = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(!afterReset.overriddenFields.contains(.name))
        #expect(afterReset.name == "Parent")

        // Undo
        vm.undoManager?.undo()
        let afterUndo = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(afterUndo.overriddenFields.contains(.name))
        #expect(afterUndo.name == "My Override")
    }

    @Test("Reset has no effect on non-overridden fields")
    @MainActor
    func resetNonOverriddenFieldIsNoOp() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Name is not overridden — reset should be a no-op
        let cloneBefore = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(!cloneBefore.overriddenFields.contains(.name))

        vm.resetContainerField(containerID: cloneID, field: .name)

        let cloneAfter = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(!cloneAfter.overriddenFields.contains(.name))
    }

    @Test("Reset effects field copies parent's effect chain")
    @MainActor
    func resetEffectsFieldCopiesParentEffects() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Add an effect to parent
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effect = InsertEffect(component: comp, displayName: "Reverb")
        vm.addContainerEffect(containerID: parentID, effect: effect)

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Override effects on clone by adding a different effect
        let cloneEffect = InsertEffect(component: comp, displayName: "Delay")
        vm.addContainerEffect(containerID: cloneID, effect: cloneEffect)
        let cloneBefore = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(cloneBefore.overriddenFields.contains(.effects))
        #expect(cloneBefore.insertEffects.count == 2) // Original + new

        // Reset effects
        vm.resetContainerField(containerID: cloneID, field: .effects)

        let cloneAfter = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(!cloneAfter.overriddenFields.contains(.effects))
        // Clone should now have parent's effects (just the one Reverb)
        let parent = vm.findContainer(id: parentID)!
        #expect(cloneAfter.insertEffects.count == parent.insertEffects.count)
        #expect(cloneAfter.insertEffects.first?.displayName == "Reverb")
    }

    @Test("Container.copyField copies each field type correctly")
    func copyFieldAllTypes() {
        let source = Container(
            name: "Source",
            startBar: 1,
            lengthBars: 4,
            loopSettings: LoopSettings(loopCount: .count(3)),
            insertEffects: [InsertEffect(component: AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1), displayName: "FX")],
            isEffectChainBypassed: true,
            enterFade: FadeSettings(duration: 2.0, curve: .exponential),
            exitFade: FadeSettings(duration: 3.0, curve: .linear),
            onEnterActions: [.makeSendMIDI(message: .programChange(channel: 0, program: 5), destination: .externalPort(name: "Port"))],
            onExitActions: [.makeSendMIDI(message: .programChange(channel: 0, program: 10), destination: .externalPort(name: "Port"))],
            midiSequence: MIDISequence(notes: [MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0, duration: 1.0)])
        )

        var target = Container(name: "Target", startBar: 5, lengthBars: 8)

        // Copy each field and verify
        target.copyField(from: source, field: .name)
        #expect(target.name == "Source")

        target.copyField(from: source, field: .effects)
        #expect(target.insertEffects.count == 1)
        #expect(target.isEffectChainBypassed == true)

        target.copyField(from: source, field: .fades)
        #expect(target.enterFade?.duration == 2.0)
        #expect(target.exitFade?.duration == 3.0)

        target.copyField(from: source, field: .enterActions)
        #expect(target.onEnterActions.count == 1)

        target.copyField(from: source, field: .exitActions)
        #expect(target.onExitActions.count == 1)

        target.copyField(from: source, field: .loopSettings)
        #expect(target.loopSettings.loopCount == .count(3))

        target.copyField(from: source, field: .midiSequence)
        #expect(target.midiSequence != nil)
        #expect(target.midiSequence?.notes.count == 1)

        // Position fields should NOT have been affected
        #expect(target.startBar == 5)
        #expect(target.lengthBars == 8)
    }

    // MARK: - Automation ContainerID Remapping

    @Test("copyField(.automation) remaps containerID from source to self")
    func copyFieldAutomationRemapsContainerID() {
        let sourceID = ID<Container>()
        let trackID = ID<Track>()
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: sourceID, effectIndex: 0, parameterAddress: 42),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 0.0),
                AutomationBreakpoint(position: 2, value: 1.0)
            ]
        )
        let source = Container(id: sourceID, name: "Source", startBar: 1, lengthBars: 4, automationLanes: [lane])

        var target = Container(name: "Target", startBar: 5, lengthBars: 4)
        target.copyField(from: source, field: .automation)

        #expect(target.automationLanes.count == 1)
        // containerID should be remapped to target's own ID
        #expect(target.automationLanes[0].targetPath.containerID == target.id)
        // Other path fields unchanged
        #expect(target.automationLanes[0].targetPath.trackID == trackID)
        #expect(target.automationLanes[0].targetPath.effectIndex == 0)
        #expect(target.automationLanes[0].targetPath.parameterAddress == 42)
        // Breakpoints preserved
        #expect(target.automationLanes[0].breakpoints.count == 2)
    }

    @Test("copyField(.automation) does not remap lanes targeting other containers")
    func copyFieldAutomationPreservesForeignContainerID() {
        let sourceID = ID<Container>()
        let otherContainerID = ID<Container>()
        let trackID = ID<Track>()
        // Lane that targets a different container (not the source)
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: otherContainerID, effectIndex: 1, parameterAddress: 99),
            breakpoints: [AutomationBreakpoint(position: 0, value: 0.5)]
        )
        let source = Container(id: sourceID, name: "Source", startBar: 1, lengthBars: 4, automationLanes: [lane])

        var target = Container(name: "Target", startBar: 5, lengthBars: 4)
        target.copyField(from: source, field: .automation)

        // Should NOT be remapped — it's targeting a different container
        #expect(target.automationLanes[0].targetPath.containerID == otherContainerID)
    }

    @Test("copyField(.automation) handles mix of own and foreign containerIDs")
    func copyFieldAutomationMixedContainerIDs() {
        let sourceID = ID<Container>()
        let otherID = ID<Container>()
        let trackID = ID<Track>()
        let ownLane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: sourceID, effectIndex: 0, parameterAddress: 1),
            breakpoints: [AutomationBreakpoint(position: 0, value: 0.0)]
        )
        let foreignLane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: otherID, effectIndex: 0, parameterAddress: 2),
            breakpoints: [AutomationBreakpoint(position: 0, value: 1.0)]
        )
        let trackLane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 3),
            breakpoints: [AutomationBreakpoint(position: 0, value: 0.5)]
        )
        let source = Container(
            id: sourceID, name: "Source", startBar: 1, lengthBars: 4,
            automationLanes: [ownLane, foreignLane, trackLane]
        )

        var target = Container(name: "Target", startBar: 5, lengthBars: 4)
        target.copyField(from: source, field: .automation)

        #expect(target.automationLanes.count == 3)
        // Own lane remapped
        #expect(target.automationLanes[0].targetPath.containerID == target.id)
        // Foreign lane preserved
        #expect(target.automationLanes[1].targetPath.containerID == otherID)
        // Track-level lane (nil containerID) preserved
        #expect(target.automationLanes[2].targetPath.containerID == nil)
    }

    @Test("resolved(parent:) remaps inherited automation containerID to clone")
    func resolvedRemapsAutomationContainerID() {
        let parentID = ID<Container>()
        let trackID = ID<Track>()
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: parentID, effectIndex: 0, parameterAddress: 42),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 0.0),
                AutomationBreakpoint(position: 4, value: 1.0)
            ]
        )
        let parent = Container(id: parentID, name: "Parent", startBar: 1, lengthBars: 4, automationLanes: [lane])

        let clone = Container(name: "Clone", startBar: 5, lengthBars: 4, parentContainerID: parentID)
        // Clone has no automation override, so resolved should inherit from parent
        #expect(!clone.overriddenFields.contains(.automation))

        let resolved = clone.resolved(parent: parent)
        #expect(resolved.automationLanes.count == 1)
        // containerID should be the clone's own ID, not the parent's
        #expect(resolved.automationLanes[0].targetPath.containerID == resolved.id)
        #expect(resolved.automationLanes[0].targetPath.containerID != parentID)
        // Breakpoints preserved
        #expect(resolved.automationLanes[0].breakpoints.count == 2)
        #expect(resolved.automationLanes[0].breakpoints[0].value == 0.0)
        #expect(resolved.automationLanes[0].breakpoints[1].value == 1.0)
    }

    @Test("resolved(parent:) does not remap automation when clone overrides")
    func resolvedPreservesOverriddenAutomation() {
        let parentID = ID<Container>()
        let trackID = ID<Track>()
        let parentLane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: parentID, effectIndex: 0, parameterAddress: 42),
            breakpoints: [AutomationBreakpoint(position: 0, value: 0.0)]
        )
        let parent = Container(id: parentID, name: "Parent", startBar: 1, lengthBars: 4, automationLanes: [parentLane])

        let cloneID = ID<Container>()
        let cloneLane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: cloneID, effectIndex: 0, parameterAddress: 99),
            breakpoints: [AutomationBreakpoint(position: 0, value: 0.7)]
        )
        let clone = Container(id: cloneID, name: "Clone", startBar: 5, lengthBars: 4, automationLanes: [cloneLane], parentContainerID: parentID, overriddenFields: [.automation])

        let resolved = clone.resolved(parent: parent)
        // Should use clone's own lanes, not parent's
        #expect(resolved.automationLanes.count == 1)
        #expect(resolved.automationLanes[0].targetPath.parameterAddress == 99)
        #expect(resolved.automationLanes[0].targetPath.containerID == cloneID)
    }

    @Test("resolved(using:) lookup remaps automation containerID end-to-end")
    @MainActor
    func resolvedUsingLookupRemapsAutomation() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Add automation to parent targeting its own containerID
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: parentID, effectIndex: 0, parameterAddress: 42),
            breakpoints: [AutomationBreakpoint(position: 0, value: 0.0), AutomationBreakpoint(position: 4, value: 1.0)]
        )
        vm.addAutomationLane(containerID: parentID, lane: lane)

        // Clone the parent
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Resolve the clone using the full lookup
        let allContainers = vm.project.songs[0].tracks[0].containers
        let clone = allContainers.first { $0.id == cloneID }!
        let resolved = clone.resolved { id in allContainers.first(where: { $0.id == id }) }

        // Inherited automation should target the clone, not the parent
        #expect(resolved.automationLanes.count == 1)
        #expect(resolved.automationLanes[0].targetPath.containerID == cloneID)
        #expect(resolved.automationLanes[0].targetPath.containerID != parentID)
    }

    // MARK: - Resolved Container Inspector Display

    @Test("Clone with no effect override shows parent's current effects via resolved()")
    @MainActor
    func resolvedCloneShowsParentEffects() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Clone before adding effects — clone gets empty effects at creation
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Now add effects to parent AFTER cloning
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: parentID, effect: InsertEffect(component: comp, displayName: "Reverb"))

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        let parent = vm.findContainer(id: parentID)!

        // Clone's raw effects are stale (empty, from before parent got the effect)
        #expect(clone.insertEffects.isEmpty)
        #expect(!clone.overriddenFields.contains(.effects))

        // Resolved clone's effects match parent's current state
        let resolved = clone.resolved(parent: parent)
        #expect(resolved.insertEffects.count == 1)
        #expect(resolved.insertEffects.first?.displayName == "Reverb")
    }

    @Test("Edit parent effects updates clone's resolved effects")
    @MainActor
    func editParentEffectsUpdatesCloneResolved() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Add an effect to parent after clone creation
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 1)
        vm.addContainerEffect(containerID: parentID, effect: InsertEffect(component: comp, displayName: "Delay"))

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        let parent = vm.findContainer(id: parentID)!

        // Parent now has one effect
        #expect(parent.insertEffects.count == 1)

        // Resolved clone picks up parent's new effect
        let resolved = clone.resolved(parent: parent)
        #expect(resolved.insertEffects.count == 1)
        #expect(resolved.insertEffects.first?.displayName == "Delay")
    }

    @Test("Override clone's effects shows clone's own values, not parent's")
    @MainActor
    func overrideCloneEffectsShowsOwnValues() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: parentID, effect: InsertEffect(component: comp, displayName: "Reverb"))

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Override effects on clone
        let cloneEffect = InsertEffect(component: comp, displayName: "Chorus")
        vm.addContainerEffect(containerID: cloneID, effect: cloneEffect)

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        let parent = vm.findContainer(id: parentID)!

        #expect(clone.overriddenFields.contains(.effects))
        let resolved = clone.resolved(parent: parent)
        // Resolved should use clone's own effects (overridden)
        #expect(resolved.insertEffects.contains { $0.displayName == "Chorus" })
    }

    @Test("Resolved container preserves clone identity for edit callbacks")
    @MainActor
    func resolvedContainerPreservesCloneID() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        let parent = vm.findContainer(id: parentID)!

        let resolved = clone.resolved(parent: parent)
        // Resolved container keeps clone's ID, parentContainerID, and overriddenFields
        #expect(resolved.id == cloneID)
        #expect(resolved.parentContainerID == parentID)
        #expect(resolved.isClone)

        // Editing via the resolved ID should create an override on the clone
        vm.updateContainerName(containerID: resolved.id, name: "Edited Clone")
        let updatedClone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(updatedClone.name == "Edited Clone")
        #expect(updatedClone.overriddenFields.contains(.name))

        // Parent should be unaffected
        let parentAfter = vm.findContainer(id: parentID)!
        #expect(parentAfter.name != "Edited Clone")
    }

    @Test("Editing inherited field in clone inspector creates override")
    @MainActor
    func editInheritedFieldCreatesOverride() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        vm.setContainerEnterFade(containerID: parentID, fade: FadeSettings(duration: 2.0, curve: .exponential))

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        let cloneBefore = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(!cloneBefore.overriddenFields.contains(.fades))

        // Edit the fade on the clone (inherited field) — should create override
        vm.setContainerEnterFade(containerID: cloneID, fade: FadeSettings(duration: 4.0, curve: .linear))

        let cloneAfter = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!
        #expect(cloneAfter.overriddenFields.contains(.fades))
        #expect(cloneAfter.enterFade?.duration == 4.0)

        // Parent unchanged
        let parent = vm.findContainer(id: parentID)!
        #expect(parent.enterFade?.duration == 2.0)
    }

    @Test("Resolved display matches what playback uses")
    @MainActor
    func resolvedDisplayMatchesPlayback() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Set up parent with various fields
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: parentID, effect: InsertEffect(component: comp, displayName: "Reverb"))
        vm.setContainerEnterFade(containerID: parentID, fade: FadeSettings(duration: 1.0, curve: .linear))
        vm.updateContainerName(containerID: parentID, name: "Parent Clip")

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Override only the name
        vm.updateContainerName(containerID: cloneID, name: "My Clone")

        let clone = vm.project.songs[0].tracks[0].containers.first { $0.id == cloneID }!

        // Using the same resolution that PlaybackScheduler uses
        let resolvedViaLookup = clone.resolved(using: { id in vm.findContainer(id: id) })
        let parent = vm.findContainer(id: parentID)!
        let resolvedViaDirect = clone.resolved(parent: parent)

        // Both resolution methods produce the same result
        #expect(resolvedViaLookup.name == resolvedViaDirect.name)
        #expect(resolvedViaLookup.insertEffects.count == resolvedViaDirect.insertEffects.count)
        #expect(resolvedViaLookup.enterFade?.duration == resolvedViaDirect.enterFade?.duration)

        // Name is overridden — shows clone's value
        #expect(resolvedViaLookup.name == "My Clone")
        // Effects are inherited — shows parent's value
        #expect(resolvedViaLookup.insertEffects.count == 1)
        #expect(resolvedViaLookup.insertEffects.first?.displayName == "Reverb")
        // Fades are inherited — shows parent's value
        #expect(resolvedViaLookup.enterFade?.duration == 1.0)
    }

    @Test("Non-clone container passed through unchanged")
    func nonCloneUnchanged() {
        let container = Container(name: "Regular", startBar: 1, lengthBars: 4)
        #expect(!container.isClone)

        // resolved(using:) returns self when not a clone
        let resolved = container.resolved(using: { _ in nil })
        #expect(resolved.name == "Regular")
        #expect(resolved.id == container.id)
    }
}
