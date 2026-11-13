import SwiftUI
import UIKit
import PhotosUI
import Photos

@main struct AukkhorApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-keyboard-system-test") {
                KeyboardSystemTestHost().ignoresSafeArea()
            } else {
                AukkhorHome()
            }
            #else
            AukkhorHome()
            #endif
        }
    }
}

#if DEBUG
// This host uses the installed keyboard extension, never inputViewController
// injection or the in-app preview. It is excluded from the distributed IPA.
private struct KeyboardSystemTestHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> KeyboardSystemTestController { KeyboardSystemTestController() }
    func updateUIViewController(_ controller: KeyboardSystemTestController, context: Context) {}
}

private final class KeyboardSystemTestController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.seamlessBackground = true
        KeyboardPreferences.numberRow = true
        KeyboardPreferences.keycapStyle = 0
        KeyboardPreferences.oneHandSide = 2
        KeyboardPreferences.heightScale = 0.9
        KeyboardPreferences.keyHeight = 43
        AukkhorSettings.defaults.synchronize()
        let background = CAGradientLayer()
        background.colors = [UIColor.systemTeal.cgColor, UIColor.systemPurple.cgColor, UIColor.systemOrange.cgColor]
        background.startPoint = .zero
        background.endPoint = CGPoint(x: 1, y: 1)
        background.frame = view.bounds
        view.layer.insertSublayer(background, at: 0)
        let field = UITextField()
        field.accessibilityIdentifier = "system-test-field"
        field.placeholder = "Type here"
        field.borderStyle = .roundedRect
        field.translatesAutoresizingMaskIntoConstraints = false
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.keyboardAppearance = .dark
        view.addSubview(field)
        let dismiss = UIButton(type: .system)
        dismiss.setTitle("Dismiss keyboard", for: .normal)
        dismiss.accessibilityIdentifier = "system-test-dismiss"
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        dismiss.addAction(UIAction { [weak self] _ in self?.view.endEditing(true) }, for: .touchUpInside)
        view.addSubview(dismiss)
        let settings = UIButton(type: .system)
        settings.setTitle("Open keyboard settings", for: .normal)
        settings.accessibilityIdentifier = "system-test-settings"
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.addAction(UIAction { _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }, for: .touchUpInside)
        view.addSubview(settings)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: view.topAnchor, constant: 120),
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            field.heightAnchor.constraint(equalToConstant: 44),
            dismiss.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 20),
            dismiss.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            settings.topAnchor.constraint(equalTo: dismiss.bottomAnchor, constant: 20),
            settings.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first?.frame = view.bounds
    }
}
#endif

@MainActor struct AukkhorHome: View {
    @StateObject private var backgroundScreenshots = BackgroundScreenshotSession()
    @ObservedObject private var screenshotClipboard = ScreenshotClipboard.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardSample = ""
    @State private var host = AukkhorSettings.host
    @State private var fingerprint = AukkhorSettings.fingerprint
    @State private var pairingCode = ""
    @State private var status = "Windows is optional. Pair only if you want PC clipboard sync or remote typing."
    @State private var clipboardSync = AukkhorSettings.syncEnabled
    @State private var keyboardTools = AukkhorSettings.keyboardClipboardEnabled
    @State private var busy = false
    @State private var lastPhone: String?
    @State private var lastWindows: String?
    @State private var keyboardPreset = KeyboardPreferences.preset
    @State private var accentColor = Color(UIColor(keyboardHex: KeyboardPreferences.customAccent))
    @State private var backgroundColor = Color(UIColor(keyboardHex: KeyboardPreferences.customBackground))
    @State private var keyColor = Color(UIColor(keyboardHex: KeyboardPreferences.customKey))
    @State private var secondaryKeyColor = Color(UIColor(keyboardHex: KeyboardPreferences.customSecondaryKey))
    @State private var textColor = Color(UIColor(keyboardHex: KeyboardPreferences.customForeground))
    @State private var keyOpacity = Double(KeyboardPreferences.keyOpacity)
    @State private var keySpacing = Double(KeyboardPreferences.keySpacing)
    @State private var touchExpansion = Double(KeyboardPreferences.touchExpansion)
    @State private var directTouchRouting = KeyboardPreferences.directTouchRouting
    @State private var heightScale = Double(KeyboardPreferences.heightScale)
    @State private var keyHeight = Double(KeyboardPreferences.keyHeight)
    @State private var oneHand = KeyboardPreferences.oneHandSide
    @State private var previewRevision = UUID()
    @State private var cornerRadius = Double(KeyboardPreferences.cornerRadius)
    @State private var haptics = KeyboardPreferences.haptics
    @State private var keySounds = KeyboardPreferences.keySounds
    @State private var keycapStyle = KeyboardPreferences.keycapStyle
    @State private var numberRow = KeyboardPreferences.numberRow
    @State private var suggestions = KeyboardPreferences.suggestions
    @State private var autocorrect = KeyboardPreferences.autocorrect
    @State private var textReplacement = KeyboardPreferences.textReplacement
    @State private var doubleSpace = KeyboardPreferences.doubleSpacePeriod
    @State private var keyPopups = KeyboardPreferences.keyPopups
    @State private var autoCaps = KeyboardPreferences.autoCapitalize
    @State private var selectedBackground: PhotosPickerItem?
    @State private var selectedClipboardImage: PhotosPickerItem?
    @State private var autoScreenshots = AukkhorSettings.defaults.bool(forKey: "autoScreenshotClipboard")
    @State private var themePhoto = KeyboardPreferences.backgroundImage
    @State private var backgroundStatus = ""
    @State private var tvHost = AukkhorTVSettings.host
    @State private var tvFingerprint = AukkhorTVSettings.fingerprint
    @State private var tvPairCode = ""
    @State private var tvStatus = "Pair with Android TV to start remote typing."
    @State private var tvAutoPrompt = AukkhorTVSettings.promptEnabled
    @State private var lastTVSession = ""
    @State private var tvPrompt: AukkhorTVPrompt?
    @State private var windowsPrompt: AukkhorTVPrompt?
    @State private var lastWindowsSession = ""
    @State private var windowsAutoPrompt = UserDefaults.standard.bool(forKey: "windowsRemotePrompt")
    @State private var windowsRemoteStatus = ""

    private var installedVersion: String {
        // Read the installed IPA's actual Info.plist, not the GitHub feed or
        // an assumed release number. CI sets CFBundleVersion per build.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version).\(build)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard responsiveness") {
                    LabeledContent("Installed version", value: installedVersion)
                    Toggle("Direct keypress handling", isOn: $directTouchRouting)
                        .onChange(of: directTouchRouting) { KeyboardPreferences.directTouchRouting = $0 }
                    VStack(alignment: .leading) {
                        Text("Touch sensitivity: \(Int(touchExpansion)) pt")
                        Slider(value: $touchExpansion, in: 0...16, step: 2)
                            .onChange(of: touchExpansion) {
                                KeyboardPreferences.touchExpansion = CGFloat($0)
                                previewRevision = UUID()
                            }
                        Text("Larger values accept taps nearer key edges. Direct handling is the new immediate touch path. Switch it off to restore normal iOS button handling. Reopen the keyboard to apply changes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Keyboard themes") {
                    Picker("Theme", selection: $keyboardPreset) {
                        ForEach(KeyboardPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .onChange(of: keyboardPreset) { KeyboardPreferences.preset = $0 }
                    if keyboardPreset == .clearGlass {
                        Text("Clear glass keys over iOS's own keyboard backdrop, which blurs the app behind it. Rims, sheen and prism fringe are drawn once and cached, so they add no typing lag. A keyboard cannot bend the app's pixels like Apple's own glass; iOS does not give extensions that access.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if keyboardPreset == .clearPrism {
                        Text("Clear glass uses iOS's refractive material with nearly invisible keycaps. A small lens highlight appears only while pressing a key, without a permanent rainbow frame or per-key glass effects.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    KeyboardThemePreview(revision: previewRevision)
                        .frame(height: KeyboardPreferences.typingHeight)
                        .listRowInsets(EdgeInsets())
                    Text("Live keyboard preview. Use ⚙ in the keyboard to change keycaps directly if your signer does not preserve shared settings.")
                        .font(.caption).foregroundStyle(.secondary)
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
                        ColorPicker("Background", selection: $backgroundColor, supportsOpacity: false)
                            .onChange(of: backgroundColor) { KeyboardPreferences.customBackground = themeHex($0) }
                        ColorPicker("Letter keys", selection: $keyColor, supportsOpacity: false)
                            .onChange(of: keyColor) { KeyboardPreferences.customKey = themeHex($0) }
                        ColorPicker("Action keys", selection: $secondaryKeyColor, supportsOpacity: false)
                            .onChange(of: secondaryKeyColor) { KeyboardPreferences.customSecondaryKey = themeHex($0) }
                        ColorPicker("Key text", selection: $textColor, supportsOpacity: false)
                            .onChange(of: textColor) { KeyboardPreferences.customForeground = themeHex($0) }
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
                                    previewRevision = UUID()
                                    backgroundStatus = "Photo saved locally. Reopen the keyboard to see it."
                                } catch { backgroundStatus = error.localizedDescription }
                            }
                        }
                        if themePhoto != nil {
                            Button("Remove background photo", role: .destructive) {
                                do {
                                    try KeyboardPreferences.removeBackgroundImage()
                                    themePhoto = nil
                                    previewRevision = UUID()
                                    backgroundStatus = "Photo removed."
                                } catch { backgroundStatus = error.localizedDescription }
                            }
                        }
                        if !backgroundStatus.isEmpty {
                            Text(backgroundStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Keycap style", selection: $keycapStyle) {
                        Text("Normal").tag(0)
                        Text("No outlines").tag(1)
                        Text("No key backgrounds").tag(2)
                    }
                    .onChange(of: keycapStyle) { KeyboardPreferences.keycapStyle = $0 }
                    glassControls
                    VStack(alignment: .leading) {
                        Text("Key roundness: \(Int(cornerRadius))")
                        Slider(value: $cornerRadius, in: 0...24, step: 1)
                            .onChange(of: cornerRadius) { KeyboardPreferences.cornerRadius = CGFloat($0) }
                        Text("Key opacity: \(Int(keyOpacity * 100))%")
                        Slider(value: $keyOpacity, in: 0.1...1)
                            .onChange(of: keyOpacity) { KeyboardPreferences.keyOpacity = CGFloat($0) }
                        Text("Key spacing: \(Int(keySpacing))")
                        Slider(value: $keySpacing, in: 2...10, step: 1)
                            .onChange(of: keySpacing) { KeyboardPreferences.keySpacing = CGFloat($0) }
                        Text("Keyboard height: \(Int(heightScale * 100))%")
                        Slider(value: $heightScale, in: 0.85...1.15, step: 0.05)
                            .onChange(of: heightScale) {
                                KeyboardPreferences.heightScale = CGFloat($0)
                                previewRevision = UUID()
                            }
                        Text("Key height: \(Int(keyHeight))")
                        Slider(value: $keyHeight, in: 36...56, step: 1)
                            .onChange(of: keyHeight) { KeyboardPreferences.keyHeight = CGFloat($0) }
                    }
                    Picker("One-handed layout", selection: $oneHand) {
                        Text("Full width").tag(0)
                        Text("Left").tag(1)
                        Text("Right").tag(2)
                    }
                    .onChange(of: oneHand) { KeyboardPreferences.oneHandSide = $0 }
                    TextField("Try your keyboard here", text: $keyboardSample)
                    Text("Text Replacement uses Settings → General → Keyboard → Text Replacement through the iOS supplementary lexicon.")
                        .font(.caption).foregroundStyle(.secondary)

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
                    Toggle("iOS text replacements", isOn: $textReplacement)
                        .onChange(of: textReplacement) { KeyboardPreferences.textReplacement = $0 }
                    Text("Autocorrect is off by default and never changes capitalization. iOS text replacements match their exact shortcut spelling and remain independent. Backspace immediately after expansion restores the shortcut. If your signer removed shared settings, use these switches in the keyboard gear menu.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Automatic capitals", isOn: $autoCaps)
                        .onChange(of: autoCaps) { KeyboardPreferences.autoCapitalize = $0 }
                    Toggle("Key popups", isOn: $keyPopups)
                        .onChange(of: keyPopups) { KeyboardPreferences.keyPopups = $0 }
                    Toggle("Double space for period", isOn: $doubleSpace)
                        .onChange(of: doubleSpace) { KeyboardPreferences.doubleSpacePeriod = $0 }
                    Text("Cursor: hold Space, or drag sideways along it, and the keyboard becomes a trackpad until you lift your finger. This replaces glide typing.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Suggestions and autocorrect use iOS's on-device spelling dictionary and your iOS text replacements. Typing is not uploaded or used for training.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Windows companion (optional)") {
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
                    Toggle("Prompt automatically for focused Windows text fields", isOn: $windowsAutoPrompt)
                        .onChange(of: windowsAutoPrompt) { enabled in
                            UserDefaults.standard.set(enabled, forKey: "windowsRemotePrompt")
                        }
                    Button("Check focused Windows field now") {
                        Task { await checkWindowsPrompt() }
                    }
                    if !windowsRemoteStatus.isEmpty {
                        Text(windowsRemoteStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Enable remote typing in the Windows Aukkhor companion. Currently native Windows Edit/RichEdit fields can auto-prompt while Aukkhor is open on iPhone. Browser fields do not auto-prompt.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Android TV keyboard · pair directly, no Windows needed") {
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
                    Text("Connect iPhone directly to the TV using its IP, fingerprint and six-digit code. Windows is NOT required. Install and select Aukkhor TV Keyboard on your Google TV. The TV detects focused fields; Aukkhor on iPhone opens the typing sheet while this app is active. iOS does not allow reliable background LAN wakeups like the Apple Watch keyboard prompt.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Forget Android TV pairing", role: .destructive) {
                        Task { await AukkhorTVLink.shared.forget() }
                        tvStatus = "TV pairing removed."
                        lastTVSession = ""
                    }
                }

                Section("Clipboard") {
                    Toggle("Automatically copy new screenshots", isOn: $autoScreenshots)
                        .onChange(of: autoScreenshots) { enabled in
                            if !enabled {
                                backgroundScreenshots.stop()
                                ScreenshotClipboard.enabled = false
                                ScreenshotClipboard.shared.stop()
                            } else {
                                Task { @MainActor in
                                    let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                                    guard autoScreenshots else { return }
                                    guard permission == .authorized || permission == .limited else {
                                        autoScreenshots = false
                                        status = "Photos access is needed to detect newly saved screenshots."
                                        return
                                    }
                                    ScreenshotClipboard.enabled = true
                                    ScreenshotClipboard.shared.start()
                                    status = permission == .authorized
                                        ? "New screenshots will be copied while Aukkhor is active or when its keyboard reopens."
                                        : "Limited Photos access only detects screenshots you have allowed Aukkhor to read."
                                }
                            }
                        }
                    Text("Enable Photos access and keyboard Full Access once. Copies only newly saved screenshots from the last two minutes. Default mode checks while Aukkhor or its keyboard is visible, or when reopened. Full Photos access is needed for all new screenshots. Background mode below is an optional experiment. Images stay on this device; files larger than 12 MB or available only in iCloud are skipped. A keyboard signer must preserve the shared App Group for this setting to reach the keyboard.")
                        .font(.caption).foregroundStyle(.secondary)
                    PhotosPicker(selection: $selectedClipboardImage, matching: .images) {
                        Label("Copy screenshot or photo", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: selectedClipboardImage) { item in
                        guard let item else { return }
                        Task {
                            do {
                                guard let data = try await item.loadTransferable(type: Data.self),
                                      let image = UIImage(data: data) else {
                                    status = "Could not load the selected image."
                                    selectedClipboardImage = nil
                                    return
                                }
                                UIPasteboard.general.image = image
                                status = "Image copied. In the destination app, touch and hold its text field and choose Paste."
                            } catch { status = "Could not copy image: \(error.localizedDescription)" }
                            selectedClipboardImage = nil
                        }
                    }
                    Text("Choose an existing screenshot or photo to copy. Image pasting depends on the destination app; the keyboard Paste button inserts text only.")
                        .font(.caption).foregroundStyle(.secondary)
                    if autoScreenshots {
                        if backgroundScreenshots.isRunning {
                            Button("Stop background screenshot experiment", role: .destructive) {
                                backgroundScreenshots.stop()
                            }
                        } else {
                            Button("Start background screenshot experiment") {
                                backgroundScreenshots.start()
                            }
                        }
                        Button("Request Always location permission") {
                            backgroundScreenshots.requestAlwaysPermission()
                        }
                        Text(backgroundScreenshots.status).font(.caption)
                        Text(screenshotClipboard.status).font(.caption)
                        Text("Experimental: uses an active background location session to try to keep screenshot observation running. Uses extra battery and shows the iOS location indicator. No coordinates are stored or uploaded. Permission alone does not keep the app alive. iOS may still stop it or reject background clipboard access. Start manually after launching; Stop ends location updates. Check the timestamp and verify by pasting in another app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Enable Windows tools in keyboard", isOn: $keyboardTools)
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

                Section("One-time codes") {
                    Button("Forward code from clipboard") { Task { await forwardCode() } }
                    Text("For SMS or Mail AutoFill, switch to Apple's keyboard. In one-time-code fields, Aukkhor offers Paste OTP from an explicitly copied code and Next keyboard. The OTP action also appears in the expanded tools rail. Aukkhor cannot independently read SMS, Mail, or Gmail. The Shortcuts action ‘Forward Code to Windows’ is separate.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Install keyboard") {
                    Text("Settings → General → Keyboard → Keyboards → Add New Keyboard → Aukkhor")
                    Text("Full Access is needed for clipboard and Windows networking. It is not needed for typing English or Bangla.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Text("App Group shared settings: \(AukkhorSettings.sharedSettingsAvailable ? "Available" : "Unavailable"). If Full Access stays off, remove Aukkhor from iOS Keyboards, add it again and enable Allow Full Access. If the switch is missing, the signed keyboard extension may be damaged; reinstall an IPA signed with the keyboard extension included.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Forget paired Windows", role: .destructive) {
                        AukkhorKeychain.remove()
                        status = "Pairing removed."
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                previewRevision = UUID()
            }
            .navigationTitle("Aukkhor · অক্ষর")
            .sheet(item: $tvPrompt) { prompt in
                TVTypingSheet(prompt: prompt, destination: .tv)
            }
            .sheet(item: $windowsPrompt) { prompt in
                TVTypingSheet(prompt: prompt, destination: .windows)
            }
        }
        .onChange(of: scenePhase) { _ in
            AukkhorSettings.refreshSharedSettings()
            if backgroundScreenshots.isRunning { backgroundScreenshots.refreshObserver() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            screenshotClipboard.screenshotCapturedInForeground()
        }
        .task(id: autoScreenshots && (scenePhase == .active || backgroundScreenshots.isRunning)) {
            if autoScreenshots && (scenePhase == .active || backgroundScreenshots.isRunning) {
                ScreenshotClipboard.shared.start(context: scenePhase == .active ? "app foreground" : "app background")
            } else { ScreenshotClipboard.shared.stop() }
        }
        .task(id: clipboardSync && scenePhase == .active) {
            guard clipboardSync && scenePhase == .active else { return }
            while !Task.isCancelled && clipboardSync && scenePhase == .active {
                await syncOnce()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task(id: windowsAutoPrompt && scenePhase == .active) {
            guard windowsAutoPrompt && scenePhase == .active else { return }
            while !Task.isCancelled && windowsAutoPrompt && scenePhase == .active {
                await checkWindowsPrompt()
                try? await Task.sleep(for: .seconds(2))
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

    @ViewBuilder private var glassControls: some View {
        Toggle("Whole keyboard glass", isOn: Binding(
            get: { KeyboardPreferences.glassEnabled },
            set: { enabled in
                KeyboardPreferences.setGlassEnabled(enabled)
                keyboardPreset = KeyboardPreferences.preset
                previewRevision = UUID()
            }))
        if KeyboardPreferences.glassEnabled {
            Toggle("Blend background with iOS", isOn: Binding(
                get: { KeyboardPreferences.seamlessBackground },
                set: { KeyboardPreferences.seamlessBackground = $0; previewRevision = UUID() }))
            if !KeyboardPreferences.seamlessBackground {
            Picker("Glass appearance", selection: Binding(
                get: { KeyboardPreferences.clearGlass },
                set: { KeyboardPreferences.clearGlass = $0; previewRevision = UUID() })) {
                Text("Frosted (adaptive)").tag(false)
                Text("Clear").tag(true)
            }
            VStack(alignment: .leading) {
                Text("Glass tint: \(Int(KeyboardPreferences.glassTintStrength * 100))%")
                Slider(value: Binding(
                    get: { Double(KeyboardPreferences.glassTintStrength) },
                    set: { KeyboardPreferences.glassTintStrength = CGFloat($0) }), in: 0...0.5)
            }
            Toggle("Glass touch response", isOn: Binding(
                get: { KeyboardPreferences.interactiveGlass },
                set: { KeyboardPreferences.interactiveGlass = $0 }))
            }
        }
        Text("Blend background with iOS uses one native keyboard background, including with Keycaps: None. Turn it off for a separate custom glass or photo surface in the typing area. iOS controls the surrounding margins and globe area; custom surfaces can have a visible edge there.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func themeHex(_ color: Color) -> String {
        let converted = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard converted.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private func checkWindowsPrompt() async {
        do {
            let prompt = try await AukkhorLink.shared.windowsPrompt()
            if prompt.active && prompt.session != lastWindowsSession {
                lastWindowsSession = prompt.session
                windowsPrompt = prompt
                windowsRemoteStatus = "Windows text field detected."
            }
        } catch {
            if windowsRemoteStatus != error.localizedDescription {
                windowsRemoteStatus = error.localizedDescription
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
        // The Windows companion currently syncs text only. Do not replace a
        // freshly copied screenshot with remote text during its polling cycle.
        guard !UIPasteboard.general.hasImages else { return }
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

// Render the actual keyboard rather than an unrelated mockup.
private struct KeyboardThemePreview: UIViewControllerRepresentable {
    let revision: UUID
    func makeUIViewController(context: Context) -> KeyboardViewController {
        let controller = KeyboardViewController()
        controller.isPreview = true
        return controller
    }
    final class Coordinator { var revision: UUID? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateUIViewController(_ controller: KeyboardViewController, context: Context) {
        guard context.coordinator.revision != revision else { return }
        context.coordinator.revision = revision
        controller.reloadAppearance()
    }
}

private enum RemoteTypingDestination { case tv, windows }

private struct TVTypingSheet: View {
    let prompt: AukkhorTVPrompt
    let destination: RemoteTypingDestination
    @Environment(\.dismiss) private var dismiss
    @FocusState private var hasFocus: Bool
    @State private var input = ""
    @State private var sending = false
    @State private var status = "Text is only sent to your paired TV when you tap Send."

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label(destination == .tv ? "TV text field detected" : "Windows text field detected",
                      systemImage: destination == .tv ? "tv" : "desktopcomputer")
                    .font(.title2.weight(.bold))
                Text(prompt.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Type on your iPhone", text: $input, axis: .vertical)
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
                    Label(sending ? "Sending…" : (destination == .tv ? "Send to TV" : "Send to Windows"),
                          systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sending || input.isEmpty)
                Text(status).font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle(destination == .tv ? "Aukkhor TV" : "Aukkhor Windows")
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
            if destination == .tv {
                try await AukkhorTVLink.shared.type(input, session: prompt.session)
            } else {
                try await AukkhorLink.shared.typeOnWindows(input, focusedSession: prompt.session)
            }
            input = ""
            status = "Sent to the focused \(destination == .tv ? "TV" : "Windows") field."
            hasFocus = true
        } catch {
            status = error.localizedDescription
        }
    }
}
