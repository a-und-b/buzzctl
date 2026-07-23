# buzzctl

Use the timeBuzzer® hardware without the vendor software: documented MIDI
protocol, a debug tool, and `buzzerd` — a macOS daemon that maps the wheel
and button to keyboard shortcuts and shell commands, with per-app profiles
and LED feedback.

> This project is not affiliated with Ideas in Logic GbR. timeBuzzer® is a
> registered trademark of its respective owner; the name is used here solely
> to describe device compatibility.

## Buzzctl.app (menu bar app)

Native menu bar app that bundles the daemon with a UI: connection status,
pause toggle, launch-at-login, and a graphical profile editor (with an app
picker, action fields, and an LED color picker).

1. Download the latest `Buzzctl-*.zip` from
   [Releases](https://github.com/a-und-b/buzzctl/releases), unzip, and move
   `Buzzctl.app` to `/Applications`.
2. The app is ad-hoc signed (no Apple Developer ID). On first launch macOS
   will refuse it once — allow it via System Settings → Privacy & Security →
   "Open Anyway", or clear the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Buzzctl.app
   ```

The app's config lives at `~/Library/Application Support/Buzzctl/buzzerd.json`
— edit it in the UI or as JSON (hot-reloaded either way). Building from
source instead: `./build.sh` produces both `Buzzctl.app` and the CLI.

## buzzerd (CLI)

```bash
./build.sh
./buzzerd buzzerd.json
```

- **Hot-plug:** unplugging/replugging the buzzer is detected.
- **Hot-reload:** config changes are picked up at runtime (mtime poll, ~2 s).
- **Verbose mode:** `./buzzerd -v buzzerd.json` logs every raw MIDI event.
- **Autostart:** edit the two `/PATH/TO` entries in `buzzerd.plist`, then
  `cp buzzerd.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/buzzerd.plist`.
- **Self-check:** `./buzzerd selftest`

Planned features: see [ROADMAP.md](ROADMAP.md).

### Configuration

`buzzerd.json` maps **app bundle IDs to profiles** (plus optional global
`timing`). The profile of the frontmost app is active; `default` is the
fallback for every app not listed:

```json
{
  "profiles": {
    "default": {
      "led": [0, 40, 127],
      "press":     { "key": "mute" },
      "wheelUp":   { "key": "volumeup" },
      "wheelDown": { "key": "volumedown" }
    },
    "com.apple.QuickTimePlayerX": {
      "led": [0, 127, 127],
      "press":     { "key": "space" },
      "wheelUp":   { "key": "right" },
      "wheelDown": { "key": "left" }
    },
    "com.microsoft.teams2": {
      "led": [127, 0, 0],
      "press": { "key": "cmd+shift+m" }
    }
  }
}
```

To find an app's bundle ID:

```bash
osascript -e 'id of app "QuickTime Player"'
```

#### Events

Every profile entry maps events to actions. All events are optional:

| Event | Fires when |
|-------|-----------|
| `press` / `release` | the buzzer is pressed down / let go |
| `doublePress` / `longPress` | two quick presses / held for ≥0.5 s |
| `wheelUp` / `wheelDown` | the wheel is turned (once per step) |
| `touch` / `untouch` | a hand approaches/hovers over the buzzer / moves away (proximity — no contact needed) |
| `longTouch` | hand hovering or resting for ≥0.5 s |

Gesture timing: with no double/long variant configured, `press` and `touch`
fire immediately (raw behavior). Configuring `longPress` moves the single
press to the release; configuring `doublePress` additionally delays it by
the double-tap window — the price of disambiguation. `release` and
`untouch` always fire on the physical transition.

Timings are global (they describe the user, not the app) and adjustable in
the settings next to each gesture row, or via an optional top-level `timing`
block. With one present, the file format is
`{ "timing": { "doublePressWindow": 0.3, "longPressHold": 0.5,
"longTouchHold": 0.5 }, "profiles": { … } }` —
bare profile dictionaries (the old format) still load fine.

The settings window also has a **test mode** (toggle above the events
table): buzzer inputs flash the matching event row instead of running
their actions — handy for tuning gestures without side effects.

#### Actions

An action is an object with exactly one of two keys:

- **`{"shell": "…"}`** — run a shell command (`/bin/sh -c`). Works without
  any permissions. This covers almost everything: `osascript`, `open`, and
  `shortcuts run "Name"` to trigger automations built in the macOS
  Shortcuts app.
- **`{"key": "…"}`** — synthesize a key press. Requires a one-time
  Accessibility grant (System Settings → Privacy & Security → Accessibility);
  buzzerd prompts for it at startup if key actions are configured.
  Two forms:
  - **Shortcut combos** like `cmd+shift+m` — modifiers `cmd`, `shift`,
    `alt`/`opt`, `ctrl`, plus one key: a letter, digit, `space`, `return`,
    `tab`, `delete`, `esc`, `f1`–`f12`, or arrow keys
    `left`/`right`/`up`/`down`. Key codes are US-physical; on QWERTZ
    layouts z/y are swapped (see ROADMAP).
  - **Named media keys** `volumeup`, `volumedown`, `mute`, `playpause`,
    `next`, `previous` — sent as native system events, so the macOS
    volume/playback HUD appears and playback controls reach whatever app
    is currently playing.

#### LED

`"led"` sets the buzzer's LED color while the profile is active — glanceable
feedback for which mode you're in. Values are 0–127 per channel:

- `[r, g, b]` — all three LEDs the same color
- `[r, g, b, r, g, b, r, g, b]` — left, middle, right LED individually

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
| 81 | ← device | Proximity sensor, active-low: < 64 = hand near/on the buzzer (triggers shortly before contact, binary threshold — only 0/127 observed); state is repeated every ~1.5 s (looks like a heartbeat) |
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
