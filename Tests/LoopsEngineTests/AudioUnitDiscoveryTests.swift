import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("AudioUnitDiscovery Tests")
struct AudioUnitDiscoveryTests {

    // MARK: - AudioUnitParameterInfo

    @Test("AudioUnitParameterInfo stores all fields correctly")
    func parameterInfoFields() {
        let info = AudioUnitParameterInfo(
            address: 42,
            displayName: "Decay Time",
            minValue: 0.0,
            maxValue: 10.0,
            defaultValue: 2.5,
            unit: "seconds"
        )
        #expect(info.address == 42)
        #expect(info.displayName == "Decay Time")
        #expect(info.minValue == 0.0)
        #expect(info.maxValue == 10.0)
        #expect(info.defaultValue == 2.5)
        #expect(info.unit == "seconds")
    }

    @Test("AudioUnitParameterInfo id is based on address")
    func parameterInfoID() {
        let info = AudioUnitParameterInfo(
            address: 123,
            displayName: "Volume",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            unit: ""
        )
        #expect(info.id == "123")
    }

    @Test("AudioUnitParameterInfo with same address has same id")
    func parameterInfoSameAddress() {
        let a = AudioUnitParameterInfo(address: 7, displayName: "A", minValue: 0, maxValue: 1, defaultValue: 0, unit: "")
        let b = AudioUnitParameterInfo(address: 7, displayName: "B", minValue: 0, maxValue: 100, defaultValue: 50, unit: "Hz")
        #expect(a.id == b.id)
    }

    @Test("AudioUnitParameterInfo with different address has different id")
    func parameterInfoDifferentAddress() {
        let a = AudioUnitParameterInfo(address: 1, displayName: "A", minValue: 0, maxValue: 1, defaultValue: 0, unit: "")
        let b = AudioUnitParameterInfo(address: 2, displayName: "A", minValue: 0, maxValue: 1, defaultValue: 0, unit: "")
        #expect(a.id != b.id)
    }

    // MARK: - AudioUnitInfo

    @Test("AudioUnitInfo id combines component fields")
    func audioUnitInfoID() {
        let comp = AudioComponentInfo(componentType: 100, componentSubType: 200, componentManufacturer: 300)
        let info = AudioUnitInfo(name: "Test AU", manufacturerName: "TestCo", componentInfo: comp, componentType: 100)
        #expect(info.id == "100-200-300")
        #expect(info.name == "Test AU")
        #expect(info.manufacturerName == "TestCo")
    }

    // MARK: - Discovery (basic availability)

    @Test("AudioUnitDiscovery can be created")
    func discoveryInit() {
        let discovery = AudioUnitDiscovery()
        // Effects returns an array (may be empty on CI)
        let effects = discovery.effects()
        #expect(effects is [AudioUnitInfo])
    }

    @Test("AudioUnitDiscovery effects returns sorted results")
    func discoveryEffectsSorted() {
        let discovery = AudioUnitDiscovery()
        let effects = discovery.effects()
        guard effects.count >= 2 else { return }
        for i in 0..<(effects.count - 1) {
            #expect(effects[i].name <= effects[i + 1].name)
        }
    }
}
