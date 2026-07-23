// BuzzctlApp — menu bar app wrapping the buzzerd engine: connection status,
// pause toggle, launch-at-login, and a graphical editor for buzzerd.json.
// Settings apply immediately (macOS HIG) — no explicit save step.
//
// Build: ./build.sh (assembles Buzzctl.app)

import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

@main struct BuzzctlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

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

// Shows the onboarding window once on first launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "onboarded") else { return }
        defaults.set(true, forKey: "onboarded")
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: OnboardingView { [weak self] in self?.onboardingWindow?.close() }
        ))
        window.title = "Welcome to Buzzctl"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}

struct OnboardingView: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dial.medium.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Welcome to Buzzctl").font(.title2.bold())
            VStack(alignment: .leading, spacing: 14) {
                row("menubar.rectangle",
                    "Buzzctl lives in your menu bar",
                    "Check the connection status, pause mappings, or quit from there.")
                row("dial.medium",
                    "Turn, press, or touch your buzzer",
                    "Every input can trigger a keystroke, media key, or shell command — per app. Set it up under Settings…")
                row("lock.shield",
                    "One permission for keystrokes",
                    "Sending keystrokes needs macOS Accessibility access — you'll be asked once, and the menu will remind you if it's missing.")
            }
            .frame(maxWidth: 400)
            Button("Get Started") { close() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 470)
    }

    func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var engine: BuzzerEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(engine.connected ? "Connected — profile: \(engine.activeProfileKey)" : "timeBuzzer not connected")
        if !engine.accessibilityOK {
            Button("⚠️ Grant Accessibility Access…") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
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
    @State private var loaded = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(sortedKeys, id: \.self) { key in
                        Text(displayName(key))
                    }
                }
                Divider()
                // add/remove at the bottom of the sidebar, System Settings-style
                HStack(spacing: 4) {
                    Button(action: addProfile) { Image(systemName: "plus") }
                        .help("Add a profile for an app")
                    Button(action: removeProfile) { Image(systemName: "minus") }
                        .disabled(selected == nil || selected == "default")
                        .help("Remove the selected profile")
                    Spacer()
                    Menu {
                        Button("Edit as JSON…") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: engine.configPath))
                        }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: engine.configPath)])
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200)
        } detail: {
            if let key = selected, draft[key] != nil {
                ProfileEditor(
                    profile: Binding(get: { draft[key] ?? Profile() },
                                     set: { draft[key] = $0 }),
                    title: displayName(key)
                )
            } else {
                Text("Select a profile").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear {
            draft = engine.config
            if draft["default"] == nil { draft["default"] = Profile() }
            selected = "default"
            loaded = true
        }
        .onChange(of: draft) { _ in
            if loaded { save() } // apply immediately — no explicit save step
        }
        // While the editor is open, the LED previews the selected profile,
        // not the frontmost app's — color changes are visible for any profile.
        .onChange(of: selected) { key in
            engine.ledPreviewKey = key
            engine.applyProfileLED(force: true)
        }
        .onDisappear {
            engine.ledPreviewKey = nil
            engine.applyProfileLED(force: true)
        }
    }

    var sortedKeys: [String] {
        draft.keys.sorted { a, b in
            if a == "default" { return true }
            if b == "default" { return false }
            return displayName(a).localizedCaseInsensitiveCompare(displayName(b)) == .orderedAscending
        }
    }

    func displayName(_ key: String) -> String {
        if key == "default" { return "Default (all apps)" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return key
    }

    func addProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the app this profile applies to"
        guard panel.runModal() == .OK, let url = panel.url,
              let bid = Bundle(url: url)?.bundleIdentifier else { return }
        if draft[bid] == nil { draft[bid] = Profile(led: [127, 127, 127]) }
        selected = bid
    }

    func removeProfile() {
        guard let key = selected, key != "default" else { return }
        draft[key] = nil
        selected = "default"
    }

    func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(draft).write(to: URL(fileURLWithPath: engine.configPath))
            engine.reloadConfig()
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
                        if (profile.led?.count ?? 0) == 9 {
                            Text("per-LED colors — edit via JSON").font(.caption).foregroundStyle(.secondary)
                        }
                        ColorPicker("", selection: ledBinding, supportsOpacity: false).labelsHidden()
                    }
                }
            }
            Section("Events") {
                HStack(spacing: 8) {
                    Text("Event").frame(width: 100, alignment: .leading)
                    Text("Mode").frame(width: 150, alignment: .trailing)
                    Spacer()
                    Text("Action")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                EventRow(label: "Press", hint: "Button pressed down", action: $profile.press)
                EventRow(label: "Release", hint: "Button let go", action: $profile.release)
                EventRow(label: "Wheel Up", hint: "Wheel turned clockwise", action: $profile.wheelUp)
                EventRow(label: "Wheel Down", hint: "Wheel turned counter-clockwise", action: $profile.wheelDown)
                EventRow(label: "Touch", hint: "Hand rests on the buzzer", action: $profile.touch)
                EventRow(label: "Untouch", hint: "Hand lifted off", action: $profile.untouch)
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

struct EventRow: View {
    let label: String
    let hint: String
    @Binding var action: Action?

    var body: some View {
        // fixed columns: event | type | input (trailing)
        HStack(spacing: 8) {
            Text(label).frame(width: 100, alignment: .leading)
            Picker("", selection: kind) {
                Text("None").tag("none")
                Text("Keystroke").tag("key")
                Text("Shell Command").tag("shell")
            }
            .labelsHidden()
            .fixedSize()
            .frame(width: 150, alignment: .trailing)
            Spacer()
            if kind.wrappedValue == "key" {
                KeyPicker(combo: value)
            } else if kind.wrappedValue == "shell" {
                ShellField(command: value)
            }
        }
        .help(hint)
    }

    var kind: Binding<String> {
        Binding(
            get: { action?.key != nil ? "key" : (action?.shell != nil ? "shell" : "none") },
            set: { k in
                switch k {
                case "key":   action = Action(key: action?.key ?? "")
                case "shell": action = Action(shell: action?.shell ?? "")
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

// Edits are committed on return or when focus leaves the field — not per
// keystroke, so half-typed commands never hit the config.
struct ShellField: View {
    @Binding var command: String
    @State private var text = ""
    @State private var showHelp = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Command", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 280)
                .focused($focused)
                .onSubmit { command = text; focused = false }
                .onChange(of: focused) { f in if !f { command = text } }
                .onAppear { text = command }
                .onChange(of: command) { c in if !focused { text = c } }
            Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                .buttonStyle(.borderless)
                .help("Examples")
                .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Runs via /bin/sh — no extra permissions needed.")
                        Group {
                            Text("open -a Safari").fontDesign(.monospaced) + Text("  — open or activate an app")
                            Text("shortcuts run \"Name\"").fontDesign(.monospaced) + Text("  — run a macOS Shortcut")
                            Text("osascript -e '…'").fontDesign(.monospaced) + Text("  — AppleScript one-liner")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(12)
                }
        }
    }
}

// MARK: - Shortcut recorder

let keyNames: [CGKeyCode: String] = Dictionary(keyCodes.map { ($0.value, $0.key) },
                                               uniquingKeysWith: { a, b in min(a, b) })

let mediaKeyOptions: [(name: String, title: String)] = [
    ("volumeup", "Volume Up"), ("volumedown", "Volume Down"), ("mute", "Mute"),
    ("playpause", "Play/Pause"), ("next", "Next Track"), ("previous", "Previous Track"),
]

let keyGlyphs: [String: String] = [
    "space": "Space", "return": "↩", "tab": "⇥", "delete": "⌫", "esc": "⎋", "escape": "⎋",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
]

func prettyCombo(_ combo: String) -> String {
    if let media = mediaKeyOptions.first(where: { $0.name == combo.lowercased() }) { return media.title }
    return combo.lowercased().split(separator: "+").map { part -> String in
        switch part {
        case "cmd", "command": return "⌘"
        case "shift": return "⇧"
        case "alt", "opt", "option": return "⌥"
        case "ctrl", "control": return "⌃"
        default: return keyGlyphs[String(part)] ?? part.uppercased()
        }
    }.joined()
}

// A menu button showing the current shortcut. "Record Shortcut…" captures the
// next keystroke (esc cancels); media keys are picked from the menu directly.
struct KeyPicker: View {
    @Binding var combo: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Menu {
            Button("Record Shortcut…") { start() }
            Divider()
            ForEach(mediaKeyOptions, id: \.name) { option in
                Button(option.title) { combo = option.name }
            }
        } label: {
            Text(recording ? "Press keys… (⎋ cancels)"
                           : (combo.isEmpty ? "Record Shortcut…" : prettyCombo(combo)))
                .frame(minWidth: 130)
        }
        .fixedSize()
        .onDisappear { stop() }
    }

    func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            defer { stop() }
            let mods = ev.modifierFlags.intersection([.command, .shift, .option, .control])
            if ev.keyCode == 53, mods.isEmpty { return nil } // esc = cancel
            if let name = keyNames[ev.keyCode] {
                var parts: [String] = []
                if mods.contains(.command) { parts.append("cmd") }
                if mods.contains(.shift) { parts.append("shift") }
                if mods.contains(.option) { parts.append("alt") }
                if mods.contains(.control) { parts.append("ctrl") }
                parts.append(name)
                combo = parts.joined(separator: "+")
            }
            return nil // swallow the keystroke
        }
    }

    func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
