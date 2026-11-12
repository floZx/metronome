# Métronome

Métronome natif SwiftUI pour **iOS 17+** et **macOS 14+** (une seule cible multiplateforme).

## Fonctionnalités
- Moteur audio précis à l'échantillon (`AVAudioEngine` + `AVAudioSourceNode`), sons synthétisés (aucun fichier audio)
- Tempo de 20 à 400 BPM : cadran rotatif, boutons ±, tap tempo, indication italienne (Allegro…)
- Signatures (2/4 à 12/8, 1 à 16 temps), accents par temps (accent / normal / faible / muet)
- Subdivisions : croches, triolets, doubles, swing réglable, galop, quintolets, sextolets
- 7 timbres : clic, wood-block, claves, bip, cloche, charleston, batterie
- Entraînement : accélération progressive, mesures muettes, minuteur
- Préréglages, 6 thèmes de couleur, flash visuel, vibrations (iOS)
- iOS : lecture en arrière-plan, se mélange à la musique ; macOS : raccourcis clavier (Espace, ↑↓, ←→, T)

## Construire
```bash
xcodegen generate
open Metronome.xcodeproj
```
Tests : `xcodebuild test -scheme Metronome -destination 'platform=macOS'`.
L'icône est générée par `swift scripts/make_icon.swift <sortie.png>`.
