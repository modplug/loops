import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("MetronomeGenerator Tests")
struct MetronomeGeneratorTests {

    @Test("Default volume is 0.8")
    func defaultVolume() {
        let met = MetronomeGenerator(sampleRate: 44100.0)
        #expect(met.volume == 0.8)
    }

    @Test("setVolume clamps to 0.0–1.0")
    func setVolumeClamping() {
        let met = MetronomeGenerator(sampleRate: 44100.0)

        met.setVolume(0.5)
        #expect(met.volume == 0.5)

        met.setVolume(1.5)
        #expect(met.volume == 1.0)

        met.setVolume(-0.3)
        #expect(met.volume == 0.0)

        met.setVolume(0.0)
        #expect(met.volume == 0.0)

        met.setVolume(1.0)
        #expect(met.volume == 1.0)
    }

    @Test("setEnabled toggles sourceNode volume")
    func setEnabledToggle() {
        let met = MetronomeGenerator(sampleRate: 44100.0)
        // Starts silent
        #expect(met.sourceNode.volume == 0.0)

        met.setEnabled(true)
        #expect(met.sourceNode.volume == 1.0)

        met.setEnabled(false)
        #expect(met.sourceNode.volume == 0.0)
    }

    @Test("setSubdivision does not crash for all cases")
    func setSubdivisionAllCases() {
        let met = MetronomeGenerator(sampleRate: 44100.0)
        for sub in MetronomeSubdivision.allCases {
            met.setSubdivision(sub)
        }
    }

    @Test("reset resets sample counter")
    func resetSampleCounter() {
        let met = MetronomeGenerator(sampleRate: 44100.0)
        // Just verify it doesn't crash
        met.reset()
    }

    @Test("update parameters does not crash")
    func updateParameters() {
        let met = MetronomeGenerator(sampleRate: 44100.0)
        met.update(bpm: 140.0, beatsPerBar: 3, sampleRate: 48000.0)
        met.update(bpm: 60.0, beatsPerBar: 7, sampleRate: 44100.0)
    }

    @Test("clicksPerBar static helper: quarter in 4/4")
    func clicksPerBarQuarter44() {
        let clicks = MetronomeGenerator.clicksPerBar(subdivision: .quarter, beatsPerBar: 4)
        #expect(clicks == 4.0)
    }

    @Test("clicksPerBar static helper: eighth in 4/4")
    func clicksPerBarEighth44() {
        let clicks = MetronomeGenerator.clicksPerBar(subdivision: .eighth, beatsPerBar: 4)
        #expect(clicks == 8.0)
    }

    @Test("clicksPerBar static helper: sixteenth in 4/4")
    func clicksPerBarSixteenth44() {
        let clicks = MetronomeGenerator.clicksPerBar(subdivision: .sixteenth, beatsPerBar: 4)
        #expect(clicks == 16.0)
    }

    @Test("clicksPerBar static helper: triplet in 4/4")
    func clicksPerBarTriplet44() {
        let clicks = MetronomeGenerator.clicksPerBar(subdivision: .triplet, beatsPerBar: 4)
        #expect(clicks == 12.0)
    }

    @Test("clicksPerBar static helper: dottedQuarter in 4/4")
    func clicksPerBarDottedQuarter44() {
        let clicks = MetronomeGenerator.clicksPerBar(subdivision: .dottedQuarter, beatsPerBar: 4)
        #expect(abs(clicks - 8.0 / 3.0) < 1e-10)
    }

    @Test("clicksPerBar static helper: eighth in 3/4")
    func clicksPerBarEighth34() {
        let clicks = MetronomeGenerator.clicksPerBar(subdivision: .eighth, beatsPerBar: 3)
        #expect(clicks == 6.0)
    }

    @Test("clicksPerBar static helper: triplet in 6/8")
    func clicksPerBarTriplet68() {
        let clicks = MetronomeGenerator.clicksPerBar(subdivision: .triplet, beatsPerBar: 6)
        #expect(clicks == 18.0)
    }
}
