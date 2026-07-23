// BuzzctlApp — menu bar app wrapping the buzzerd engine: connection status,
// pause toggle, launch-at-login, and a graphical editor for buzzerd.json.
//
// Build: ./build.sh (assembles Buzzctl.app)

import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

@main struct BuzzctlApp: App {
    static let engine: BuzzerEngine = {
        let e = BuzzerEngine(configPath: defaultConfigPath())
        e.start()
        return e
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(engine: Self.engine)
        } label: {
            Image(systemName: "dial.medium.fill")
        }
        Window("Buzzctl", id: "config") {
            ConfigView(engine: Self.engine)
        }
        .windowResizability(.contentSize)
    }

    // The app owns its config in Application Support; the CLI keeps using ./buzzerd.json.
    static func defaultConfigPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Buzzctl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("buzzerd.json")
        if !FileManager.default.fileExists(atPath: file.path) {
            let seed = """
            {
              "default": {
                "led": [0, 40, 127],
                "press": { "key": "mute" },
                "wheelUp": { "key": "volumeup" },
                "wheelDown": { "key": "volumedown" }
              }
            }
            """
            try? seed.write(to: file, atomically: true, encoding: .utf8)
        }
        return file.path
    }
}

struct MenuContent: View {
    @ObservedObject var engine: BuzzerEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(engine.connected ? "Connected — profile: \(engine.activeProfileKey)" : "timeBuzzer not connected")
        Divider()
        Toggle("Pause", isOn: $engine.paused)
        Button("Settings…") {
            openWindow(id: "config")
            NSApp.activate(ignoringOtherApps: true)
        }
        Toggle("Launch at login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                catch { NSSound.beep() }
            }
        ))
        Divider()
        Button("Quit Buzzctl") { NSApp.terminate(nil) }
    }
}

struct ConfigView: View {
    @ObservedObject var engine: BuzzerEngine
    @State private var draft: [String: Profile] = [:]
    @State private var selected: String?
    @State private var dirty = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(sortedKeys, id: \.self) { key in
                    Text(key == "default" ? "Default (all apps)" : appName(for: key))
                }
            }
            .frame(minWidth: 190)
            .toolbar {
                Button(action: addProfile) { Image(systemName: "plus") }
                    .help("Add a profile for an app")
                Button(action: removeProfile) { Image(systemName: "minus") }
                    .disabled(selected == nil || selected == "default")
                    .help("Remove the selected profile")
            }
        } detail: {
            if let key = selected, draft[key] != nil {
                ProfileEditor(
                    profile: Binding(get: { draft[key] ?? Profile() },
                                     set: { draft[key] = $0; dirty = true }),
                    title: key == "default" ? "Default (all apps)" : appName(for: key)
                )
            } else {
                Text("Select a profile").foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(engine.configPath)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Edit JSON") { NSWorkspace.shared.open(URL(fileURLWithPath: engine.configPath)) }
                Button("Save") { save() }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .disabled(!dirty)
            }
            .padding(10)
            .background(.bar)
        }
        .frame(minWidth: 680, minHeight: 440)
        .onAppear {
            draft = engine.config
            if draft["default"] == nil { draft["default"] = Profile() }
            selected = "default"
        }
    }

    var sortedKeys: [String] {
        draft.keys.sorted { a, b in
            if a == "default" { return true }
            if b == "default" { return false }
            return appName(for: a).localizedCaseInsensitiveCompare(appName(for: b)) == .orderedAscending
        }
    }

    func appName(for bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bid
    }

    func addProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the app this profile applies to"
        guard panel.runModal() == .OK, let url = panel.url,
              let bid = Bundle(url: url)?.bundleIdentifier else { return }
        if draft[bid] == nil {
            draft[bid] = Profile(led: [127, 127, 127])
            dirty = true
        }
        selected = bid
    }

    func removeProfile() {
        guard let key = selected, key != "default" else { return }
        draft[key] = nil
        selected = "default"
        dirty = true
    }

    func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(draft).write(to: URL(fileURLWithPath: engine.configPath))
            engine.reloadConfig()
            dirty = false
        } catch { NSSound.beep() }
    }
}

struct ProfileEditor: View {
    @Binding var profile: Profile
    let title: String

    var body: some View {
        Form {
            Section {
                LabeledContent("LED color") {
                    HStack {
                        ColorPicker("", selection: ledBinding, supportsOpacity: false).labelsHidden()
                        if (profile.led?.count ?? 0) == 9 {
                            Text("per-LED colors — edit via JSON").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Events") {
                ActionRow(label: "Press", hint: "button pressed down", action: $profile.press)
                ActionRow(label: "Release", hint: "button let go", action: $profile.release)
                ActionRow(label: "Wheel up", hint: "wheel turned clockwise", action: $profile.wheelUp)
                ActionRow(label: "Wheel down", hint: "wheel turned counter-clockwise", action: $profile.wheelDown)
                ActionRow(label: "Touch", hint: "hand rests on the buzzer", action: $profile.touch)
                ActionRow(label: "Untouch", hint: "hand lifted off", action: $profile.untouch)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }

    var ledBinding: Binding<Color> {
        Binding(
            get: {
                let l = profile.led ?? [0, 0, 0]
                return Color(red: Double(l.first ?? 0) / 127,
                             green: Double(l.count > 1 ? l[1] : 0) / 127,
                             blue: Double(l.count > 2 ? l[2] : 0) / 127)
            },
            set: { c in
                let n = NSColor(c).usingColorSpace(.deviceRGB) ?? .black
                profile.led = [UInt8(n.redComponent * 127),
                               UInt8(n.greenComponent * 127),
                               UInt8(n.blueComponent * 127)]
            }
        )
    }
}

struct ActionRow: View {
    let label: String
    let hint: String
    @Binding var action: Action?

    var body: some View {
        HStack {
            Picker(label, selection: kind) {
                Text("None").tag("none")
                Text("Key").tag("key")
                Text("Shell").tag("shell")
            }
            .frame(width: 230)
            .help(hint)
            if kind.wrappedValue == "key" {
                TextField("cmd+shift+m · volumeup · space …", text: value)
                    .textFieldStyle(.roundedBorder)
            } else if kind.wrappedValue == "shell" {
                TextField("shell command", text: value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    var kind: Binding<String> {
        Binding(
            get: { action?.key != nil ? "key" : (action?.shell != nil ? "shell" : "none") },
            set: { k in
                let current = action?.key ?? action?.shell ?? ""
                switch k {
                case "key":   action = Action(key: current)
                case "shell": action = Action(shell: current)
                default:      action = nil
                }
            }
        )
    }

    var value: Binding<String> {
        Binding(
            get: { action?.key ?? action?.shell ?? "" },
            set: { v in
                if action?.key != nil { action = Action(key: v) }
                else if action?.shell != nil { action = Action(shell: v) }
            }
        )
    }
}
