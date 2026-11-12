import SwiftUI

extension ThemeColor {
    var color: Color {
        switch self {
        case .amber: Color(red: 1.0, green: 0.66, blue: 0.22)
        case .coral: Color(red: 1.0, green: 0.45, blue: 0.38)
        case .rose: Color(red: 0.98, green: 0.4, blue: 0.62)
        case .violet: Color(red: 0.66, green: 0.52, blue: 1.0)
        case .sky: Color(red: 0.35, green: 0.72, blue: 1.0)
        case .mint: Color(red: 0.3, green: 0.9, blue: 0.7)
        }
    }

    /// Second gradient stop.
    var deep: Color {
        switch self {
        case .amber: Color(red: 1.0, green: 0.42, blue: 0.16)
        case .coral: Color(red: 0.92, green: 0.24, blue: 0.3)
        case .rose: Color(red: 0.78, green: 0.22, blue: 0.62)
        case .violet: Color(red: 0.44, green: 0.3, blue: 0.95)
        case .sky: Color(red: 0.2, green: 0.45, blue: 0.95)
        case .mint: Color(red: 0.1, green: 0.66, blue: 0.62)
        }
    }

    var label: String {
        switch self {
        case .amber: "Ambre"
        case .coral: "Corail"
        case .rose: "Rose"
        case .violet: "Violet"
        case .sky: "Ciel"
        case .mint: "Menthe"
        }
    }
}

enum Palette {
    static let backgroundTop = Color(red: 0.09, green: 0.09, blue: 0.13)
    static let backgroundBottom = Color(red: 0.03, green: 0.03, blue: 0.05)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let idle = Color.white.opacity(0.16)
    static let secondaryText = Color.white.opacity(0.55)
}

struct BackgroundView: View {
    let theme: ThemeColor

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop, Palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [theme.color.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.cardStroke))
    }
}

struct SelectChip: View {
    @Environment(MetronomeController.self) private var metronome
    let title: String
    var caption: String?
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let theme = metronome.prefs.theme
        Button(action: action) {
            VStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(caption == nil ? .subheadline.weight(.semibold) : .system(size: 20, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption {
                    Text(caption).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(isSelected ? .black.opacity(0.7) : Palette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: caption == nil && symbol == nil ? 38 : 56)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected ? .black : .white)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(colors: [theme.color, theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.white.opacity(0.07)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Compact − value + control.
struct ValueStepper: View {
    @Environment(MetronomeController.self) private var metronome
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0))" }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.85))
            Spacer()
            HStack(spacing: 4) {
                stepButton("minus", delta: -step)
                Text(format(value))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 64)
                    .contentTransition(.numericText(value: value))
                stepButton("plus", delta: step)
            }
        }
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        Button {
            withAnimation(.snappy) { value = min(max(value + delta, range.lowerBound), range.upperBound) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(delta < 0 ? value <= range.lowerBound : value >= range.upperBound)
    }
}

extension ValueStepper {
    init(title: String, intValue: Binding<Int>, range: ClosedRange<Int>, format: @escaping (Int) -> String = { "\($0)" }) {
        self.title = title
        self._value = Binding(get: { Double(intValue.wrappedValue) }, set: { intValue.wrappedValue = Int($0) })
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        self.step = 1
        self.format = { format(Int($0)) }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var display: (Double) -> String = { "\(Int(($0 * 100).rounded())) %" }
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(display(value)).font(.callout.monospacedDigit()).foregroundStyle(Palette.secondaryText)
            }
            Slider(value: $value, in: range).tint(tint)
        }
    }
}
