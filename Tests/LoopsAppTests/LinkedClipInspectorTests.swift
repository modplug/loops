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
}
