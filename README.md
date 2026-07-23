# buzzctl

Die timeBuzzer®-Hardware ohne Hersteller-Software nutzen: dokumentiertes
MIDI-Protokoll, Debug-Tool und `buzzerd` — ein macOS-Daemon, der Rad/Taster
auf Shortcuts und Shell-Kommandos mappt, mit App-Profilen und LED-Feedback.

> Dieses Projekt steht in keiner Verbindung zur Ideas in Logic GbR.
> timeBuzzer® ist eine eingetragene Marke des jeweiligen Inhabers; der Name
> wird hier nur zur Beschreibung der Gerätekompatibilität verwendet.

## buzzerd

```bash
swiftc -O buzzerd.swift -o buzzerd
./buzzerd buzzerd.json
```

- **Profile:** `buzzerd.json` mappt Bundle-IDs (Frontmost-App) auf Profile,
  `default` als Fallback. Änderungen werden im Betrieb übernommen (mtime-Poll).
- **Events:** `press`, `release`, `wheelUp`, `wheelDown`.
- **Aktionen:** `{"shell": "…"}` (auch `shortcuts run "Name"` für die
  Shortcuts-App, keine Sonderrechte nötig) oder `{"key": "cmd+shift+m"}`
  (braucht einmalig Bedienungshilfen-Berechtigung für das Binary).
- **LED:** `"led": [r,g,b]` (alle 3 LEDs) oder 9 Werte einzeln, 0–127 —
  zeigt das aktive Profil an.
- **Hot-Plug:** Buzzer ab-/anstecken wird erkannt.
- **Autostart:** in `buzzerd.plist` die beiden `/PATH/TO`-Einträge anpassen,
  dann `cp buzzerd.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/buzzerd.plist`.
- **Selbsttest:** `./buzzerd selftest`

Geplante Erweiterungen: siehe [ROADMAP.md](ROADMAP.md).

## Erkenntnisse (Stand 2026-07-23)

- Das Gerät ist **kein HID**, sondern ein **USB-MIDI-Gerät** (USB `16D0:1170`,
  Audio-Class mit MIDI-Streaming-Interface). macOS bindet es automatisch an den
  MIDIServer — es erscheint als MIDI-Source **und** -Destination namens „timeBuzzer".
- **Protokoll (vollständig entschlüsselt):** alles Control Change auf Kanal 12 (Status `0xBB`):

  | CC | Richtung | Bedeutung |
  |----|----------|-----------|
  | 70–72 | → Gerät | LED links: R, G, B (0–127) |
  | 73–75 | → Gerät | LED mitte: R, G, B |
  | 76–78 | → Gerät | LED rechts: R, G, B |
  | 80 | ← Gerät | Rad, absolute Position 0–127 (wrappt) |
  | 81 | ← Gerät | Touch-Sensor, aktiv-niedrig: < 64 = berührt; Status wird alle ~1,5 s wiederholt (sieht wie ein Heartbeat aus) |
  | 82 | ← Gerät | Taster: 127 = gedrückt, 0 = losgelassen |
- Keine Antwort auf Standard-SysEx Identity Request (`F0 7E 7F 06 01 F7`).
- Echo des Heartbeats zurück ans Gerät ändert (im MIDI-Log sichtbar) nichts.
- Kein existierendes OSS-Projekt für diese Hardware gefunden (GitHub-Treffer
  namens „TimeBuzzer" sind unabhängige Software-Zeittracker).

## Tool

`buzzer.swift` — null Dependencies, direkt ausführbar:

```
swift buzzer.swift listen                    # eingehende Events dumpen (hex + dekodiert)
swift buzzer.swift led 127 0 0               # alle 3 LEDs rot
swift buzzer.swift led 127 0 0 0 127 0 0 0 127   # links rot, mitte grün, rechts blau
swift buzzer.swift send BB 46 7F             # rohe MIDI-Bytes senden
swift buzzer.swift scan [von] [bis] [ms]     # CCs einzeln durchsteppen
```

`led-ui.html` — Browser-UI (Web MIDI, in Chrome öffnen) mit Buttons für die LED-CCs.

Da das Gerät ein Standard-MIDI-Gerät ist, funktioniert jede MIDI-Lib direkt:
Python (`mido`), Node (`easymidi`), Browser (Web MIDI API) — kein Treiber nötig.

## Verwandte Projekte

- [vertexitde/OpenBuzzer](https://github.com/vertexitde/OpenBuzzer) —
  Electron-App für LED-Animationen (Pomodoro, Media-Keys, Plugin-System),
  nutzt dasselbe MIDI-Protokoll.
