// buzzerd — CLI daemon for the timeBuzzer: maps wheel/button/touch to keyboard
// shortcuts and shell commands, with app profiles and LED feedback.
// The Buzzctl menu bar app wraps the same engine (see Engine.swift, BuzzctlApp.swift).
//
// usage: buzzerd [-v] [path/to/buzzerd.json]   (default: ./buzzerd.json; -v logs raw MIDI events)
//        buzzerd selftest
//
// Build: ./build.sh   (or: swiftc -O -parse-as-library Engine.swift buzzerd.swift -o buzzerd)

import AppKit

@main enum BuzzerdCLI {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("selftest") { selftest(); return }
        let engine = BuzzerEngine(configPath: args.dropFirst().first { $0 != "-v" } ?? "buzzerd.json")
        engine.verbose = args.contains("-v")
        engine.start()
        engine.log("buzzerd running — config: \(engine.configPath)")
        RunLoop.main.run()
    }

    // precondition, not assert: stays active in -O builds
    static func selftest() {
        precondition(wheelDelta(last: 50, now: 53) == 3)
        precondition(wheelDelta(last: 126, now: 2) == 4)    // wrap upwards
        precondition(wheelDelta(last: 2, now: 126) == -4)   // wrap downwards
        let (f, c) = parseCombo("cmd+shift+m")!
        precondition(c == 46 && f.contains(.maskCommand) && f.contains(.maskShift) && !f.contains(.maskControl))
        precondition(parseCombo("cmd+ö") == nil)
        precondition(parseCombo("ctrl+alt+delete") != nil)
        precondition(mediaKeys["volumeup"] == 0 && mediaKeys["mute"] == 7)
        print("selftest ok")
    }
}
