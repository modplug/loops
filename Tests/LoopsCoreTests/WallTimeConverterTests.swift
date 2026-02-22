import Testing
import Foundation
@testable import LoopsCore

@Suite("WallTimeConverter Tests")
struct WallTimeConverterTests {

    // MARK: - seconds(forBar:bpm:beatsPerBar:)

    @Test("Bar 1.0 at any tempo is 0 seconds")
    func barOneIsZero() {
        let result = WallTimeConverter.seconds(forBar: 1.0, bpm: 120.0, beatsPerBar: 4)
        #expect(result == 0.0)
    }

    @Test("120 BPM, 4/4: bar 2.0 is 2 seconds")
    func bar2At120BPM4_4() {
        // 4 beats at 120 BPM = 4 × 0.5s = 2.0s per bar
        let result = WallTimeConverter.seconds(forBar: 2.0, bpm: 120.0, beatsPerBar: 4)
        #expect(abs(result - 2.0) < 0.001)
    }

    @Test("120 BPM, 4/4: bar 5.0 is 8 seconds")
    func bar5At120BPM4_4() {
        // 4 bars × 2.0s = 8.0s
        let result = WallTimeConverter.seconds(forBar: 5.0, bpm: 120.0, beatsPerBar: 4)
        #expect(abs(result - 8.0) < 0.001)
    }

    @Test("60 BPM, 4/4: bar 2.0 is 4 seconds")
    func bar2At60BPM4_4() {
        // 4 beats at 60 BPM = 4 × 1.0s = 4.0s per bar
        let result = WallTimeConverter.seconds(forBar: 2.0, bpm: 60.0, beatsPerBar: 4)
        #expect(abs(result - 4.0) < 0.001)
    }

    @Test("90 BPM, 4/4: conversion is correct")
    func at90BPM4_4() {
        // 4 beats at 90 BPM = 4 × (60/90) = 2.667s per bar
        // Bar 3.0 = 2 bars × 2.667 = 5.333s
        let result = WallTimeConverter.seconds(forBar: 3.0, bpm: 90.0, beatsPerBar: 4)
        let expected = 2.0 * (4.0 * 60.0 / 90.0)
        #expect(abs(result - expected) < 0.001)
    }

    @Test("140 BPM, 4/4: conversion is correct")
    func at140BPM4_4() {
        // 4 beats at 140 BPM = 4 × (60/140) = 1.714s per bar
        // Bar 4.0 = 3 bars × 1.714 = 5.143s
        let result = WallTimeConverter.seconds(forBar: 4.0, bpm: 140.0, beatsPerBar: 4)
        let expected = 3.0 * (4.0 * 60.0 / 140.0)
        #expect(abs(result - expected) < 0.001)
    }

    @Test("3/4 time signature: bar duration is shorter")
    func threeQuarterTime() {
        // 3 beats at 120 BPM = 3 × 0.5s = 1.5s per bar
        // Bar 3.0 = 2 bars × 1.5 = 3.0s
        let result = WallTimeConverter.seconds(forBar: 3.0, bpm: 120.0, beatsPerBar: 3)
        #expect(abs(result - 3.0) < 0.001)
    }

    @Test("6/8 time signature: 6 beats per bar")
    func sixEighthTime() {
        // 6 beats at 120 BPM = 6 × 0.5s = 3.0s per bar
        // Bar 2.0 = 1 bar × 3.0 = 3.0s
        let result = WallTimeConverter.seconds(forBar: 2.0, bpm: 120.0, beatsPerBar: 6)
        #expect(abs(result - 3.0) < 0.001)
    }

    @Test("Fractional bar position")
    func fractionalBar() {
        // 120 BPM, 4/4: bar duration = 2.0s
        // Bar 1.5 = 0.5 bars × 2.0s = 1.0s
        let result = WallTimeConverter.seconds(forBar: 1.5, bpm: 120.0, beatsPerBar: 4)
        #expect(abs(result - 1.0) < 0.001)
    }

    @Test("Bar below 1.0 clamps to 0 seconds")
    func barBelowOneClamps() {
        let result = WallTimeConverter.seconds(forBar: 0.5, bpm: 120.0, beatsPerBar: 4)
        #expect(result == 0.0)
    }

    // MARK: - formatted(_:)

    @Test("Formatted zero seconds")
    func formattedZero() {
        #expect(WallTimeConverter.formatted(0.0) == "00:00.00")
    }

    @Test("Formatted 65.5 seconds")
    func formatted65Point5() {
        #expect(WallTimeConverter.formatted(65.5) == "01:05.50")
    }

    @Test("Formatted large value")
    func formattedLargeValue() {
        // 10 minutes, 30 seconds, 0.25
        let seconds = 10.0 * 60.0 + 30.0 + 0.25
        #expect(WallTimeConverter.formatted(seconds) == "10:30.25")
    }

    @Test("Formatted negative clamps to zero")
    func formattedNegativeClamps() {
        #expect(WallTimeConverter.formatted(-5.0) == "00:00.00")
    }

    // MARK: - formattedTime(forBar:bpm:beatsPerBar:)

    @Test("Formatted time at bar 1 is 00:00.00")
    func formattedTimeBarOne() {
        let result = WallTimeConverter.formattedTime(forBar: 1.0, bpm: 120.0, beatsPerBar: 4)
        #expect(result == "00:00.00")
    }

    @Test("Formatted time at bar 2, 120 BPM, 4/4 is 00:02.00")
    func formattedTimeBar2() {
        let result = WallTimeConverter.formattedTime(forBar: 2.0, bpm: 120.0, beatsPerBar: 4)
        #expect(result == "00:02.00")
    }
}
