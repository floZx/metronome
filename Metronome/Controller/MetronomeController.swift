import AVFoundation
import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class MetronomeController {
    var settings: MetronomeSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.schedulerConfig != oldValue.schedulerConfig { engine.update(settings.schedulerConfig) }
            if settings.sound != oldValue.sound { engine.setSound(settings.sound) }
            if settings.bpm != oldValue.bpm { liveBPM = settings.bpm }
            store(settings, key: Keys.settings)
        }
    }

    var prefs: AppPreferences {
        didSet {
            guard prefs != oldValue else { return }
            engine.masterVolume = Float(prefs.masterVolume)
            store(prefs, key: Keys.prefs)
        }
    }

    private(set) var presets: [Preset] = [] {
        didSet { store(presets, key: Keys.presets) }
    }

    private(set) var activePresetID: UUID?

    // Playback state, updated in sync with what is heard.
    private(set) var isPlaying = false
    private(set) var currentBeat: Int?
    private(set) var currentPulse = 0
    private(set) var currentBar = 0
    private(set) var beatCount = 0
    private(set) var downbeatCount = 0
    private(set) var lastBeatLevel: AccentLevel = .normal
    private(set) var isSilentBar = false
    private(set) var liveBPM: Double
    private(set) var tapCount = 0
    private(set) var startDate: Date?

    @ObservationIgnored private let engine: MetronomeAudioEngine
    @ObservationIgnored private var tapTempo = TapTempo()
    @ObservationIgnored private var pending: [TickEvent] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let settings = "metronome.settings.v1"
        static let prefs = "metronome.prefs.v1"
        static let presets = "metronome.presets.v1"
    }

    init() {
        let loadedSettings = Self.load(MetronomeSettings.self, key: Keys.settings) ?? MetronomeSettings()
        let loadedPrefs = Self.load(AppPreferences.self, key: Keys.prefs) ?? AppPreferences()
        settings = loadedSettings
        prefs = loadedPrefs
        liveBPM = loadedSettings.bpm
        engine = MetronomeAudioEngine(settings: loadedSettings)
        engine.masterVolume = Float(loadedPrefs.masterVolume)
        presets = Self.load([Preset].self, key: Keys.presets) ?? []

        #if os(iOS)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated { self?.stop() }
        }
        #endif
    }

    // MARK: - Derived

    /// Tempo to display: follows the trainer while it ramps.
    var displayedBPM: Double {
        isPlaying && settings.trainer.rampEnabled ? liveBPM : settings.bpm
    }

    var activePreset: Preset? { presets.first { $0.id == activePresetID } }

    // MARK: - Transport

    func toggle() { isPlaying ? stop() : start() }

    func start() {
        guard !isPlaying else { return }
        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            return
        }
        pending.removeAll()
        liveBPM = settings.bpm
        currentBar = 0
        isSilentBar = false
        startDate = Date()
        isPlaying = true
        setIdleTimerDisabled(true)
        Haptics.prepare()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(6))
            }
        }
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
        pollTask?.cancel()
        pollTask = nil
        pending.removeAll()
        isPlaying = false
        currentBeat = nil
        currentPulse = 0
        isSilentBar = false
        startDate = nil
        liveBPM = settings.bpm
        setIdleTimerDisabled(false)
    }

    private func poll() {
        let (events, audibleFrame) = engine.drain()
        pending.append(contentsOf: events)
        if let audibleFrame {
            var consumed = 0
            while consumed < pending.count, pending[consumed].frame <= audibleFrame {
                apply(pending[consumed], isLatest: consumed + 1 == pending.count || pending[consumed + 1].frame > audibleFrame)
                consumed += 1
            }
            pending.removeFirst(consumed)
        }
        if prefs.timerMinutes > 0, let startDate, Date().timeIntervalSince(startDate) >= Double(prefs.timerMinutes) * 60 {
            stop()
        }
    }

    private func apply(_ event: TickEvent, isLatest: Bool) {
        // When catching up several ticks at once, only the last one drives visuals.
        guard isLatest else { return }
        currentBeat = event.beat
        currentPulse = event.pulse
        currentBar = event.bar
        isSilentBar = event.isSilent
        if liveBPM != event.bpm { liveBPM = event.bpm }
        guard event.pulse == 0 else { return }
        beatCount += 1
        lastBeatLevel = event.level
        if event.beat == 0 { downbeatCount += 1 }
        if prefs.haptics, !event.isSilent, event.level != .mute {
            Haptics.beat(strong: event.level == .accent)
        }
    }

    // MARK: - Tempo

    func setBPM(_ bpm: Double) {
        settings.bpm = Tempo.clamp(bpm.rounded())
    }

    func nudge(_ delta: Double) {
        setBPM(settings.bpm.rounded() + delta)
    }

    func tap() {
        tapCount += 1
        if let bpm = tapTempo.tap(at: ProcessInfo.processInfo.systemUptime) {
            setBPM(bpm)
        }
    }

    // MARK: - Rhythm

    func cycleAccent(at index: Int) {
        guard settings.accents.indices.contains(index) else { return }
        settings.accents[index] = settings.accents[index].next
        Haptics.selection()
    }

    func setBeats(_ count: Int) { settings.setBeats(count) }

    func setTimeSignature(_ signature: TimeSignature) { settings.setTimeSignature(signature) }

    func resetAccents() { settings.accents = settings.timeSignature.defaultAccents }

    // MARK: - Presets

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = Preset(name: trimmed.isEmpty ? "Préréglage \(presets.count + 1)" : trimmed, settings: settings)
        presets.append(preset)
        activePresetID = preset.id
    }

    func load(_ preset: Preset) {
        settings = preset.settings
        activePresetID = preset.id
    }

    func updatePreset(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].settings = settings
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        if activePresetID == preset.id { activePresetID = nil }
    }

    func movePresets(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    private func store<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

@MainActor
enum Haptics {
    #if os(iOS)
    private static let strong = UIImpactFeedbackGenerator(style: .heavy)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let select = UISelectionFeedbackGenerator()
    #endif

    static func prepare() {
        #if os(iOS)
        strong.prepare()
        light.prepare()
        #endif
    }

    static func beat(strong isStrong: Bool) {
        #if os(iOS)
        if isStrong { strong.impactOccurred() } else { light.impactOccurred(intensity: 0.7) }
        #endif
    }

    static func selection() {
        #if os(iOS)
        select.selectionChanged()
        #endif
    }
}
