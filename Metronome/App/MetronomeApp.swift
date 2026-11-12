import SwiftUI

@main
struct MetronomeApp: App {
    @State private var metronome = MetronomeController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(metronome)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 720)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 780)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            CommandMenu("Métronome") {
                Button("Démarrer / Arrêter") { metronome.toggle() }
                    .keyboardShortcut(.return, modifiers: .command)
                Divider()
                Button("Tempo +1") { metronome.nudge(1) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Tempo −1") { metronome.nudge(-1) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Button("Tempo +10") { metronome.nudge(10) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Tempo −10") { metronome.nudge(-10) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Tap tempo") { metronome.tap() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}
