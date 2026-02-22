import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("ParameterPicker Tests")
struct ParameterPickerTests {

    @Test("PendingEffectSelection stores all fields")
    func pendingEffectSelectionFields() {
        let trackID = ID<Track>()
        let containerID = ID<Container>()
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)

        let pending = PendingEffectSelection(
            trackID: trackID,
            containerID: containerID,
            effectIndex: 2,
            component: comp,
            effectName: "Reverb"
        )

        #expect(pending.trackID == trackID)
        #expect(pending.containerID == containerID)
        #expect(pending.effectIndex == 2)
        #expect(pending.component == comp)
        #expect(pending.effectName == "Reverb")
    }

    @Test("PendingEffectSelection id includes container ID")
    func pendingEffectSelectionIDWithContainer() {
        let trackID = ID<Track>()
        let containerID = ID<Container>()
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)

        let pending = PendingEffectSelection(
            trackID: trackID,
            containerID: containerID,
            effectIndex: 0,
            component: comp,
            effectName: "Delay"
        )

        #expect(pending.id.contains(trackID.rawValue.uuidString))
        #expect(pending.id.contains(containerID.rawValue.uuidString))
        #expect(pending.id.contains("0"))
    }

    @Test("PendingEffectSelection id uses 'track' for nil container")
    func pendingEffectSelectionIDNilContainer() {
        let trackID = ID<Track>()
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)

        let pending = PendingEffectSelection(
            trackID: trackID,
            containerID: nil,
            effectIndex: 1,
            component: comp,
            effectName: "EQ"
        )

        #expect(pending.id.contains("track"))
        #expect(pending.id.contains("1"))
    }

    @Test("PendingEffectSelection equality")
    func pendingEffectSelectionEquality() {
        let trackID = ID<Track>()
        let containerID = ID<Container>()
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)

        let a = PendingEffectSelection(trackID: trackID, containerID: containerID, effectIndex: 0, component: comp, effectName: "FX")
        let b = PendingEffectSelection(trackID: trackID, containerID: containerID, effectIndex: 0, component: comp, effectName: "FX")
        #expect(a == b)
    }

    @Test("PendingEffectSelection inequality with different effect index")
    func pendingEffectSelectionInequality() {
        let trackID = ID<Track>()
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)

        let a = PendingEffectSelection(trackID: trackID, containerID: nil, effectIndex: 0, component: comp, effectName: "FX")
        let b = PendingEffectSelection(trackID: trackID, containerID: nil, effectIndex: 1, component: comp, effectName: "FX")
        #expect(a != b)
    }
}
