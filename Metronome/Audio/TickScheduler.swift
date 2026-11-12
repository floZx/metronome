import Foundation

/// Parameters the audio thread needs to place clicks.
struct SchedulerConfig: Equatable, Sendable {
    var bpm: Double = 120
    var accents: [AccentLevel] = [.accent, .normal, .normal, .normal]
    var pulseOffsets: [Double] = [0]
    var subdivisionGain: Float = 0.6

    var rampEnabled = false
    var rampStep: Double = 5
    var rampEveryBars = 4
    var rampTarget: Double = 160

    var gapEnabled = false
    var gapPlayBars = 3
    var gapMuteBars = 1
}

/// One click (beat or subdivision pulse), positioned in absolute frames since start.
struct TickEvent: Equatable, Sendable {
    var frame: Int64
    var bar: Int
    var beat: Int
    var pulse: Int
    var level: AccentLevel
    var isSilent: Bool
    var bpm: Double
}

/// Pure, allocation-free sample-accurate clock. Owned by the audio render thread;
/// kept free of audio APIs so it can be unit-tested.
///
/// Tempo changes take effect at the next beat, so a beat's subdivisions are always even.
struct TickScheduler {
    let sampleRate: Double

    var config: SchedulerConfig {
        didSet {
            if config.bpm != oldValue.bpm || config.rampEnabled != oldValue.rampEnabled {
                effectiveBPM = Tempo.clamp(config.bpm)
            }
        }
    }

    private(set) var effectiveBPM: Double
    /// Number of frames processed so far.
    private(set) var frame: Int64 = 0

    private var nextTickFrame: Double = 0
    private var beatStart: Double = 0
    private var beatDuration: Double
    private var bar = 0
    private var beat = 0
    private var pulse = 0

    init(sampleRate: Double, config: SchedulerConfig = SchedulerConfig()) {
        self.sampleRate = sampleRate
        self.config = config
        self.effectiveBPM = Tempo.clamp(config.bpm)
        self.beatDuration = sampleRate * 60 / Tempo.clamp(config.bpm)
    }

    mutating func reset() {
        frame = 0
        nextTickFrame = 0
        beatStart = 0
        bar = 0
        beat = 0
        pulse = 0
        effectiveBPM = Tempo.clamp(config.bpm)
        beatDuration = sampleRate * 60 / effectiveBPM
    }

    /// Emits every tick falling in `[frame, frame + count)` then advances `frame`.
    mutating func advance(by count: Int, _ onTick: (TickEvent) -> Void) {
        let end = frame + Int64(count)
        while true {
            let tickFrame = max(Int64(nextTickFrame.rounded(.up)), frame)
            guard tickFrame < end else { break }
            if pulse == 0 {
                // A beat starts now: its length follows the tempo in force at this moment.
                beatDuration = sampleRate * 60 / effectiveBPM
            }
            onTick(makeEvent(at: tickFrame))
            step()
        }
        frame = end
    }

    private func makeEvent(at tickFrame: Int64) -> TickEvent {
        let accents = config.accents
        let level = accents.isEmpty ? .normal : accents[beat % accents.count]
        var silent = false
        if config.gapEnabled {
            let cycle = max(config.gapPlayBars, 1) + max(config.gapMuteBars, 0)
            silent = bar % cycle >= max(config.gapPlayBars, 1)
        }
        return TickEvent(frame: tickFrame, bar: bar, beat: beat, pulse: pulse,
                         level: level, isSilent: silent, bpm: effectiveBPM)
    }

    private mutating func step() {
        let offsets = config.pulseOffsets.isEmpty ? [0] : config.pulseOffsets
        pulse += 1
        if pulse >= offsets.count {
            pulse = 0
            beat += 1
            beatStart += beatDuration
            if beat >= max(config.accents.count, 1) {
                beat = 0
                bar += 1
                applyRamp()
            }
        }
        nextTickFrame = beatStart + offsets[pulse] * beatDuration
    }

    private mutating func applyRamp() {
        guard config.rampEnabled, config.rampEveryBars > 0, bar % config.rampEveryBars == 0 else { return }
        let step = abs(config.rampStep)
        let target = Tempo.clamp(config.rampTarget)
        if effectiveBPM < target {
            effectiveBPM = min(effectiveBPM + step, target)
        } else if effectiveBPM > target {
            effectiveBPM = max(effectiveBPM - step, target)
        }
    }
}
