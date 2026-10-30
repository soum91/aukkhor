import SwiftUI
import UIKit
import PhotosUI

@main struct AukkhorApp: App {
    var body: some Scene {
        WindowGroup { AukkhorHome() }
    }
}

struct AukkhorHome: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var host = AukkhorSettings.host
    @State private var fingerprint = AukkhorSettings.fingerprint
    @State private var pairingCode = ""
    @State private var status = "Pair with your Windows companion to get started."
    @State private var clipboardSync = AukkhorSettings.syncEnabled
    @State private var keyboardTools = AukkhorSettings.keyboardClipboardEnabled
    @State private var busy = false
    @State private var lastPhone: String?
    @State private var lastWindows: String?
    @State private var keyboardPreset = KeyboardPreferences.preset
    @State private var accentColor = Color(UIColor(keyboardHex: KeyboardPreferences.customAccent))
    @State private var cornerRadius = Double(KeyboardPreferences.cornerRadius)
    @State private var haptics = KeyboardPreferences.haptics
    @State private var keySounds = KeyboardPreferences.keySounds
    @State private var numberRow = KeyboardPreferences.numberRow
    @State private var suggestions = KeyboardPreferences.suggestions
    @State private var autocorrect = KeyboardPreferences.autocorrect
    @State private var autoCaps = KeyboardPreferences.autoCapitalize
    @State private var doubleSpace = KeyboardPreferences.doubleSpacePeriod
    @State private var experimentalGlide = KeyboardPreferences.experimentalGlide
    @State private var selectedBackground: PhotosPickerItem?
    @State private var themePhoto = KeyboardPreferences.backgroundImage
    @State private var backgroundStatus = ""
    @State private var tvHost = AukkhorTVSettings.host
    @State private var tvFingerprint = AukkhorTVSettings.fingerprint
    @State private var tvPairCode = ""
    @State private var tvStatus = "Pair with Android TV to start remote typing."
    @State private var tvAutoPrompt = AukkhorTVSettings.promptEnabled
    @State private var lastTVSession = ""
    @State private var tvPrompt: AukkhorTVPrompt?

    var body: some View {
        NavigationStack {
            Form {
                Section("Windows companion") {
                    TextField("PC IPv4, e.g. 192.168.1.20", text: $host)
                        .textInputAutocapitalization(.never).keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    TextField("64-digit SHA-256 certificate fingerprint", text: $fingerprint)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Six-digit pairing code", text: $pairingCode)
                        .keyboardType(.numberPad)
                    Button(busy ? "Pairing…" : "Pair securely") { Task { await pair() } }
                        .disabled(busy)
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }

                Section("Android TV keyboard and iPhone typing") {
                    TextField("TV IPv4 (e.g. 192.168.1.50)", text: $tvHost)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    TextField("TV certificate SHA-256 fingerprint", text: $tvFingerprint)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Six-digit TV pairing code", text: $tvPairCode)
                        .keyboardType(.numberPad)
                    Button("Pair Android TV securely") {
                        Task { await pairTV() }
                    }.disabled(busy)
                    Toggle("Prompt automatically for TV text fields", isOn: $tvAutoPrompt)
                        .onChange(of: tvAutoPrompt) { enabled in
                            AukkhorTVSettings.promptEnabled = enabled
                        }
                    Button("Check TV text field now") {
                        Task { await checkTVPrompt() }
                    }
                    Text(tvStatus).font(.caption).foregroundStyle(.secondary)
                    Text("Install and select Aukkhor TV Keyboard on your Google TV. The TV detects focused fields; Aukkhor on iPhone opens the typing sheet automatically while this app is active. iOS does not allow reliable background LAN wakeups like the Apple Watch keyboard prompt.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Forget Android TV pairing", role: .destructive) {
                        Task { await AukkhorTVLink.shared.forget() }
                        tvStatus = "TV pairing removed."
                        lastTVSession = ""
                    }
                }

                Section("Clipboard") {
                    Toggle("Enable tools in keyboard", isOn: $keyboardTools)
                        .onChange(of: keyboardTools) { AukkhorSettings.keyboardClipboardEnabled = $0 }
                    Toggle("Foreground sync while this app is open", isOn: $clipboardSync)
                        .onChange(of: clipboardSync) {
                            AukkhorSettings.syncEnabled = $0
                            lastPhone = nil; lastWindows = nil
                        }
                    Button("Send iPhone clipboard to Windows") { Task { await sendClipboard() } }
                    Button("Copy Windows clipboard to iPhone") { Task { await pullClipboard() } }
                    Text("For syncing from the keyboard, explicitly tap Send or Get. iOS does not permit a third-party keyboard to run continuous background clipboard sync.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Keyboard themes") {
                    Picker("Theme", selection: $keyboardPreset) {
                        ForEach(KeyboardPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .onChange(of: keyboardPreset) { KeyboardPreferences.preset = $0 }
                    KeyboardThemePreview(preset: keyboardPreset,
                                         accent: keyboardPreset == .custom ? accentColor : nil,
                                         photo: keyboardPreset == .custom ? themePhoto : nil,
                                         cornerRadius: CGFloat(cornerRadius))
                    if keyboardPreset == .custom {
                        ColorPicker("Accent color", selection: $accentColor, supportsOpacity: false)
                            .onChange(of: accentColor) { newColor in
                                let converted = UIColor(newColor)
                                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                if converted.getRed(&r, green: &g, blue: &b, alpha: &a) {
                                    KeyboardPreferences.customAccent = String(format: "#%02X%02X%02X",
                                        Int(r * 255), Int(g * 255), Int(b * 255))
                                }
                            }
                        PhotosPicker(selection: $selectedBackground, matching: .images) {
                            Label("Choose background photo", systemImage: "photo.on.rectangle")
                        }
                        .onChange(of: selectedBackground) { item in
                            guard let item else { return }
                            Task {
                                do {
                                    guard let bytes = try await item.loadTransferable(type: Data.self),
                                          let image = UIImage(data: bytes) else {
                                        backgroundStatus = "The selected image couldn't be decoded."
                                        return
                                    }
                                    try KeyboardPreferences.setBackgroundImage(image)
                                    themePhoto = KeyboardPreferences.backgroundImage
                                    backgroundStatus = "Photo saved locally. Reopen the keyboard to see it."
                                } catch { backgroundStatus = error.localizedDescription }
                            }
                        }
                        if themePhoto != nil {
                            Button("Remove background photo", role: .destructive) {
                                do {
                                    try KeyboardPreferences.removeBackgroundImage()
                                    themePhoto = nil
                                    backgroundStatus = "Photo removed."
                                } catch { backgroundStatus = error.localizedDescription }
                            }
                        }
                        if !backgroundStatus.isEmpty {
                            Text(backgroundStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Key roundness")
                        Slider(value: $cornerRadius, in: 4...20, step: 1)
                            .onChange(of: cornerRadius) { KeyboardPreferences.cornerRadius = CGFloat($0) }
                    }
                }

                Section("Typing preferences") {
                    Toggle("Key haptics", isOn: $haptics)
                        .onChange(of: haptics) { KeyboardPreferences.haptics = $0 }
                    Toggle("Key sounds", isOn: $keySounds)
                        .onChange(of: keySounds) { KeyboardPreferences.keySounds = $0 }
                    Toggle("Dedicated number row", isOn: $numberRow)
                        .onChange(of: numberRow) { KeyboardPreferences.numberRow = $0 }
                    Toggle("Word suggestions", isOn: $suggestions)
                        .onChange(of: suggestions) { KeyboardPreferences.suggestions = $0 }
                    Toggle("Conservative autocorrect", isOn: $autocorrect)
                        .onChange(of: autocorrect) { KeyboardPreferences.autocorrect = $0 }
                    Toggle("Automatic capitals", isOn: $autoCaps)
                        .onChange(of: autoCaps) { KeyboardPreferences.autoCapitalize = $0 }
                    Toggle("Double space for period", isOn: $doubleSpace)
                        .onChange(of: doubleSpace) { KeyboardPreferences.doubleSpacePeriod = $0 }
                    Toggle("Experimental English glide typing", isOn: $experimentalGlide)
                        .onChange(of: experimentalGlide) { KeyboardPreferences.experimentalGlide = $0 }
                    Text("Glide decoding is an early local implementation, not Gboard's mature gesture model. Leave it off if it interferes with normal typing.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Suggestions use a local starter dictionary and available iOS text replacements. Typing is not uploaded or used for training.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("One-time codes") {
                    Button("Forward code from clipboard") { Task { await forwardCode() } }
                    Text("Use the Aukkhor Shortcuts action ‘Forward Code to Windows’ for text handed to it by a Messages automation, Siri, or a Share/Copy action. Aukkhor cannot independently read SMS, Mail, or Gmail.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Install keyboard") {
                    Text("Settings → General → Keyboard → Keyboards → Add New Keyboard → Aukkhor")
                    Text("Full Access is needed for clipboard and Windows networking. It is not needed for typing English or Bangla.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Forget paired Windows", role: .destructive) {
                        AukkhorKeychain.remove()
                        status = "Pairing removed."
                    }
                }
            }
            .navigationTitle("Aukkhor · অক্ষর")
            .sheet(item: $tvPrompt) { prompt in
                TVTypingSheet(prompt: prompt)
            }
        }
        .task(id: clipboardSync && scenePhase == .active) {
            guard clipboardSync && scenePhase == .active else { return }
            while !Task.isCancelled && clipboardSync && scenePhase == .active {
                await syncOnce()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task(id: tvAutoPrompt && scenePhase == .active) {
            guard tvAutoPrompt && scenePhase == .active else { return }
            while !Task.isCancelled && tvAutoPrompt && scenePhase == .active {
                await checkTVPrompt()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func storeTVEndpoint() {
        AukkhorTVSettings.host = tvHost.trimmingCharacters(in: .whitespacesAndNewlines)
        AukkhorTVSettings.fingerprint = tvFingerprint
    }

    private func pairTV() async {
        storeTVEndpoint()
        busy = true
        defer { busy = false }
        do {
            try await AukkhorTVLink.shared.pair(code: tvPairCode)
            tvPairCode = ""
            tvStatus = "TV securely paired. Open a text field on the TV."
            lastTVSession = ""
        } catch {
            tvStatus = error.localizedDescription
        }
    }

    private func checkTVPrompt() async {
        do {
            let prompt = try await AukkhorTVLink.shared.prompt()
            if prompt.active && prompt.session != lastTVSession {
                lastTVSession = prompt.session
                tvPrompt = prompt
                tvStatus = "Text field detected in \(prompt.label)"
            }
        } catch {
            if tvStatus != error.localizedDescription {
                tvStatus = error.localizedDescription
            }
        }
    }

    private func storeEndpoint() {
        AukkhorSettings.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        AukkhorSettings.fingerprint = fingerprint
    }

    private func pair() async {
        storeEndpoint()
        busy = true; defer { busy = false }
        do {
            try await AukkhorLink.shared.pair(code: pairingCode)
            pairingCode = ""
            status = "Paired. Certificate pinned and shared credentials stored."
        } catch { status = error.localizedDescription }
    }

    private func sendClipboard() async {
        do {
            guard let text = UIPasteboard.general.string else { throw AukkhorError.noClipboard }
            try await AukkhorLink.shared.sendClipboard(text)
            lastPhone = text; lastWindows = text
            status = "Sent to Windows."
        } catch { status = error.localizedDescription }
    }

    private func pullClipboard() async {
        do {
            let text = try await AukkhorLink.shared.receiveClipboard()
            UIPasteboard.general.string = text
            lastPhone = text; lastWindows = text
            status = "Copied Windows clipboard."
        } catch { status = error.localizedDescription }
    }

    private func forwardCode() async {
        do {
            guard let text = UIPasteboard.general.string else { throw AukkhorError.noClipboard }
            let code = try await AukkhorLink.shared.sendCode(from: text)
            status = "Sent code ending \(code.suffix(2)) to Windows."
        } catch { status = error.localizedDescription }
    }

    private func syncOnce() async {
        guard AukkhorKeychain.load() != nil else { return }
        do {
            let phone = UIPasteboard.general.string ?? ""
            let windows = try await AukkhorLink.shared.receiveClipboard()
            guard let oldPhone = lastPhone, let oldWindows = lastWindows else {
                lastPhone = phone; lastWindows = windows; return
            }
            if phone != oldPhone && phone != windows {
                try await AukkhorLink.shared.sendClipboard(phone)
                lastPhone = phone; lastWindows = phone
                status = "Synced iPhone → Windows"
            } else if windows != oldWindows && windows != phone {
                UIPasteboard.general.string = windows
                lastPhone = windows; lastWindows = windows
                status = "Synced Windows → iPhone"
            } else {
                lastPhone = phone; lastWindows = windows
            }
        } catch { status = "Clipboard sync paused: \(error.localizedDescription)" }
    }
}

private struct KeyboardThemePreview: View {
    let preset: KeyboardPreset
    let accent: Color?
    let photo: UIImage?
    let cornerRadius: CGFloat

    private var colors: (Color, Color, Color, Color) {
        switch preset {
        case .system: return (Color(.secondarySystemBackground), Color(.tertiarySystemBackground), .primary, .indigo)
        case .midnight: return (Color(UIColor(keyboardHex: "#101728")), Color(UIColor(keyboardHex: "#27344D")), .white, .cyan)
        case .blossom: return (Color(UIColor(keyboardHex: "#FFF0F5")), .white, .black, .pink)
        case .mint: return (Color(UIColor(keyboardHex: "#DCEFE9")), .white, .black, .green)
        case .sunset: return (Color(UIColor(keyboardHex: "#3D2145")), Color(UIColor(keyboardHex: "#634064")), .white, .orange)
        case .highContrast: return (.black, Color(white: 0.16), .white, .yellow)
        case .custom: return (Color(.secondarySystemBackground), Color(.tertiarySystemBackground), .primary, accent ?? .purple)
        }
    }

    var body: some View {
        let values = colors
        VStack(spacing: 5) {
            ForEach(["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"], id: \.self) { line in
                HStack(spacing: 4) {
                    ForEach(Array(line.enumerated()), id: \.offset) { item in
                        Text(String(item.element))
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 27)
                            .foregroundStyle(values.2)
                            .background(values.1, in: RoundedRectangle(cornerRadius: cornerRadius))
                    }
                }
            }
            Text("Space  ·  বাংলা  ·  🌐")
                .font(.caption).foregroundStyle(values.2)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(values.3.opacity(0.25), in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(values.0)
                .overlay {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Preview of \(preset.title) keyboard theme")
    }
}


private struct TVTypingSheet: View {
    let prompt: AukkhorTVPrompt
    @Environment(\.dismiss) private var dismiss
    @FocusState private var hasFocus: Bool
    @State private var input = ""
    @State private var sending = false
    @State private var status = "Text is only sent to your paired TV when you tap Send."

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("TV text field detected", systemImage: "tv")
                    .font(.title2.weight(.bold))
                Text(prompt.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Type here on your iPhone", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .focused($hasFocus)
                    .onSubmit { Task { await send() } }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    Task { await send() }
                } label: {
                    Label(sending ? "Sending…" : "Send to TV", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sending || input.isEmpty)
                Text(status).font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Aukkhor TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { hasFocus = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        guard !sending, !input.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await AukkhorTVLink.shared.type(input, session: prompt.session)
            input = ""
            status = "Sent to the focused TV field."
            hasFocus = true
        } catch {
            status = error.localizedDescription
        }
    }
}
