import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case rhythm, sound, trainer, presets, display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rhythm: "Rythme"
        case .sound: "Son"
        case .trainer: "Entraînement"
        case .presets: "Préréglages"
        case .display: "Affichage"
        }
    }

    var symbol: String {
        switch self {
        case .rhythm: "music.quarternote.3"
        case .sound: "speaker.wave.2.fill"
        case .trainer: "figure.run"
        case .presets: "bookmark.fill"
        case .display: "paintpalette.fill"
        }
    }
}

struct ControlPanel: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(\.dismiss) private var dismiss
    @Binding var tab: PanelTab
    var showsClose = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(tab.title).font(.title2.bold())
                Spacer()
                if showsClose {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
            }
            tabStrip
            ScrollView {
                VStack(spacing: 14) {
                    switch tab {
                    case .rhythm: RhythmSection()
                    case .sound: SoundSection()
                    case .trainer: TrainerSection()
                    case .presets: PresetsSection()
                    case .display: DisplaySection()
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
        .padding(.top, showsClose ? 22 : 16)
        .foregroundStyle(.white)
        .toggleStyle(.switch)
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(PanelTab.allCases) { item in
                let selected = item == tab
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tab = item }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selected ? .black : .white.opacity(0.75))
                        .background(
                            selected ? AnyShapeStyle(metronome.prefs.theme.color) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
            }
        }
        .padding(4)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Rhythm

private struct RhythmSection: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        @Bindable var metronome = metronome
        let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

        Card(title: "Signature rythmique") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(TimeSignature.common, id: \.self) { signature in
                    SelectChip(title: signature.label, isSelected: metronome.settings.timeSignature == signature) {
                        metronome.setTimeSignature(signature)
                    }
                }
            }
            ValueStepper(title: "Temps par mesure",
                         intValue: Binding(get: { metronome.settings.beatsPerBar }, set: { metronome.setBeats($0) }),
                         range: 1...16)
            HStack {
                Text("Unité").foregroundStyle(.white.opacity(0.85))
                Spacer()
                Picker("Unité", selection: $metronome.settings.beatUnit) {
                    ForEach(TimeSignature.units, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
        }

        Card(title: "Accents", subtitle: "Touchez un temps pour passer de accent → normal → faible → muet.") {
            BeatIndicatorRow(showsPulses: false)
                .frame(height: 64)
            Button("Accents par défaut") { metronome.resetAccents() }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(metronome.prefs.theme.color)
        }

        Card(title: "Subdivision") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(Subdivision.allCases) { subdivision in
                    SelectChip(title: subdivision.glyph, caption: subdivision.label,
                               isSelected: metronome.settings.subdivision == subdivision) {
                        metronome.settings.subdivision = subdivision
                    }
                }
            }
            if metronome.settings.subdivision == .swing {
                LabeledSlider(title: "Swing", value: $metronome.settings.swing, range: 0.5...0.8,
                              display: { "\(Int(($0 * 100).rounded())) %" }, tint: metronome.prefs.theme.color)
            }
            LabeledSlider(title: "Volume des subdivisions", value: $metronome.settings.subdivisionVolume,
                          tint: metronome.prefs.theme.color)
        }
    }
}

// MARK: - Sound

private struct SoundSection: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        @Bindable var metronome = metronome
        Card(title: "Timbre") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(SoundKit.allCases) { kit in
                    SelectChip(title: kit.label, symbol: kit.symbol, isSelected: metronome.settings.sound == kit) {
                        metronome.settings.sound = kit
                    }
                }
            }
        }
        Card(title: "Volume") {
            LabeledSlider(title: "Général", value: $metronome.prefs.masterVolume, tint: metronome.prefs.theme.color)
            LabeledSlider(title: "Subdivisions", value: $metronome.settings.subdivisionVolume, tint: metronome.prefs.theme.color)
        }
        Text("Astuce : le métronome se mélange à votre musique, vous pouvez jouer par-dessus un morceau.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Trainer

private struct TrainerSection: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        @Bindable var metronome = metronome
        let tint = metronome.prefs.theme.color

        Card(title: "Accélération progressive", subtitle: "Le tempo évolue automatiquement jusqu'à la cible.") {
            Toggle("Activer", isOn: $metronome.settings.trainer.rampEnabled).tint(tint)
            if metronome.settings.trainer.rampEnabled {
                ValueStepper(title: "Pas", value: $metronome.settings.trainer.rampStep, range: 1...30,
                             format: { "\(Int($0)) BPM" })
                ValueStepper(title: "Toutes les", intValue: $metronome.settings.trainer.rampEveryBars, range: 1...32,
                             format: { "\($0) mes." })
                ValueStepper(title: "Tempo cible", value: $metronome.settings.trainer.rampTarget, range: Tempo.range,
                             step: 5, format: { "\(Int($0)) BPM" })
                Text("Départ à \(Int(metronome.settings.bpm)) BPM, \(metronome.settings.trainer.rampTarget >= metronome.settings.bpm ? "accélère" : "ralentit") jusqu'à \(Int(metronome.settings.trainer.rampTarget)) BPM.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }

        Card(title: "Mesures muettes", subtitle: "Coupe le son par moments pour vérifier que vous gardez le tempo.") {
            Toggle("Activer", isOn: $metronome.settings.trainer.gapEnabled).tint(tint)
            if metronome.settings.trainer.gapEnabled {
                ValueStepper(title: "Mesures jouées", intValue: $metronome.settings.trainer.gapPlayBars, range: 1...16)
                ValueStepper(title: "Mesures muettes", intValue: $metronome.settings.trainer.gapMuteBars, range: 1...16)
            }
        }

        Card(title: "Minuteur", subtitle: "Arrête le métronome après la durée choisie.") {
            Picker("Durée", selection: $metronome.prefs.timerMinutes) {
                Text("Désactivé").tag(0)
                ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.menu)
            .tint(tint)
        }
    }
}

// MARK: - Presets

private struct PresetsSection: View {
    @Environment(MetronomeController.self) private var metronome
    @State private var name = ""

    var body: some View {
        let tint = metronome.prefs.theme.color
        Card(title: "Enregistrer la configuration", subtitle: metronome.settings.summary) {
            HStack(spacing: 8) {
                TextField("Nom (ex. Morceau, exercice…)", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .onSubmit(save)
                Button(action: save) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.black)
                        .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enregistrer")
            }
        }

        if metronome.presets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark").font(.largeTitle).foregroundStyle(Palette.secondaryText)
                Text("Aucun préréglage").font(.headline)
                Text("Enregistrez vos tempos et réglages pour chaque morceau, puis rappelez-les d'un geste.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                ForEach(metronome.presets) { preset in
                    PresetRow(preset: preset)
                }
            }
        }
    }

    private func save() {
        metronome.savePreset(named: name)
        name = ""
    }
}

private struct PresetRow: View {
    @Environment(MetronomeController.self) private var metronome
    let preset: Preset

    var body: some View {
        let active = metronome.activePresetID == preset.id
        let tint = metronome.prefs.theme.color
        HStack(spacing: 12) {
            Text("\(Int(preset.settings.bpm))")
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 52, height: 44)
                .foregroundStyle(active ? .black : tint)
                .background(active ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(preset.settings.timeSignature.label) · \(preset.settings.subdivision.label) · \(preset.settings.sound.label)")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button { metronome.updatePreset(preset) } label: {
                    Label("Remplacer par les réglages actuels", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) { metronome.deletePreset(preset) } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(active ? tint.opacity(0.6) : Palette.cardStroke))
        .contentShape(Rectangle())
        .onTapGesture { metronome.load(preset) }
    }
}

// MARK: - Display

private struct DisplaySection: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        @Bindable var metronome = metronome
        let tint = metronome.prefs.theme.color

        Card(title: "Couleur") {
            HStack(spacing: 12) {
                ForEach(ThemeColor.allCases) { theme in
                    Button { metronome.prefs.theme = theme } label: {
                        Circle()
                            .fill(LinearGradient(colors: [theme.color, theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(.white, lineWidth: metronome.prefs.theme == theme ? 3 : 0))
                            .padding(3)
                            .overlay(Circle().strokeBorder(theme.color.opacity(metronome.prefs.theme == theme ? 0.6 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.label)
                }
            }
            .frame(maxWidth: .infinity)
        }

        Card(title: "Retours") {
            Toggle("Flash visuel sur le 1er temps", isOn: $metronome.prefs.flashOnDownbeat).tint(tint)
            Toggle("Afficher les subdivisions", isOn: $metronome.prefs.showPulseDots).tint(tint)
            #if os(iOS)
            Toggle("Vibrations sur les temps", isOn: $metronome.prefs.haptics).tint(tint)
            #endif
        }

        #if os(macOS)
        Card(title: "Raccourcis clavier") {
            VStack(alignment: .leading, spacing: 8) {
                shortcut("Espace", "Démarrer / arrêter")
                shortcut("↑ ↓", "Tempo ± 1")
                shortcut("← →", "Tempo ± 10")
                shortcut("T", "Tap tempo")
            }
        }
        #endif

        Text("Astuce : faites tourner le cadran pour régler le tempo, touchez-le pour démarrer.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func shortcut(_ key: String, _ action: String) -> some View {
        HStack {
            Text(key)
                .font(.callout.weight(.semibold).monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            Text(action).foregroundStyle(.white.opacity(0.85))
        }
    }
}
