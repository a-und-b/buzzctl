# Roadmap

Die Basis ist bewusst minimal: ein Event pro Bedienelement, Profile per
Frontmost-App, Aktionen als Shell-Kommando oder Tastatur-Shortcut.
Nachrüstbar, grob nach Nutzen sortiert:

## Bedienung
- **Gesten:** Doppelklick, Langdruck (Timer zwischen press/release), Drücken+Drehen als eigene Events
- **Rad als Modus-Wähler:** Drehen wählt Aktion/Profil (LED-Farbe als Feedback), Drücken führt aus
- **Wheel-Tuning:** Schrittweite/Beschleunigung konfigurierbar, Aktion erst pro N Schritte

## Aktionen
- **Media-Keys** nativ (Lautstärke, Play/Pause via `NX_KEYTYPE_*` statt osascript-Umweg)
- **Layout-aware Keycodes:** aktuell US-physisch (auf QWERTZ sind z/y vertauscht) → Mapping via `UCKeyTranslate`
- **Aktions-Sequenzen** (mehrere Aktionen pro Event) und Inline-Variablen (z. B. Radposition an Shell übergeben)

## LED
- **Animationen:** Pulsieren, Blinken, Lauflicht — z. B. als Timer- oder Statusanzeige
- **Aufräumen beim Beenden:** Signal-Handler, der die LEDs ausschaltet bzw. Zustand wiederherstellt

## Infrastruktur
- **Menubar-UI:** aktives Profil anzeigen, Config öffnen, Daemon pausieren
- **Mehrere Buzzer** gleichzeitig (Unterscheidung über Seriennummer / `kMIDIPropertyUniqueID`)
- **Homebrew-Formula** + signiertes Release-Binary
- **Linux/Windows-Port:** Protokoll ist dokumentiert (README); ALSA rawmidi bzw. WinMM genügen
- **Config-Schema-Validierung** mit hilfreichen Fehlermeldungen
