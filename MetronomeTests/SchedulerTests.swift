import XCTest
@testable import Metronome

final class SchedulerTests: XCTestCase {
    private func ticks(_ config: SchedulerConfig, seconds: Double, chunk: Int = 512, sampleRate: Double = 48_000) -> [TickEvent] {
        var scheduler = TickScheduler(sampleRate: sampleRate, config: config)
        var events: [TickEvent] = []
        var remaining = Int(seconds * sampleRate)
        while remaining > 0 {
            let n = min(chunk, remaining)
            scheduler.advance(by: n) { events.append($0) }
            remaining -= n
        }
        return events
    }

    func testQuartersAt120() {
        let events = ticks(SchedulerConfig(bpm: 120), seconds: 2.1)
        XCTAssertEqual(events.map(\.frame), [0, 24_000, 48_000, 72_000, 96_000])
        XCTAssertEqual(events.map(\.beat), [0, 1, 2, 3, 0])
        XCTAssertEqual(events.map(\.bar), [0, 0, 0, 0, 1])
        XCTAssertEqual(events.first?.level, .accent)
    }

    func testTriplets() {
        var config = SchedulerConfig(bpm: 120)
        config.pulseOffsets = Subdivision.triplets.pulseOffsets(swing: 0.66)
        let events = ticks(config, seconds: 0.6)
        XCTAssertEqual(events.map(\.frame), [0, 8_000, 16_000, 24_000])
        XCTAssertEqual(events.map(\.pulse), [0, 1, 2, 0])
    }

    func testSwing() {
        var config = SchedulerConfig(bpm: 60)
        config.pulseOffsets = Subdivision.swing.pulseOffsets(swing: 0.75)
        let events = ticks(config, seconds: 1.1)
        XCTAssertEqual(events.map(\.frame), [0, 36_000, 48_000])
    }

    func testChunkSizeDoesNotChangeTiming() {
        var config = SchedulerConfig(bpm: 137)
        config.pulseOffsets = Subdivision.quintuplets.pulseOffsets(swing: 0.66)
        XCTAssertEqual(ticks(config, seconds: 5, chunk: 1), ticks(config, seconds: 5, chunk: 4_096))
    }

    func testTempoRamp() {
        var config = SchedulerConfig(bpm: 120)
        config.rampEnabled = true
        config.rampStep = 10
        config.rampEveryBars = 1
        config.rampTarget = 140
        let downbeats = ticks(config, seconds: 10).filter { $0.beat == 0 }
        XCTAssertEqual(Array(downbeats.prefix(4).map(\.bpm)), [120, 130, 140, 140])
        // Bar 1 at 120 BPM is 2 s long, bar 2 at 130 BPM is 4 * 60/130 s long.
        XCTAssertEqual(downbeats[1].frame, 96_000)
        XCTAssertEqual(downbeats[2].frame, 96_000 + Int64((4 * 60.0 / 130 * 48_000).rounded(.up)))
    }

    func testGapTrainer() {
        var config = SchedulerConfig(bpm: 240)
        config.gapEnabled = true
        config.gapPlayBars = 1
        config.gapMuteBars = 1
        let downbeats = ticks(config, seconds: 3.1).filter { $0.beat == 0 }
        XCTAssertEqual(downbeats.map(\.isSilent), [false, true, false, true])
    }

    func testTempoChangeAppliesAtNextBeat() {
        var scheduler = TickScheduler(sampleRate: 1_000, config: SchedulerConfig(bpm: 60))
        var events: [TickEvent] = []
        scheduler.advance(by: 500) { events.append($0) }
        scheduler.config.bpm = 120
        scheduler.advance(by: 2_000) { events.append($0) }
        XCTAssertEqual(events.map(\.frame), [0, 1_000, 1_500, 2_000])
    }
}

final class ModelTests: XCTestCase {
    func testTapTempo() {
        var tap = TapTempo()
        XCTAssertNil(tap.tap(at: 10))
        XCTAssertEqual(tap.tap(at: 10.5)!, 120, accuracy: 0.001)
        XCTAssertEqual(tap.tap(at: 11.0)!, 120, accuracy: 0.001)
        // Long pause restarts the measurement.
        XCTAssertNil(tap.tap(at: 20))
        XCTAssertEqual(tap.tap(at: 21)!, 60, accuracy: 0.001)
    }

    func testSetBeatsKeepsAccents() {
        var settings = MetronomeSettings()
        settings.accents[2] = .mute
        settings.setBeats(6)
        XCTAssertEqual(settings.accents, [.accent, .normal, .mute, .normal, .normal, .normal])
        settings.setBeats(3)
        XCTAssertEqual(settings.accents, [.accent, .normal, .mute])
    }

    func testCompoundMeterDefaults() {
        XCTAssertEqual(TimeSignature(beats: 6, unit: 8).defaultAccents, [.accent, .soft, .soft, .normal, .soft, .soft])
        XCTAssertEqual(TimeSignature(beats: 7, unit: 8).defaultAccents, [.accent, .soft, .normal, .soft, .normal, .soft, .soft])
        XCTAssertEqual(TimeSignature(beats: 3, unit: 4).defaultAccents, [.accent, .normal, .normal])
    }

    func testTempoMarking() {
        XCTAssertEqual(Tempo.marking(for: 120), "Allegro")
        XCTAssertEqual(Tempo.marking(for: 60), "Larghetto")
        XCTAssertEqual(Tempo.clamp(1_000), 400)
    }
}
