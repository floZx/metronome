import SwiftUI

struct ContentView: View {
    @Environment(MetronomeController.self) private var metronome
    @State private var showPanel = false
    @State private var panelTab: PanelTab = .rhythm
    @FocusState private var keyboardFocus: Bool

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 780
            ZStack {
                BackgroundView(theme: metronome.prefs.theme)
                FlashOverlay()
                HStack(spacing: 0) {
                    MainColumn(wide: wide) { tab in
                        panelTab = tab
                        if !wide { showPanel = true }
                    }
                    .frame(maxWidth: wide ? .infinity : 560)
                    .frame(maxWidth: .infinity)
                    if wide {
                        ControlPanel(tab: $panelTab)
                            .frame(width: 400)
                            .background(Color.black.opacity(0.22).ignoresSafeArea())
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Palette.cardStroke).frame(width: 1).ignoresSafeArea()
                            }
                            .transition(.move(edge: .trailing))
                    }
                }
            }
            .animation(.snappy, value: wide)
        }
        .sheet(isPresented: $showPanel) {
            ControlPanel(tab: $panelTab, showsClose: true)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.backgroundTop)
                .environment(metronome)
                .preferredColorScheme(.dark)
        }
        .tint(metronome.prefs.theme.color)
        #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocus)
        .onAppear { keyboardFocus = true }
        .onKeyPress(.space) { metronome.toggle(); return .handled }
        .onKeyPress(.upArrow) { metronome.nudge(1); return .handled }
        .onKeyPress(.downArrow) { metronome.nudge(-1); return .handled }
        .onKeyPress(.rightArrow) { metronome.nudge(10); return .handled }
        .onKeyPress(.leftArrow) { metronome.nudge(-10); return .handled }
        .onKeyPress(characters: .init(charactersIn: "tT")) { _ in metronome.tap(); return .handled }
        #endif
    }
}

private struct MainColumn: View {
    let wide: Bool
    let openPanel: (PanelTab) -> Void

    var body: some View {
        VStack(spacing: 16) {
            TopBar(wide: wide, openPanel: openPanel)
            BeatIndicatorRow()
                .frame(height: 76)
            TempoDial()
                .frame(maxWidth: 440, maxHeight: 440)
                .layoutPriority(1)
            TrainerStatus(openPanel: openPanel)
            TempoControls()
            SubdivisionStrip()
            PlayButton()
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(MetronomeController.self) private var metronome
    let wide: Bool
    let openPanel: (PanelTab) -> Void

    var body: some View {
        HStack(alignment: .center) {
            Menu {
                ForEach(TimeSignature.common, id: \.self) { signature in
                    Button(signature.label) { metronome.setTimeSignature(signature) }
                }
                Divider()
                Button("Plus d'options…") { openPanel(.rhythm) }
            } label: {
                SignatureGlyph(signature: metronome.settings.timeSignature)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            Spacer()
            StatusCenter()
            Spacer()

            if wide {
                Color.clear.frame(width: 44, height: 44)
            } else {
                HStack(spacing: 6) {
                    iconButton("bookmark.fill") { openPanel(.presets) }
                    iconButton("slider.horizontal.3") { openPanel(.rhythm) }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct SignatureGlyph: View {
    @Environment(MetronomeController.self) private var metronome
    let signature: TimeSignature

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: -4) {
                Text("\(signature.beats)")
                Text("\(signature.unit)")
            }
            .font(.system(size: 19, weight: .bold, design: .serif))
            .monospacedDigit()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct StatusCenter: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        VStack(spacing: 2) {
            if metronome.isPlaying, let start = metronome.startDate {
                Text("Mesure \(metronome.currentBar + 1)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(elapsedText(from: start, to: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.secondaryText)
                }
            } else if let preset = metronome.activePreset {
                Text(preset.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("Préréglage").font(.caption).foregroundStyle(Palette.secondaryText)
            } else {
                Text("Métronome").font(.subheadline.weight(.semibold))
                Text(metronome.settings.sound.label).font(.caption).foregroundStyle(Palette.secondaryText)
            }
        }
        .animation(.snappy, value: metronome.currentBar)
    }

    private func elapsedText(from start: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        let timer = metronome.prefs.timerMinutes
        let base = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return timer > 0 ? "\(base) / \(timer):00" : base
    }
}

// MARK: - Beats

struct BeatIndicatorRow: View {
    @Environment(MetronomeController.self) private var metronome
    var showsPulses = true

    var body: some View {
        let accents = metronome.settings.accents
        let pulses = metronome.settings.subdivision.pulseOffsets(swing: metronome.settings.swing).count
        HStack(alignment: .bottom, spacing: accents.count > 8 ? 4 : 8) {
            ForEach(accents.indices, id: \.self) { index in
                BeatCell(
                    level: accents[index],
                    isActive: metronome.isPlaying && metronome.currentBeat == index,
                    activePulse: metronome.currentBeat == index ? metronome.currentPulse : nil,
                    pulses: showsPulses && metronome.prefs.showPulseDots ? pulses : 1,
                    silent: metronome.isSilentBar,
                    theme: metronome.prefs.theme
                )
                .contentShape(Rectangle())
                .onTapGesture { metronome.cycleAccent(at: index) }
                .accessibilityLabel("Temps \(index + 1), \(accents[index].label)")
                .accessibilityAddTraits(.isButton)
            }
        }
        .animation(.snappy(duration: 0.25), value: accents)
    }
}

private struct BeatCell: View {
    let level: AccentLevel
    let isActive: Bool
    let activePulse: Int?
    let pulses: Int
    let silent: Bool
    let theme: ThemeColor

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                VStack {
                    Spacer(minLength: 0)
                    bar.frame(height: max(geo.size.height * level.heightFraction, 8))
                }
            }
            if pulses > 1 {
                HStack(spacing: 3) {
                    ForEach(0..<pulses, id: \.self) { pulse in
                        Circle()
                            .fill(isActive && activePulse == pulse ? AnyShapeStyle(theme.color) : AnyShapeStyle(Palette.idle))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: 56)
    }

    @ViewBuilder private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if level == .mute {
            shape.strokeBorder(isActive ? theme.color : Palette.idle, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        } else {
            shape
                .fill(fill)
                .shadow(color: isActive && !silent ? theme.color.opacity(0.7) : .clear, radius: 12)
                .scaleEffect(x: isActive ? 1.06 : 1, y: 1, anchor: .bottom)
                .animation(.easeOut(duration: 0.12), value: isActive)
        }
    }

    private var fill: AnyShapeStyle {
        if isActive && silent { return AnyShapeStyle(Color.white.opacity(0.35)) }
        if isActive {
            return AnyShapeStyle(LinearGradient(colors: [theme.color, theme.deep], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(level == .accent ? Color.white.opacity(0.28) : Palette.idle)
    }
}

// MARK: - Dial

struct TempoDial: View {
    @Environment(MetronomeController.self) private var metronome
    @State private var lastAngle: Double?
    @State private var accumulated: Double = 0
    @State private var dragged = false

    private let degreesPerBPM = 4.0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let theme = metronome.prefs.theme
            let bpm = metronome.displayedBPM
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.02)],
                                         center: .center, startRadius: 0, endRadius: size / 2))
                Circle().strokeBorder(Palette.cardStroke, lineWidth: 1)

                // Rotating graduation ring.
                TickRing()
                    .rotationEffect(.degrees(bpm * degreesPerBPM))
                    .padding(size * 0.035)
                    .animation(.snappy(duration: 0.18), value: bpm)

                // Tempo arc (logarithmic so common tempos spread nicely).
                let fraction = log(bpm / Tempo.range.lowerBound) / log(Tempo.range.upperBound / Tempo.range.lowerBound)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(AngularGradient(colors: [theme.deep, theme.color, theme.deep], center: .center),
                            style: StrokeStyle(lineWidth: size * 0.022, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(size * 0.12)
                    .animation(.snappy(duration: 0.25), value: fraction)
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: size * 0.022)
                    .padding(size * 0.12)

                // Beat pulse.
                let strength = metronome.isSilentBar || metronome.lastBeatLevel == .mute ? 0
                    : (metronome.lastBeatLevel == .accent ? 1.0 : 0.55)
                Circle()
                    .stroke(theme.color, lineWidth: 3)
                    .padding(size * 0.12)
                    .keyframeAnimator(initialValue: 0.0, trigger: metronome.beatCount) { content, value in
                        content
                            .scaleEffect(1 + 0.06 * (1 - value) * (value > 0 ? 1 : 0))
                            .opacity(value * strength)
                            .shadow(color: theme.color.opacity(value * 0.8), radius: 18 * value)
                    } keyframes: { _ in
                        LinearKeyframe(1, duration: 0.015)
                        CubicKeyframe(0, duration: 0.38)
                    }

                VStack(spacing: size * 0.005) {
                    Text("\(Int(bpm.rounded()))")
                        .font(.system(size: size * 0.25, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: bpm))
                        .animation(.snappy(duration: 0.2), value: Int(bpm.rounded()))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("BPM")
                        .font(.system(size: size * 0.042, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(theme.color)
                    Text(Tempo.marking(for: bpm))
                        .font(.system(size: size * 0.05, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.top, size * 0.01)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(dragGesture(center: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2), size: size))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo")
            .accessibilityValue("\(Int(bpm.rounded())) battements par minute, \(Tempo.marking(for: bpm))")
            .accessibilityAdjustableAction { direction in
                metronome.nudge(direction == .increment ? 1 : -1)
            }
            .accessibilityAction(named: metronome.isPlaying ? "Arrêter" : "Démarrer") { metronome.toggle() }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func dragGesture(center: CGPoint, size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let dx = gesture.location.x - center.x
                let dy = gesture.location.y - center.y
                if hypot(gesture.translation.width, gesture.translation.height) > 6 { dragged = true }
                // Ignore the very centre where the angle is unstable.
                guard hypot(dx, dy) > size * 0.1 else { lastAngle = nil; return }
                let angle = atan2(dy, dx) * 180 / .pi
                if let lastAngle {
                    var delta = angle - lastAngle
                    if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
                    accumulated += delta
                    let steps = (accumulated / degreesPerBPM).rounded(.towardZero)
                    if steps != 0 {
                        metronome.nudge(steps)
                        accumulated -= steps * degreesPerBPM
                        Haptics.selection()
                    }
                }
                lastAngle = angle
            }
            .onEnded { _ in
                if !dragged { metronome.toggle() }
                lastAngle = nil
                accumulated = 0
                dragged = false
            }
    }
}

private struct TickRing: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for i in 0..<90 {
                let angle = Double(i) / 90 * 2 * .pi
                let major = i % 5 == 0
                let length = radius * (major ? 0.07 : 0.035)
                let start = CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length))
                let end = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(.white.opacity(major ? 0.3 : 0.13)),
                               style: StrokeStyle(lineWidth: major ? 2 : 1, lineCap: .round))
            }
        }
    }
}

// MARK: - Controls

private struct TrainerStatus: View {
    @Environment(MetronomeController.self) private var metronome
    let openPanel: (PanelTab) -> Void

    var body: some View {
        let trainer = metronome.settings.trainer
        let timer = metronome.prefs.timerMinutes
        if trainer.rampEnabled || trainer.gapEnabled || timer > 0 {
            HStack(spacing: 8) {
                if trainer.rampEnabled {
                    chip("arrow.up.right", "\(Int(metronome.settings.bpm)) → \(Int(trainer.rampTarget))")
                }
                if trainer.gapEnabled {
                    chip(metronome.isSilentBar ? "speaker.slash.fill" : "speaker.wave.2.fill",
                         "\(trainer.gapPlayBars) + \(trainer.gapMuteBars) muette\(trainer.gapMuteBars > 1 ? "s" : "")")
                }
                if timer > 0 {
                    chip("timer", "\(timer) min")
                }
            }
            .onTapGesture { openPanel(.trainer) }
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(metronome.prefs.theme.color.opacity(0.16), in: Capsule())
            .foregroundStyle(metronome.prefs.theme.color)
    }
}

private struct TempoControls: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        HStack(spacing: 14) {
            round("minus") { metronome.nudge(-1) }
            let tapColor = metronome.prefs.theme.color
            Button { metronome.tap() } label: {
                Text("TAP")
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(4)
                    .frame(width: 120, height: 52)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.cardStroke))
                    .keyframeAnimator(initialValue: 0.0, trigger: metronome.tapCount) { content, value in
                        content
                            .background(tapColor.opacity(0.45 * value), in: Capsule())
                            .scaleEffect(1 - 0.05 * value)
                    } keyframes: { _ in
                        LinearKeyframe(1, duration: 0.02)
                        CubicKeyframe(0, duration: 0.3)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tap tempo")
            round("plus") { metronome.nudge(1) }
        }
    }

    private func round(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(Palette.cardStroke))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(symbol == "plus" ? "Augmenter le tempo" : "Diminuer le tempo")
    }
}

private struct SubdivisionStrip: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        // Plain row when everything fits (Mac, iPad); scrolling strip otherwise (iPhone).
        ViewThatFits(in: .horizontal) {
            chips(width: 58).fixedSize()
            // Scrolls edge to edge of the screen, past the column's 20 pt margins.
            ScrollView(.horizontal, showsIndicators: false) {
                chips(width: 66).padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
        .frame(maxWidth: .infinity)
    }

    private func chips(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(Subdivision.allCases) { subdivision in
                let selected = metronome.settings.subdivision == subdivision
                Button {
                    metronome.settings.subdivision = subdivision
                    Haptics.selection()
                } label: {
                    VStack(spacing: 0) {
                        Text(subdivision.glyph).font(.system(size: 20))
                        Text(subdivision.label)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 3)
                    .frame(width: width, height: 50)
                    .foregroundStyle(selected ? .black : .white.opacity(0.85))
                    .background(
                        selected ? AnyShapeStyle(metronome.prefs.theme.color) : AnyShapeStyle(Color.white.opacity(0.07)),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Subdivision \(subdivision.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct PlayButton: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        let theme = metronome.prefs.theme
        Button { metronome.toggle() } label: {
            Image(systemName: metronome.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 30, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.black)
                .frame(width: 84, height: 84)
                .background(LinearGradient(colors: [theme.color, theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())
                .shadow(color: theme.color.opacity(metronome.isPlaying ? 0.6 : 0.3), radius: metronome.isPlaying ? 22 : 12)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(metronome.isPlaying ? "Arrêter" : "Démarrer")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private struct FlashOverlay: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        let peak = metronome.prefs.flashOnDownbeat && !metronome.isSilentBar ? 0.22 : 0
        Rectangle()
            .fill(metronome.prefs.theme.color)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .keyframeAnimator(initialValue: 0.0, trigger: metronome.downbeatCount) { content, value in
                content.opacity(value * peak)
            } keyframes: { _ in
                LinearKeyframe(1, duration: 0.01)
                CubicKeyframe(0, duration: 0.35)
            }
    }
}
