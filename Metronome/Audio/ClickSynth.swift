import Foundation

/// Pre-rendered mono samples for one sound kit.
final class ClickSamples: @unchecked Sendable {
    let accent: [Float]
    let normal: [Float]
    let sub: [Float]

    init(accent: [Float], normal: [Float], sub: [Float]) {
        self.accent = accent
        self.normal = normal
        self.sub = sub
    }
}

/// Synthesises every sound in code, so the app ships with no audio files.
enum ClickSynth {
    static func make(_ kit: SoundKit, sampleRate sr: Double) -> ClickSamples {
        switch kit {
        case .click:
            ClickSamples(accent: click(sr, freq: 2400, decay: 110),
                         normal: click(sr, freq: 1600, decay: 120),
                         sub: click(sr, freq: 1150, decay: 170))
        case .woodblock:
            ClickSamples(accent: woodblock(sr, freq: 1080),
                         normal: woodblock(sr, freq: 860),
                         sub: woodblock(sr, freq: 700, decay: 85))
        case .clave:
            ClickSamples(accent: clave(sr, freq: 2650),
                         normal: clave(sr, freq: 2200),
                         sub: clave(sr, freq: 1850, decay: 70))
        case .beep:
            ClickSamples(accent: beep(sr, freq: 1568),
                         normal: beep(sr, freq: 1047),
                         sub: beep(sr, freq: 784, length: 0.03))
        case .cowbell:
            ClickSamples(accent: cowbell(sr, f1: 900, f2: 605, decay: 14),
                         normal: cowbell(sr, f1: 800, f2: 540, decay: 18),
                         sub: cowbell(sr, f1: 800, f2: 540, decay: 45))
        case .hihat:
            ClickSamples(accent: hat(sr, length: 0.32, decay: 11),
                         normal: hat(sr, length: 0.1, decay: 42),
                         sub: hat(sr, length: 0.07, decay: 70))
        case .drums:
            ClickSamples(accent: kick(sr),
                         normal: snare(sr),
                         sub: hat(sr, length: 0.07, decay: 60))
        }
    }

    // MARK: - Voices

    private static func click(_ sr: Double, freq: Double, decay: Double) -> [Float] {
        render(sr, length: 0.06) { t, noise in
            sin(2 * .pi * freq * t) * exp(-t * decay) + 0.3 * noise.next() * exp(-t * 900)
        }
    }

    private static func woodblock(_ sr: Double, freq: Double, decay: Double = 55) -> [Float] {
        render(sr, length: 0.11) { t, noise in
            let bend = 1 + 0.04 * exp(-t * 80)
            return sin(2 * .pi * freq * bend * t) * exp(-t * decay)
                + 0.45 * sin(2 * .pi * freq * 2.76 * t) * exp(-t * decay * 2)
                + 0.15 * noise.next() * exp(-t * 1500)
        }
    }

    private static func clave(_ sr: Double, freq: Double, decay: Double = 42) -> [Float] {
        render(sr, length: 0.12) { t, _ in
            sin(2 * .pi * freq * t) * exp(-t * decay) + 0.2 * sin(2 * .pi * freq * 1.52 * t) * exp(-t * decay * 3)
        }
    }

    private static func beep(_ sr: Double, freq: Double, length: Double = 0.05) -> [Float] {
        render(sr, length: length + 0.03) { t, _ in
            let attack = min(t / 0.002, 1)
            let release = t < length ? 1 : exp(-(t - length) * 180)
            return sin(2 * .pi * freq * t) * attack * release
        }
    }

    private static func cowbell(_ sr: Double, f1: Double, f2: Double, decay: Double) -> [Float] {
        render(sr, length: 0.3) { t, _ in
            func square(_ f: Double) -> Double {
                let x = 2 * .pi * f * t
                return sin(x) + sin(3 * x) / 3 + sin(5 * x) / 5
            }
            return (square(f1) + square(f2)) * (0.65 * exp(-t * decay) + 0.35 * exp(-t * decay * 6))
        }
    }

    private static func hat(_ sr: Double, length: Double, decay: Double) -> [Float] {
        var p1 = 0.0, p2 = 0.0
        return render(sr, length: length) { t, noise in
            // Two first-order differences: crude but bright high-pass.
            let x = noise.next()
            let y = x - p1
            p1 = x
            let z = y - p2
            p2 = y
            return z * exp(-t * decay)
        }
    }

    private static func kick(_ sr: Double) -> [Float] {
        var phase = 0.0
        return render(sr, length: 0.35) { t, noise in
            let freq = 48 + 110 * exp(-t * 28)
            phase += 2 * .pi * freq / sr
            return sin(phase) * exp(-t * 8) + 0.25 * noise.next() * exp(-t * 700)
        }
    }

    private static func snare(_ sr: Double) -> [Float] {
        render(sr, length: 0.2) { t, noise in
            0.75 * noise.next() * exp(-t * 24) + 0.6 * sin(2 * .pi * 190 * t) * exp(-t * 22)
        }
    }

    // MARK: - Helpers

    struct Noise {
        private var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    private static func render(_ sr: Double, length: Double, _ generator: (Double, inout Noise) -> Double) -> [Float] {
        let count = max(Int(length * sr), 1)
        var out = [Float](repeating: 0, count: count)
        var noise = Noise()
        for i in 0..<count {
            out[i] = Float(generator(Double(i) / sr, &noise))
        }
        // Short fade-out so truncated tails never click.
        let fade = min(Int(0.003 * sr), count)
        for i in 0..<fade {
            out[count - 1 - i] *= Float(i) / Float(fade)
        }
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 0 {
            let scale = 0.9 / peak
            for i in 0..<count { out[i] *= scale }
        }
        return out
    }
}
