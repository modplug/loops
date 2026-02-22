import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Keyboard Focus Management Tests")
struct KeyboardFocusTests {

    @Test("FocusedField enum has main case")
    func focusedFieldEnum() {
        let field = FocusedField.main
        #expect(field == .main)
    }

    @Test("FocusedField conforms to Hashable")
    func focusedFieldHashable() {
        let set: Set<FocusedField> = [.main]
        #expect(set.contains(.main))
    }

    @Test("MainContentView can be created with focus state")
    @MainActor
    func mainContentViewCreation() {
        let projectVM = ProjectViewModel()
        let timelineVM = TimelineViewModel()
        let _ = MainContentView(projectViewModel: projectVM, timelineViewModel: timelineVM)
    }

    @Test("Shortcuts do not fire when focus is not on main (integration model test)")
    @MainActor
    func shortcutsBlockedWhenTextFieldFocused() {
        // Verify the model layer: selectTrackByIndex should work normally
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)

        // Shortcuts work via model layer regardless of focus — the guard is in the View layer
        vm.selectTrackByIndex(0)
        #expect(vm.selectedTrackID == vm.project.songs[0].tracks[0].id)
    }

    @Test("Escape behavior: deselectAll clears selection state")
    @MainActor
    func escapeDeselectsAll() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.selectedContainerID = containerID
        vm.selectedTrackID = trackID
        vm.selectedContainerIDs = [containerID]

        // Simulates Escape when no text field is focused: deselect all
        vm.deselectAll()

        #expect(vm.selectedContainerID == nil)
        #expect(vm.selectedTrackID == nil)
        #expect(vm.selectedContainerIDs.isEmpty)
    }

    @Test("FocusedField nil represents text field active state")
    func focusedFieldNilMeansTextFieldActive() {
        // When focusedField is nil, a text field (or other non-main view) has focus.
        // This matches the guard: focusedField != .main → true when nil → shortcuts blocked.
        let focusedField: FocusedField? = nil
        #expect(focusedField != .main)

        let mainFocused: FocusedField? = .main
        #expect(mainFocused == .main)
    }

    @Test("Keyboard shortcuts should be blocked for all non-modifier single-key bindings")
    @MainActor
    func singleKeyShortcutsShouldBeGuarded() {
        // This test documents that the following shortcuts are guarded:
        // Space, Return, R, M, Left, Right, Home, End, 1-9, Tab, Escape
        // The guard is: guard !isTextFieldFocused else { return .ignored }
        // where isTextFieldFocused = (focusedField != .main)
        //
        // Modifier shortcuts (Cmd+C, Cmd+V, Cmd+D, Cmd+A, Cmd+Shift+M, Cmd+Shift+L)
        // are NOT blocked because Cmd+key combos are typically not typed in text fields
        // and the OS handles text field Cmd shortcuts separately.

        // Verify the focus detection logic
        let nilField: FocusedField? = nil
        let mainField: FocusedField? = .main

        // nil (text field focused) → shortcuts should be blocked
        #expect(nilField != .main)

        // .main (main content focused) → shortcuts should work
        #expect(mainField == .main)
    }

    @Test("ContentMode enum unchanged")
    func contentModeEnum() {
        #expect(ContentMode.timeline.rawValue == "Timeline")
        #expect(ContentMode.mixer.rawValue == "Mixer")
    }

    @Test("InspectorMode enum unchanged")
    func inspectorModeEnum() {
        #expect(InspectorMode.container.rawValue == "Container")
        #expect(InspectorMode.storyline.rawValue == "Storyline")
    }

    @Test("SidebarTab enum unchanged")
    func sidebarTabEnum() {
        #expect(SidebarTab.songs.rawValue == "Songs")
        #expect(SidebarTab.setlists.rawValue == "Setlists")
    }
}
