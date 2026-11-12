import Foundation

/// Accent level of a single beat in the bar.
enum AccentLevel: Int, Codable, CaseIterable, Sendable {
    case mute = 0, soft, normal, accent

    /// Order used when the user taps a beat: accent → normal → soft → mute → accent.
    var next: AccentLevel {
        switch self {
        case .accent: .normal
        case .normal: .soft
        case .soft: .mute
        case .mute: .accent
        }
    }

    var gain: Float {
        switch self {
        case .mute: 0
        case .soft: 0.38
        case .normal: 0.72
        case .accent: 1
        }
    }

    var heightFraction: CGFloat {
        switch self {
        case .mute: 0.14
        case .soft: 0.4
        case .normal: 0.68
        case .accent: 1
        }
    }

    var label: String {
        switch self {
        case .mute: "Muet"
        case .soft: "Faible"
        case .normal: "Normal"
        case .accent: "Accent"
        }
    }
}

/// How each beat is divided.
enum Subdivision: String, Codable, CaseIterable, Identifiable, Sendable {
    case quarter, eighths, triplets, sixteenths, swing, gallop, reverseGallop, quintuplets, sextuplets

    var id: String { rawValue }

    /// Position of each pulse inside the beat, as a fraction of the beat (first is always 0).
    func pulseOffsets(swing: Double) -> [Double] {
        switch self {
        case .quarter: [0]
        case .eighths: [0, 0.5]
        case .triplets: [0, 1.0 / 3, 2.0 / 3]
        case .sixteenths: [0, 0.25, 0.5, 0.75]
        case .swing: [0, min(max(swing, 0.5), 0.8)]
        case .gallop: [0, 0.5, 0.75]
        case .reverseGallop: [0, 0.25, 0.5]
        case .quintuplets: (0..<5).map { Double($0) / 5 }
        case .sextuplets: (0..<6).map { Double($0) / 6 }
        }
    }

    var glyph: String {
        switch self {
        case .quarter: "♩"
        case .eighths: "♫"
        case .triplets: "³"
        case .sixteenths: "♬"
        case .swing: "♪♪"
        case .gallop: "♪♬"
        case .reverseGallop: "♬♪"
        case .quintuplets: "⁵"
        case .sextuplets: "⁶"
        }
    }

    var label: String {
        switch self {
        case .quarter: "Noires"
        case .eighths: "Croches"
        case .triplets: "Triolets"
        case .sixteenths: "Doubles"
        case .swing: "Swing"
        case .gallop: "Galop"
        case .reverseGallop: "Galop inv."
        case .quintuplets: "Quintolets"
        case .sextuplets: "Sextolets"
        }
    }
}

/// Synthesised sound kits.
enum SoundKit: String, Codable, CaseIterable, Identifiable, Sendable {
    case click, woodblock, clave, beep, cowbell, hihat, drums

    var id: String { rawValue }

    var label: String {
        switch self {
        case .click: "Clic"
        case .woodblock: "Wood-block"
        case .clave: "Claves"
        case .beep: "Bip"
        case .cowbell: "Cloche"
        case .hihat: "Charleston"
        case .drums: "Batterie"
        }
    }

    var symbol: String {
        switch self {
        case .click: "metronome.fill"
        case .woodblock: "rectangle.fill"
        case .clave: "line.diagonal"
        case .beep: "waveform"
        case .cowbell: "bell.fill"
        case .hihat: "circle.hexagongrid.fill"
        case .drums: "music.note"
        }
    }
}

struct TimeSignature: Hashable, Sendable {
    var beats: Int
    var unit: Int

    static let common: [TimeSignature] = [
        .init(beats: 2, unit: 4), .init(beats: 3, unit: 4), .init(beats: 4, unit: 4), .init(beats: 5, unit: 4),
        .init(beats: 6, unit: 8), .init(beats: 7, unit: 8), .init(beats: 9, unit: 8), .init(beats: 12, unit: 8),
    ]

    static let units = [2, 4, 8, 16]

    var label: String { "\(beats)/\(unit)" }

    /// Musically sensible default accents: downbeat accented, and in compound / odd
    /// eighth-note meters the group starts are normal and the others soft.
    var defaultAccents: [AccentLevel] {
        guard beats > 0 else { return [] }
        var accents = [AccentLevel](repeating: .normal, count: beats)
        var groupStarts: Set<Int>?
        if unit >= 8 {
            switch beats {
            case 5: groupStarts = [0, 3]           // 3+2
            case 7: groupStarts = [0, 2, 4]        // 2+2+3
            case let n where n % 3 == 0 && n > 3: groupStarts = Set(stride(from: 0, to: n, by: 3))
            default: break
            }
        }
        if let groupStarts {
            for i in 0..<beats where !groupStarts.contains(i) { accents[i] = .soft }
        }
        accents[0] = .accent
        return accents
    }
}

enum Tempo {
    static let range: ClosedRange<Double> = 20...400

    static func clamp(_ bpm: Double) -> Double { min(max(bpm, range.lowerBound), range.upperBound) }

    /// Traditional Italian tempo marking for a BPM value.
    static func marking(for bpm: Double) -> String {
        switch bpm {
        case ..<25: "Larghissimo"
        case ..<40: "Grave"
        case ..<55: "Largo"
        case ..<66: "Larghetto"
        case ..<76: "Adagio"
        case ..<92: "Andante"
        case ..<108: "Andantino"
        case ..<120: "Moderato"
        case ..<156: "Allegro"
        case ..<176: "Vivace"
        case ..<200: "Presto"
        default: "Prestissimo"
        }
    }
}
