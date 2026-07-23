// buzzerd — daemon for the timeBuzzer: maps wheel/button to keyboard shortcuts
// and shell commands, with app profiles (frontmost app → profile) and LED feedback.
//
// usage: buzzerd [path/to/buzzerd.json]   (default: ./buzzerd.json)
//        buzzerd selftest
//
// Build: swiftc -O buzzerd.swift -o buzzerd

import AppKit
import CoreMIDI

struct Action: Codable { var key: String?; var shell: String? }
struct Profile: Codable {
    var led: [UInt8]?
    var press: Action?
    var release: Action?
    var wheelUp: Action?
    var wheelDown: Action?
    var touch: Action?
    var untouch: Action?
}

func log(_ s: String) { print("\(ISO8601DateFormatter().string(from: Date()))  \(s)"); fflush(stdout) }

// MARK: - Pure logic

// The wheel reports an absolute position 0–127; fix the sign when it wraps (endless encoder).
func wheelDelta(last: Int, now: Int) -> Int {
    var d = now - last
    if d > 64 { d -= 128 }
    if d < -64 { d += 128 }
    return d
}

// ponytail: US-physical key codes (ANSI). On QWERTZ, z/y are swapped —
// layout-aware mapping via UCKeyTranslate is on the roadmap.
let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "return": 36, "tab": 48, "space": 49, "delete": 51, "esc": 53, "escape": 53,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "left": 123, "right": 124, "down": 125, "up": 126,
]

func parseCombo(_ combo: String) -> (CGEventFlags, CGKeyCode)? {
    var flags = CGEventFlags()
    var code: CGKeyCode?
    for part in combo.lowercased().split(separator: "+") {
        switch part {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift":          flags.insert(.maskShift)
        case "alt", "opt", "option": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: code = keyCodes[String(part)]
        }
    }
    guard let c = code else { return nil }
    return (flags, c)
}

if CommandLine.arguments.contains("selftest") {
    assert(wheelDelta(last: 50, now: 53) == 3)
    assert(wheelDelta(last: 126, now: 2) == 4)    // wrap upwards
    assert(wheelDelta(last: 2, now: 126) == -4)   // wrap downwards
    let (f, c) = parseCombo("cmd+shift+m")!
    assert(c == 46 && f.contains(.maskCommand) && f.contains(.maskShift) && !f.contains(.maskControl))
    assert(parseCombo("cmd+ö") == nil)
    assert(parseCombo("ctrl+alt+delete") != nil)
    print("selftest ok")
    exit(0)
}

// MARK: - Config

let configPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "buzzerd.json"
var config: [String: Profile] = [:]
var configMtime = Date.distantPast

func loadConfigIfChanged() {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: configPath),
          let m = attrs[.modificationDate] as? Date, m != configMtime else { return }
    configMtime = m
    do {
        config = try JSONDecoder().decode([String: Profile].self,
                                          from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        log("config loaded (\(config.count) profiles): \(config.keys.sorted().joined(separator: ", "))")
        applyProfileLED(force: true)
    } catch { log("config error in \(configPath): \(error)") }
}

func activeProfile() -> (key: String, profile: Profile?) {
    let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "default"
    if let p = config[bid] { return (bid, p) }
    return ("default", config["default"])
}

// MARK: - MIDI

var client = MIDIClientRef()
var outPort = MIDIPortRef()
var inPort = MIDIPortRef()
var connectedSource: MIDIEndpointRef = 0
var destination: MIDIEndpointRef = 0

func endpointName(_ e: MIDIEndpointRef) -> String {
    var s: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(e, kMIDIPropertyName, &s)
    return s?.takeRetainedValue() as String? ?? ""
}

func midiSend(_ bytes: [UInt8]) {
    guard destination != 0 else { return }
    var list = MIDIPacketList()
    let packet = MIDIPacketListInit(&list)
    MIDIPacketListAdd(&list, 1024, packet, 0, bytes.count, bytes)
    MIDISend(outPort, destination, &list)
}

var lastLEDProfile = ""
func applyProfileLED(force: Bool = false) {
    let (key, profile) = activeProfile()
    guard force || key != lastLEDProfile else { return }
    lastLEDProfile = key
    guard var rgb = profile?.led else { return }
    if rgb.count == 3 { rgb = rgb + rgb + rgb }
    guard rgb.count == 9 else { log("led needs 3 or 9 values"); return }
    for (i, v) in rgb.enumerated() { midiSend([0xBB, UInt8(70 + i), min(v, 127)]) }
}

// MARK: - Aktionen

func run(_ action: Action?, _ label: String) {
    guard let action else { return }
    if let shell = action.shell {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", shell]
        do { try p.run() } catch { log("shell error (\(label)): \(error)") }
    }
    if let key = action.key {
        guard let (flags, code) = parseCombo(key) else { log("unknown key: \(key)"); return }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Events

var lastWheel: Int?
var lastTouched: Bool?

func handle(cc: UInt8, val: UInt8) {
    let profile = activeProfile().profile
    switch cc {
    case 80:
        let now = Int(val)
        defer { lastWheel = now }
        guard let last = lastWheel else { return }
        let d = wheelDelta(last: last, now: now)
        if d > 0 { run(profile?.wheelUp, "wheelUp") }
        if d < 0 { run(profile?.wheelDown, "wheelDown") }
    case 81:
        // Touch sensor, active-low; state is repeated periodically → only react to changes
        let touched = val < 64
        defer { lastTouched = touched }
        guard let last = lastTouched, touched != last else { return }
        run(touched ? profile?.touch : profile?.untouch, touched ? "touch" : "untouch")
    case 82:
        run(val == 127 ? profile?.press : profile?.release, val == 127 ? "press" : "release")
    default: break
    }
}

func connectBuzzer() {
    let source = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource)
        .first { endpointName($0).localizedCaseInsensitiveContains("timebuzzer") } ?? 0
    destination = (0..<MIDIGetNumberOfDestinations()).map(MIDIGetDestination)
        .first { endpointName($0).localizedCaseInsensitiveContains("timebuzzer") } ?? 0
    if source != 0, source != connectedSource {
        MIDIPortConnectSource(inPort, source, nil)
        connectedSource = source
        lastWheel = nil
        lastTouched = nil
        log("timeBuzzer connected")
        applyProfileLED(force: true)
    }
    if source == 0, connectedSource != 0 {
        connectedSource = 0
        log("timeBuzzer disconnected")
    }
}

// MARK: - Start

MIDIClientCreateWithBlock("buzzerd" as CFString, &client) { _ in
    DispatchQueue.main.async { connectBuzzer() } // hot-plug: re-scan on every setup change
}
MIDIOutputPortCreate(client, "out" as CFString, &outPort)
MIDIInputPortCreateWithBlock(client, "in" as CFString, &inPort) { packetList, _ in
    var packet = packetList.pointee.packet
    for _ in 0..<packetList.pointee.numPackets {
        let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
        if bytes.count >= 3, bytes[0] == 0xBB {
            DispatchQueue.main.async { handle(cc: bytes[1], val: bytes[2]) }
        }
        packet = MIDIPacketNext(&packet).pointee
    }
}

loadConfigIfChanged()
connectBuzzer()

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { _ in applyProfileLED() }

Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in loadConfigIfChanged() }

log("buzzerd running — config: \(configPath)")
RunLoop.main.run()
