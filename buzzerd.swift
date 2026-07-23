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
        testGestures()
        print("selftest ok")
    }

    static func testGestures() {
        func spin(_ t: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        var fired: [String] = []
        var double = false, long = false
        let g = GestureRecognizer(doubleInterval: 0.1, longInterval: 0.2)
        g.hasDouble = { double }
        g.hasLong = { long }
        g.onSingle = { fired.append("single") }
        g.onDouble = { fired.append("double") }
        g.onLong = { fired.append("long") }

        // no gestures configured → raw: single fires immediately on down
        g.down(); precondition(fired == ["single"]); g.up()
        precondition(fired == ["single"])
        fired = []

        // double configured: lone tap fires single after the window
        double = true
        g.down(); g.up()
        precondition(fired.isEmpty)
        spin(0.15)
        precondition(fired == ["single"])
        fired = []

        // two taps inside the window → double, no single
        g.down(); g.up(); g.down()
        precondition(fired == ["double"])
        g.up(); spin(0.15)
        precondition(fired == ["double"])
        fired = []

        // long configured: hold past threshold → long, nothing on release
        double = false; long = true
        g.down(); spin(0.25)
        precondition(fired == ["long"])
        g.up()
        precondition(fired == ["long"])
        fired = []

        // long configured, quick release → single on release
        g.down(); g.up()
        precondition(fired == ["single"])
    }
}
