import Foundation

struct TrainerSettings: Codable, Equatable, Sendable {
    var rampEnabled = false
    var rampStep: Double = 5
    var rampEveryBars = 4
    var rampTarget: Double = 160

    var gapEnabled = false
    var gapPlayBars = 3
    var gapMuteBars = 1
}

/// Everything that defines what the metronome plays. Saved in presets.
struct MetronomeSettings: Codable, Equatable, Sendable {
    var bpm: Double = 120
    var beatsPerBar = 4
    var beatUnit = 4
    var accents: [AccentLevel] = [.accent, .normal, .normal, .normal]
    var subdivision: Subdivision = .quarter
    var swing: Double = 0.66
    var sound: SoundKit = .click
    var subdivisionVolume: Double = 0.6
    var trainer = TrainerSettings()

    var timeSignature: TimeSignature { TimeSignature(beats: beatsPerBar, unit: beatUnit) }

    mutating func setTimeSignature(_ signature: TimeSignature) {
        beatsPerBar = signature.beats
        beatUnit = signature.unit
        accents = signature.defaultAccents
    }

    /// Changes the number of beats, keeping the accents already set.
    mutating func setBeats(_ count: Int) {
        let count = min(max(count, 1), 16)
        beatsPerBar = count
        if accents.count > count {
            accents.removeLast(accents.count - count)
        } else {
            accents.append(contentsOf: Array(repeating: .normal, count: count - accents.count))
        }
        if accents.count == 1 { accents[0] = .accent }
    }

    var schedulerConfig: SchedulerConfig {
        SchedulerConfig(
            bpm: bpm,
            accents: accents,
            pulseOffsets: subdivision.pulseOffsets(swing: swing),
            subdivisionGain: Float(subdivisionVolume),
            rampEnabled: trainer.rampEnabled,
            rampStep: trainer.rampStep,
            rampEveryBars: trainer.rampEveryBars,
            rampTarget: trainer.rampTarget,
            gapEnabled: trainer.gapEnabled,
            gapPlayBars: trainer.gapPlayBars,
            gapMuteBars: trainer.gapMuteBars
        )
    }

    var summary: String {
        "\(Int(bpm.rounded())) BPM · \(timeSignature.label) · \(subdivision.label) · \(sound.label)"
    }
}

struct Preset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var settings: MetronomeSettings
}

enum ThemeColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case amber, coral, rose, violet, sky, mint

    var id: String { rawValue }
}

/// App-wide preferences, not stored in presets.
struct AppPreferences: Codable, Equatable, Sendable {
    var theme: ThemeColor = .amber
    var masterVolume: Double = 0.9
    var flashOnDownbeat = false
    var haptics = true
    var showPulseDots = true
    var timerMinutes = 0
}

/// Averages the last few taps to estimate a tempo.
struct TapTempo {
    private(set) var taps: [TimeInterval] = []
    var maxTaps = 6
    var resetInterval: TimeInterval = 2

    /// Registers a tap and returns the estimated BPM once two taps are known.
    mutating func tap(at time: TimeInterval) -> Double? {
        if let last = taps.last, time - last > resetInterval || time <= last {
            taps.removeAll()
        }
        taps.append(time)
        if taps.count > maxTaps { taps.removeFirst(taps.count - maxTaps) }
        guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
        let interval = (last - first) / Double(taps.count - 1)
        guard interval > 0 else { return nil }
        return Tempo.clamp(60 / interval)
    }
}
