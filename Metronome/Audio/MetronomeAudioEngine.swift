import AVFoundation
import os

/// State exchanged between the main thread and the render thread.
/// The render thread only ever *tries* the lock, so it never blocks.
private struct SharedState {
    var pendingConfig: SchedulerConfig?
    var pendingSamples: ClickSamples?
    /// Old samples handed back so they are freed off the audio thread.
    var retiredSamples: ClickSamples?
    var resetRequested = false
    var running = false
    var events: [TickEvent] = []
    var bufferStartFrame: Int64 = 0
    var bufferHostTime: UInt64 = 0
}

private struct Voice {
    var kind = 0 // 0 accent, 1 normal, 2 subdivision
    var position = 0
    var gain: Float = 0
    var active = false
}

/// Sample-accurate click generator built on an `AVAudioSourceNode`.
final class MetronomeAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let shared = OSAllocatedUnfairLock(initialState: SharedState())
    private(set) var sampleRate: Double = 48_000

    // Render-thread state.
    private var scheduler: TickScheduler
    private var samples: ClickSamples
    private var running = false
    private var voices = [Voice](repeating: Voice(), count: 8)
    private var scratch: [TickEvent] = []
    private var outbox: [TickEvent] = []

    init(settings: MetronomeSettings) {
        Self.configureSession()
        let hwRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = hwRate > 0 ? hwRate : 48_000
        scheduler = TickScheduler(sampleRate: sampleRate, config: settings.schedulerConfig)
        samples = ClickSynth.make(settings.sound, sampleRate: sampleRate)
        scratch.reserveCapacity(128)
        outbox.reserveCapacity(256)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        source = AVAudioSourceNode(format: format) { [unowned self] _, timestamp, frameCount, bufferList in
            self.render(timestamp: timestamp, frameCount: Int(frameCount), bufferList: bufferList)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()

        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.shared.withLock({ $0.running }) else { return }
            try? self.engine.start()
        }
    }

    // MARK: - Main-thread API

    var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    func start() throws {
        Self.configureSession()
        shared.withLock {
            $0.resetRequested = true
            $0.running = true
            $0.events.removeAll()
            $0.bufferHostTime = 0
        }
        if !engine.isRunning { try engine.start() }
    }

    func stop() {
        shared.withLock { $0.running = false }
        engine.stop()
    }

    func update(_ config: SchedulerConfig) {
        shared.withLock { $0.pendingConfig = config }
    }

    func setSound(_ kit: SoundKit) {
        let newSamples = ClickSynth.make(kit, sampleRate: sampleRate)
        shared.withLock { $0.pendingSamples = newSamples }
    }

    /// Returns the ticks rendered since the last call, plus an estimate of the
    /// frame currently coming out of the speakers.
    func drain() -> (events: [TickEvent], audibleFrame: Int64?) {
        let (events, frame, host) = shared.withLock { state -> ([TickEvent], Int64, UInt64) in
            let events = state.events
            state.events.removeAll(keepingCapacity: true)
            state.retiredSamples = nil
            return (events, state.bufferStartFrame, state.bufferHostTime)
        }
        guard host != 0 else { return (events, nil) }
        let elapsed = AVAudioTime.seconds(forHostTime: mach_absolute_time()) - AVAudioTime.seconds(forHostTime: host)
        let latency = engine.outputNode.presentationLatency
        return (events, frame + Int64((elapsed - latency) * sampleRate))
    }

    private static func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
        #endif
    }

    // MARK: - Render thread

    private func render(timestamp: UnsafePointer<AudioTimeStamp>, frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let time = timestamp.pointee
        shared.withLockIfAvailable { state in
            if let config = state.pendingConfig {
                scheduler.config = config
                state.pendingConfig = nil
            }
            if let newSamples = state.pendingSamples {
                state.retiredSamples = samples
                samples = newSamples
                state.pendingSamples = nil
            }
            if state.resetRequested {
                scheduler.reset()
                for i in voices.indices { voices[i].active = false }
                outbox.removeAll(keepingCapacity: true)
                state.resetRequested = false
            }
            running = state.running
            if running, time.mFlags.contains(.hostTimeValid) {
                state.bufferStartFrame = scheduler.frame
                state.bufferHostTime = time.mHostTime
            }
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard running, let data = buffers.first?.mData else { return }
        let out = data.assumingMemoryBound(to: Float.self)

        let start = scheduler.frame
        scratch.removeAll(keepingCapacity: true)
        scheduler.advance(by: frameCount) { scratch.append($0) }

        var cursor = 0
        for event in scratch {
            let offset = Int(event.frame - start)
            mix(into: out, from: cursor, to: offset)
            trigger(event)
            cursor = offset
            if outbox.count < 256 { outbox.append(event) }
        }
        mix(into: out, from: cursor, to: frameCount)

        for i in 0..<frameCount { out[i] = min(max(out[i], -1), 1) }
        for buffer in buffers.dropFirst() {
            if let dest = buffer.mData { memcpy(dest, out, frameCount * MemoryLayout<Float>.size) }
        }

        if !outbox.isEmpty {
            shared.withLockIfAvailable { state in
                if state.events.count > 1_024 { state.events.removeFirst(state.events.count - 512) }
                state.events.append(contentsOf: outbox)
                outbox.removeAll(keepingCapacity: true)
            }
        }
    }

    private func trigger(_ event: TickEvent) {
        guard !event.isSilent else { return }
        let kind: Int
        let gain: Float
        if event.pulse == 0 {
            kind = event.level == .accent ? 0 : 1
            gain = event.level.gain
        } else {
            kind = 2
            gain = scheduler.config.subdivisionGain * 0.8
        }
        guard gain > 0 else { return }
        // Free voice, or steal the one that has played the longest.
        var slot = 0
        var oldest = -1
        for i in voices.indices {
            if !voices[i].active { slot = i; oldest = .max; break }
            if voices[i].position > oldest { oldest = voices[i].position; slot = i }
        }
        voices[slot] = Voice(kind: kind, position: 0, gain: gain, active: true)
    }

    private func mix(into out: UnsafeMutablePointer<Float>, from: Int, to: Int) {
        guard to > from else { return }
        for v in voices.indices where voices[v].active {
            let source: [Float]
            switch voices[v].kind {
            case 0: source = samples.accent
            case 1: source = samples.normal
            default: source = samples.sub
            }
            source.withUnsafeBufferPointer { samplesPtr in
                var position = voices[v].position
                let gain = voices[v].gain
                var i = from
                while i < to, position < samplesPtr.count {
                    out[i] += samplesPtr[position] * gain
                    i += 1
                    position += 1
                }
                voices[v].position = position
                if position >= samplesPtr.count { voices[v].active = false }
            }
        }
    }
}
