# buzzctl

Use the timeBuzzer® hardware without the vendor software: documented MIDI
protocol, a debug tool, and `buzzerd` — a macOS daemon that maps the wheel
and button to keyboard shortcuts and shell commands, with per-app profiles
and LED feedback.

> This project is not affiliated with Ideas in Logic GbR. timeBuzzer® is a
> registered trademark of its respective owner; the name is used here solely
> to describe device compatibility.

## buzzerd

```bash
swiftc -O buzzerd.swift -o buzzerd
./buzzerd buzzerd.json
```

- **Profiles:** `buzzerd.json` maps bundle IDs (frontmost app) to profiles,
  with `default` as fallback. Changes are picked up at runtime (mtime poll).
- **Events:** `press`, `release`, `wheelUp`, `wheelDown`, `touch`, `untouch`
  (resting a hand on the buzzer without pressing).
- **Actions:** `{"shell": "…"}` (including `shortcuts run "Name"` for the
  macOS Shortcuts app, no special permissions needed) or
  `{"key": "cmd+shift+m"}`. Named media keys — `volumeup`, `volumedown`,
  `mute`, `playpause`, `next`, `previous` — are sent as native system events,
  so the macOS volume/playback HUD shows up. All `key` actions require a
  one-time Accessibility grant; buzzerd prompts for it at startup if needed.
- **LED:** `"led": [r,g,b]` (all 3 LEDs) or 9 values for individual control,
  0–127 — shows which profile is active.
- **Hot-plug:** unplugging/replugging the buzzer is detected.
- **Autostart:** edit the two `/PATH/TO` entries in `buzzerd.plist`, then
  `cp buzzerd.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/buzzerd.plist`.
- **Self-check:** `./buzzerd selftest`

Planned features: see [ROADMAP.md](ROADMAP.md).

## Protocol

The device is **not HID** — it is a standard **USB MIDI device**
(USB `16D0:1170`, audio class with a MIDI streaming interface). macOS binds
it to the MIDIServer automatically; it shows up as a MIDI source **and**
destination named "timeBuzzer". No driver required.

Everything is Control Change on MIDI channel 12 (status byte `0xBB`):

| CC | Direction | Meaning |
|----|-----------|---------|
| 70–72 | → device | Left LED: R, G, B (0–127) |
| 73–75 | → device | Middle LED: R, G, B |
| 76–78 | → device | Right LED: R, G, B |
| 80 | ← device | Wheel, absolute position 0–127 (wraps) |
| 81 | ← device | Touch sensor, active-low: < 64 = touched; state is repeated every ~1.5 s (looks like a heartbeat) |
| 82 | ← device | Button: 127 = pressed, 0 = released |

The device does not respond to the standard SysEx identity request
(`F0 7E 7F 06 01 F7`).

## Tools

```
swift buzzer.swift listen                    # dump incoming events (hex + decoded)
swift buzzer.swift led 127 0 0               # all 3 LEDs red
swift buzzer.swift led 127 0 0 0 127 0 0 0 127   # left red, middle green, right blue
swift buzzer.swift send BB 46 7F             # send raw MIDI bytes
swift buzzer.swift scan [from] [to] [ms]     # step through CCs one by one
```

`led-ui.html` — browser UI (Web MIDI, open in Chrome) with buttons for the
LED CCs.

Since this is a standard MIDI device, any MIDI library works out of the box:
Python (`mido`), Node (`easymidi`), the browser (Web MIDI API) — no driver
needed.

## Acknowledgements

- [Ideas in Logic GbR](https://timebuzzer.com/) — makers of the timeBuzzer®
  hardware this project builds on. If you like the device, buy one from them.
- [vertexitde/OpenBuzzer](https://github.com/vertexitde/OpenBuzzer) — Electron
  app for LED animations (Pomodoro, media keys, plugin system) using the same
  MIDI protocol; also provided the hint that CC 81 is a touch sensor, not a
  heartbeat.

## License

[MIT](LICENSE)
