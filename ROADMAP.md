# Roadmap

The base is deliberately minimal: one event per control, profiles keyed by
frontmost app, actions as shell commands or keyboard shortcuts.
Candidates for later, roughly sorted by usefulness:

## Input
- **Press+turn / touch+turn** as separate events (double/long press and touch are implemented)
- **Wheel as mode selector:** long-touch enters selection, turning cycles modes (LED color as feedback), pressing or a timeout confirms
- **Wheel tuning:** configurable step size/acceleration, trigger action every N steps

## Actions
- **Layout-aware key codes:** currently US-physical (z/y swapped on QWERTZ) → map via `UCKeyTranslate`
- **Action sequences** (multiple actions per event) and inline variables (e.g. pass the wheel position to the shell)

## LED
- **Animations:** pulse, blink, chase — e.g. as a timer or status display
- **Cleanup on exit:** signal handler that turns the LEDs off or restores their previous state

## Infrastructure
- **Multiple buzzers** at once (distinguished by serial number / `kMIDIPropertyUniqueID`)
- **Homebrew formula**; Developer-ID-signed and notarized releases; universal (Intel) binary
- **App icon** for Buzzctl.app
- **Linux/Windows port:** the protocol is documented (README); ALSA rawmidi or WinMM is all it takes
- **Config schema validation** with helpful error messages
