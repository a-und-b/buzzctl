// buzzer.swift — use the timeBuzzer (Ideas in Logic GbR, USB MIDI) without the vendor software
//
// Usage:
//   swift buzzer.swift listen              # dump incoming MIDI events (hex + decoded)
//   swift buzzer.swift send F0 7E 7F 06 01 F7   # send raw MIDI bytes (hex) to the buzzer
//   swift buzzer.swift probe               # send LED candidates group by group (Enter = next group)
//
// ponytail: classic (deprecated) CoreMIDI packet API — works fine and is half the code.

import CoreMIDI
import Foundation

func endpointName(_ e: MIDIEndpointRef) -> String {
    var s: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(e, kMIDIPropertyName, &s)
    return s?.takeRetainedValue() as String? ?? ""
}

func buzzerSource() -> MIDIEndpointRef? {
    (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).first { endpointName($0).localizedCaseInsensitiveContains("timebuzzer") }
}
func buzzerDest() -> MIDIEndpointRef? {
    (0..<MIDIGetNumberOfDestinations()).map(MIDIGetDestination).first { endpointName($0).localizedCaseInsensitiveContains("timebuzzer") }
}

var client = MIDIClientRef()
MIDIClientCreate("buzzer-control" as CFString, nil, nil, &client)

func decode(_ bytes: [UInt8]) -> String {
    guard let status = bytes.first else { return "" }
    let ch = status & 0x0F
    switch status & 0xF0 {
    case 0x80: return "NoteOff ch\(ch) note=\(bytes[1]) vel=\(bytes[2])"
    case 0x90: return "NoteOn  ch\(ch) note=\(bytes[1]) vel=\(bytes[2])"
    case 0xB0: return "CC      ch\(ch) cc=\(bytes[1]) val=\(bytes[2])"
    case 0xC0: return "ProgChg ch\(ch) prog=\(bytes[1])"
    case 0xE0: return "PitchBend ch\(ch) val=\(Int(bytes[2]) << 7 | Int(bytes[1]))"
    case 0xF0: return status == 0xF0 ? "SysEx" : "System \(String(format: "%02X", status))"
    default:   return ""
    }
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

func send(_ bytes: [UInt8]) {
    guard let dst = buzzerDest() else { fputs("timeBuzzer destination not found\n", stderr); exit(1) }
    var port = MIDIPortRef()
    MIDIOutputPortCreate(client, "out" as CFString, &port)
    var list = MIDIPacketList()
    let packet = MIDIPacketListInit(&list)
    MIDIPacketListAdd(&list, 1024, packet, 0, bytes.count, bytes)
    MIDISend(port, dst, &list)
    usleep(20_000) // let the send buffer drain before the process may exit
}

func listen() {
    guard let src = buzzerSource() else { fputs("timeBuzzer source not found\n", stderr); exit(1) }
    var inPort = MIDIPortRef()
    MIDIInputPortCreateWithBlock(client, "in" as CFString, &inPort) { packetList, _ in
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
            let ts = ISO8601DateFormatter().string(from: Date())
            print("\(ts)  \(hex(bytes))  \(decode(bytes))")
            fflush(stdout)
            packet = MIDIPacketNext(&packet).pointee
        }
    }
    MIDIPortConnectSource(inPort, src, nil)
    print("listening on '\(endpointName(src))' — turn the wheel / press the buzzer…")
    fflush(stdout)
    RunLoop.main.run()
}

func probe() {
    // The device itself talks on channel 12 (status 0xBB) — the LED most likely listens there too.
    let groups: [(String, [[UInt8]])] = [
        ("CC ch12 0-31 val=127",   (0..<32).map   { [0xBB, UInt8($0), 127] }),
        ("CC ch12 32-63 val=127",  (32..<64).map  { [0xBB, UInt8($0), 127] }),
        ("CC ch12 64-95 val=127",  (64..<96).map  { [0xBB, UInt8($0), 127] }),
        ("CC ch12 96-127 val=127", (96..<128).map { [0xBB, UInt8($0), 127] }),
        ("NoteOn ch12 0-127 vel=127", (0..<128).map { [0x9B, UInt8($0), 127] }),
        ("SysEx manufacturer sweep F0 <id> 7F 7F 7F F7", (0..<0x7E).map { [0xF0, UInt8($0), 0x7F, 0x7F, 0x7F, 0xF7] }),
        ("All off ch12 (CC=0 + NoteOff)", (0..<128).flatMap { [[0xBB, UInt8($0), 0], [0x8B, UInt8($0), 0]] }),
    ]
    for (label, msgs) in groups {
        print("\n>> \(label) — \(msgs.count) messages. Enter = send, then watch the LED…")
        _ = readLine()
        for m in msgs { send(m); usleep(5_000) }
        print("   sent. Did the LED change? (take a note, then Enter for the next group)")
    }
}

// Steps through CCs on channel 12 one by one (on for dwellMs, then off).
// Watch the LED and note which CC number switches which color.
func scan(from: Int, to: Int, dwellMs: Int) {
    print("Reset: all CCs to 0…")
    for cc in 0..<128 { send([0xBB, UInt8(cc), 0]) }
    sleep(1)
    for cc in from...to {
        print("CC \(cc) = 127")
        fflush(stdout)
        send([0xBB, UInt8(cc), 127])
        usleep(UInt32(dwellMs) * 1000)
        send([0xBB, UInt8(cc), 0])
    }
    print("done — all back to 0.")
}

// 3 RGB LEDs (left/middle/right), each channel 0-127: CC 70-72, 73-75, 76-78 on channel 12.
// led r g b        → all 3 LEDs the same
// led r g b × 3    → LEDs individually (left middle right)
func led(_ v: [UInt8]) {
    let rgb = v.count == 3 ? v + v + v : v
    guard rgb.count == 9, rgb.allSatisfy({ $0 <= 127 }) else {
        print("usage: led r g b  |  led r g b r g b r g b   (values 0-127)"); exit(1)
    }
    for (i, val) in rgb.enumerated() { send([0xBB, UInt8(70 + i), val]) }
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "listen": listen()
case "send":   send(args.dropFirst().compactMap { UInt8($0, radix: 16) })
case "probe":  probe()
case "led":    led(args.dropFirst().compactMap { UInt8($0) })
case "scan":
    let nums = args.dropFirst().compactMap { Int($0) }
    scan(from: nums.count > 0 ? nums[0] : 0, to: nums.count > 1 ? nums[1] : 127, dwellMs: nums.count > 2 ? nums[2] : 700)
default: print("usage: swift buzzer.swift listen | send <hexbytes> | probe | scan [from] [to] [ms] | led r g b")
}
