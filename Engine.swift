// Engine.swift — shared timeBuzzer engine, used by both the buzzerd CLI and the Buzzctl app.
//
// Protocol: everything is Control Change on MIDI channel 12 (status 0xBB).
// CC 70-78 = three RGB LED zones, CC 80 = wheel (absolute, wraps),
// CC 81 = touch sensor (active-low), CC 82 = button.

import AppKit
import Combine
import CoreMIDI

struct Action: Codable, Equatable {
    var key: String? = nil
    var shell: String? = nil
}

struct Profile: Codable, Equatable {
    var led: [UInt8]? = nil
    var press: Action? = nil
    var release: Action? = nil
    var wheelUp: Action? = nil
    var wheelDown: Action? = nil
    var touch: Action? = nil
    var untouch: Action? = nil
}

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

// Named media keys — sent as system-defined events (NX_KEYTYPE_*), which
// trigger the native macOS volume/playback HUD, unlike osascript.
let mediaKeys: [String: Int32] = [
    "volumeup": 0, "volumedown": 1, "mute": 7,
    "playpause": 16, "next": 17, "previous": 18,
]

func sendMediaKey(_ key: Int32) {
    for down in [true, false] {
        let data1 = Int((key << 16) | Int32((down ? 0xa : 0xb) << 8))
        NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00),
            timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
            data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
    }
}

private func endpointName(_ e: MIDIEndpointRef) -> String {
    var s: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(e, kMIDIPropertyName, &s)
    return s?.takeRetainedValue() as String? ?? ""
}

final class BuzzerEngine: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var activeProfileKey = "default"
    @Published private(set) var config: [String: Profile] = [:]
    @Published var paused = false
    @Published private(set) var accessibilityOK = true

    let configPath: String
    var verbose = false
    /// Set by the config UI: preview this profile's LED instead of the frontmost app's.
    var ledPreviewKey: String? = nil

    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    private var inPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    private var configMtime = Date.distantPast
    private var lastWheel: Int?
    private var lastTouched: Bool?
    private var lastLEDProfile = ""

    init(configPath: String) { self.configPath = configPath }

    func log(_ s: String) { print("\(ISO8601DateFormatter().string(from: Date()))  \(s)"); fflush(stdout) }

    func start() {
        MIDIClientCreateWithBlock("buzzctl" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.connectBuzzer() } // hot-plug: re-scan on every setup change
        }
        MIDIOutputPortCreate(client, "out" as CFString, &outPort)
        MIDIInputPortCreateWithBlock(client, "in" as CFString, &inPort) { [weak self] packetList, _ in
            var packet = packetList.pointee.packet
            for _ in 0..<packetList.pointee.numPackets {
                let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
                if bytes.count >= 3, bytes[0] == 0xBB {
                    DispatchQueue.main.async { self?.handle(cc: bytes[1], val: bytes[2]) }
                }
                packet = MIDIPacketNext(&packet).pointee
            }
        }
        loadConfigIfChanged()
        connectBuzzer()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyProfileLED() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.loadConfigIfChanged()
            self?.updateAccessibilityState()
        }
        promptAccessibilityIfNeeded()
    }

    /// Force an immediate re-read of the config file (e.g. after the UI saved it).
    func reloadConfig() {
        configMtime = .distantPast
        loadConfigIfChanged()
    }

    private func loadConfigIfChanged() {
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

    private func midiSend(_ bytes: [UInt8]) {
        guard destination != 0 else { return }
        var list = MIDIPacketList()
        let packet = MIDIPacketListInit(&list)
        MIDIPacketListAdd(&list, 1024, packet, 0, bytes.count, bytes)
        MIDISend(outPort, destination, &list)
    }

    func applyProfileLED(force: Bool = false) {
        let (key, profile) = activeProfile()
        activeProfileKey = key
        var effKey = key
        var effProfile = profile
        if let pk = ledPreviewKey, let pp = config[pk] { effKey = pk; effProfile = pp }
        guard force || effKey != lastLEDProfile else { return }
        lastLEDProfile = effKey
        guard var rgb = effProfile?.led else { return }
        if rgb.count == 3 { rgb = rgb + rgb + rgb }
        guard rgb.count == 9 else { log("led needs 3 or 9 values"); return }
        for (i, v) in rgb.enumerated() { midiSend([0xBB, UInt8(70 + i), min(v, 127)]) }
    }

    private func run(_ action: Action?, _ label: String) {
        guard !paused else { return }
        guard let action else { if verbose { log("\(label): no action configured") }; return }
        log("\(label) → \(action.shell ?? "key: \(action.key ?? "?")")")
        if let shell = action.shell {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", shell]
            do { try p.run() } catch { log("shell error (\(label)): \(error)") }
        }
        if let key = action.key {
            if let mk = mediaKeys[key.lowercased()] { sendMediaKey(mk); return }
            guard let (flags, code) = parseCombo(key) else { log("unknown key: \(key)"); return }
            let src = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                e?.flags = flags
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    private func handle(cc: UInt8, val: UInt8) {
        if verbose { log("event: CC \(cc) = \(val)  (profile: \(activeProfile().key))") }
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

    private func connectBuzzer() {
        let source = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource)
            .first { endpointName($0).localizedCaseInsensitiveContains("timebuzzer") } ?? 0
        destination = (0..<MIDIGetNumberOfDestinations()).map(MIDIGetDestination)
            .first { endpointName($0).localizedCaseInsensitiveContains("timebuzzer") } ?? 0
        if source != 0, source != connectedSource {
            MIDIPortConnectSource(inPort, source, nil)
            connectedSource = source
            lastWheel = nil
            lastTouched = nil
            connected = true
            log("timeBuzzer connected")
            applyProfileLED(force: true)
        }
        if source == 0, connectedSource != 0 {
            connectedSource = 0
            connected = false
            log("timeBuzzer disconnected")
        }
    }

    private var usesKeyActions: Bool {
        config.values.contains { p in
            [p.press, p.release, p.wheelUp, p.wheelDown, p.touch, p.untouch].contains { $0?.key != nil }
        }
    }

    private func updateAccessibilityState() {
        let ok = !usesKeyActions || AXIsProcessTrusted()
        if ok != accessibilityOK { accessibilityOK = ok }
    }

    // key actions (incl. media keys) are silently dropped by macOS without the
    // Accessibility permission. Show the system prompt only once — afterwards
    // the UI surfaces the state instead of re-prompting on every launch.
    private func promptAccessibilityIfNeeded() {
        updateAccessibilityState()
        guard !accessibilityOK else { return }
        log("key actions configured but Accessibility permission is missing — grant it in System Settings → Privacy & Security → Accessibility")
        let d = UserDefaults.standard
        if !d.bool(forKey: "axPrompted") {
            d.set(true, forKey: "axPrompted")
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
    }
}
