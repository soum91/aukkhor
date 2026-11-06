import UIKit
import AVFoundation
import Photos
import AudioToolbox

private enum InputMode: Int, CaseIterable {
    case english, phonetic, bangla
    var label: String {
        switch self { case .english: return "EN"; case .phonetic: return "বাংলা Ph"; case .bangla: return "বাংলা" }
    }
}

private struct TypingOptions {
    let haptics = KeyboardPreferences.haptics
    let hapticMode = KeyboardPreferences.hapticMode
    let sounds = KeyboardPreferences.keySounds
    let suggestions = KeyboardPreferences.suggestions
    let doubleSpace = KeyboardPreferences.doubleSpacePeriod
    let glide = KeyboardPreferences.experimentalGlide
    let autoCaps = KeyboardPreferences.autoCapitalize
}

// The user explicitly starts this trace. Keep only the touch locations/key
// labels of a short test session in memory, never persistent keystroke logs.
private struct KeyboardTouchSample {
    let key: String?
    let position: CGPoint
    let deliveryMs: Int
    let actionMs: Int
    let usedGapRouting: Bool
}

// The root probe sees touch-downs even when UIKit selects a different
// descendant than KeyboardInteractionView. Kept only during manual debugging.
private struct KeyboardRootTouchSample {
    let keyCandidate: String?
    let position: CGPoint
    let receivingView: String
    let deliveryMs: Int
}

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback, UIGestureRecognizerDelegate {
    var isPreview = false
    var previewNeedsInputModeSwitchKey = false
    private var letterButtons: [(UIButton, String)] = []
    private weak var shiftButton: UIButton?
    private weak var inputSwitcher: UIButton?
    private var mode: InputMode = .english
    private var shift = false
    private var capsLock = false
    private var lastShiftTap = Date.distantPast
    // Shift that the keyboard turned on by itself at a sentence start. A
    // manual Shift tap clears it, and the text at that moment is remembered so
    // the keyboard does not immediately turn Shift back on.
    private var autoShifted = false
    private var autoShiftDeclinedContext: String?
    private let textChecker = UITextChecker()
    private lazy var checkerLanguage: String? = {
        let available = UITextChecker.availableLanguages
        let preferred = Locale.preferredLanguages.map { $0.replacingOccurrences(of: "-", with: "_") }
        return preferred.first { $0.hasPrefix("en") && available.contains($0) }
            ?? (available.contains("en_US") ? "en_US" : available.first { $0.hasPrefix("en") })
    }()
    private var lastSpaceTap = Date.distantPast
    private var symbols = false
    private var symbolPage = 0
    private var nativeSigns = false
    private var oneHandSide = KeyboardPreferences.oneHandSide // 0 full, 1 left, 2 right
    private var settingsPanel = false
    private var emojiMode = false
    private var emojiSearch = false
    private var emojiQuery = ""
    private var emojiGroup = "Faces"
    private var clipboardPanel = false
    private var clipboardHistory: [String] = [] // Session-only; never stored or collected in the background.
    private var replacements: [String: String] = [:]
    private var dragCaretOffset = 0
    private var dragStartX: CGFloat = 0
    private var glideStartKey = ""
    private var glideKeys = ""
    private var hasPhotoBackground = false
    private var buffer = ""
    private var renderedBuffer = ""
    private let speech = AVSpeechSynthesizer()
    private let surface = UIView()
    private let backgroundImageView = UIImageView()
    // Associate feedback with the live interactive keyboard scene (iOS 26+).
    // A long-lived generator avoids reallocating the Taptic Engine per key.
    private lazy var impact: UIImpactFeedbackGenerator = {
        if #available(iOS 26.0, *) {
            return UIImpactFeedbackGenerator(style: .light, view: interactionHost)
        }
        return UIImpactFeedbackGenerator(style: .light)
    }()
    private var typingOptions = TypingOptions()
    private lazy var selectionFeedback: UISelectionFeedbackGenerator = {
        if #available(iOS 26.0, *) {
            return UISelectionFeedbackGenerator(view: interactionHost)
        }
        return UISelectionFeedbackGenerator()
    }()
    private var lastVibrationAt: TimeInterval = -1_000
    private var debugHapticRequests = 0
    private var debugVibrationRequests = 0
    private var lastAppearanceSignature: String?
    private var candidateButtons: [UIButton] = []
    private var candidateValues = [String](repeating: "", count: 3)
    private var otpActionsVisible = false
    private var otpCandidates: [OTPInbox.Candidate] = []
    private let suggestionHeading = UILabel()
    private var suggestionRequestKey: String?
    private var contextRefreshWork: DispatchWorkItem?
    private var contextRefreshGeneration = 0
    private var deleteTimer: Timer?
    private var deleteHeld = false
    private var deleteTicks = 0
    private enum SpaceTouchResult { case ordinary, doubleSpacePeriod }
    private var spaceTouchResult: SpaceTouchResult?
    private var pendingReplacement: (original: String, inserted: String, document: UUID)?
    private var suppressedReplacement: String?
    private var touchDebuggerRunning = false
    private var touchSamples: [KeyboardTouchSample] = []
    private var rootTouchSamples: [KeyboardRootTouchSample] = []
    private var debugStartStaleCount = 0
    private var debugStartEarlyRoutedCount = 0
    private var debugProxyInsertions: [String] = []
    private var debugProxyTimes: [Int] = []
    private var debugInitialContextLength: Int?
    private var debugCanvasDescription = ""
    private var touchDebugOverlay: UIView?
    private var lastTouchDebugReport = ""
    #if DEBUG
    var testingProxy: UITextDocumentProxy?
    var testingAllowTouchEvents = false
    var testingReplacements: [String: String] {
        get { replacements }
        set { replacements = newValue }
    }
    override var textDocumentProxy: UITextDocumentProxy { testingProxy ?? super.textDocumentProxy }
    func testingType(_ text: String) { type(text) }
    func testingTypeCharacter(_ character: String) { typeCharacter(character) }
    func testingTouchDownSpace() { typeSpaceFromTouchDown() }
    func testingBeginSpaceCaret() { undoSpaceForCaretMovement() }
    func testingDelete() { backspace() }
    func testingStartDelete() { startDelete() }
    func testingStopDelete() { stopDelete() }
    var testingOTPActionVisible: Bool { otpActionsVisible }
    var testingCandidateTitles: [String] { candidateValues }
    func testingInsertOTP(from text: String) -> Bool { insertOneTimeCode(from: text) }
    func testingFormatSelection(_ action: String) { if let action = SelectionFormat(rawValue: action) { formatSelection(action) } }
    func testingToggleTouchDebugger() { toggleTouchDebugger() }
    var testingTouchDebugOverlay: UIView? { touchDebugOverlay }
    #endif

    private let glassBackdrop = UIVisualEffectView(effect: nil)
    private let pressLens = KeyboardPressLensView()
    // A few reusable popups so overlapping fingers each get one.
    private let keyPopups = (0..<3).map { _ in KeyboardKeyPopupView() }
    private var keyPopupsEnabled = KeyboardPreferences.keyPopups
    private weak var highlightedLensButton: KeyboardButton?
    // Keep every control in a plain view above the decorative material. An
    // effectless UIVisualEffectView can still install private hit-test views
    // when UIKit moves a keyboard extension between remote host windows.
    private let interactionHost = KeyboardInteractionView()
    private lazy var rootTouchMonitor: KeyboardRootTouchMonitor = {
        let monitor = KeyboardRootTouchMonitor()
        monitor.cancelsTouchesInView = false
        monitor.delaysTouchesBegan = false
        monitor.delaysTouchesEnded = false
        monitor.isEnabled = false
        return monitor
    }()
    private lazy var glideRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleGlide(_:)))
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        return recognizer
    }()
    private let stack = UIStackView()
    private let contentStack = UIStackView()
    private var toolsExpanded = false
    // Height of each typing row for the current page, set by buildKeys.
    private var rowHeight = KeyboardPreferences.rowHeight
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private let suggestions = UIStackView()
    private let banner = UILabel()
    private var palette = KeyboardPalette.selected(dark: false)
    var enableInputClicks: Bool { typingOptions.sounds }

    // Apple-supported request to prioritize the rightmost and leftmost key
    // touches over system edge gestures. We never disable system recognizers.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right]
    }

    override func loadView() {
        let root = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                                   height: KeyboardPreferences.typingHeight), inputViewStyle: .default)
        root.allowsSelfSizing = true
        // All letter touches share one router view. UIKit otherwise drops
        // overlapping fingers because UIView defaults to single-touch.
        root.isMultipleTouchEnabled = true
        root.autoresizingMask = [.flexibleWidth]
        root.backgroundColor = .clear
        root.isOpaque = false
        root.accessibilityIdentifier = "aukkhor.keyboard.content"
        inputView = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.isMultipleTouchEnabled = true
        surface.accessibilityIdentifier = "keyboard.surface"
        surface.layer.cornerRadius = 20
        surface.layer.cornerCurve = .continuous
        surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        surface.clipsToBounds = true
        surface.isOpaque = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        prepareHaptic()
        surface.backgroundColor = palette.background
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(backgroundImageView)
        glassBackdrop.translatesAutoresizingMaskIntoConstraints = false
        glassBackdrop.accessibilityIdentifier = "keyboard.canvasGlass"
        glassBackdrop.layer.cornerRadius = 20
        glassBackdrop.layer.cornerCurve = .continuous
        glassBackdrop.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        glassBackdrop.clipsToBounds = true
        glassBackdrop.isUserInteractionEnabled = false
        surface.addSubview(glassBackdrop)
        pressLens.accessibilityIdentifier = "keyboard.pressLens"
        surface.addSubview(pressLens)
        interactionHost.translatesAutoresizingMaskIntoConstraints = false
        // A nearly invisible, full-size touch plate keeps the keyboard's
        // transparent styles in the remote host's composited input region.
        // Hit targets remain UIKit rectangles; no visible keycap is added.
        interactionHost.backgroundColor = .clear
        interactionHost.isOpaque = false
        interactionHost.isUserInteractionEnabled = true
        // Essential for rapid alternating/multi-finger typing: the root
        // monitor sees every touch, and this view must receive them too.
        // This is the iOS 27 touch-loss fix; keep Taptic feedback unchanged.
        interactionHost.isMultipleTouchEnabled = true
        interactionHost.accessibilityIdentifier = "keyboard.interactionHost"
        surface.addSubview(interactionHost)
        keyPopups.forEach { view.addSubview($0) }
        (view as? KeyboardInputView)?.keyRoutingView = interactionHost
        view.addGestureRecognizer(rootTouchMonitor)
        // UIKit can defer delivery to the descendant for a fraction of a
        // second, even after the root sees a key touch. Route at the earliest
        // public callback while leaving native controls and touch-up intact.
        rootTouchMonitor.onTouchBegan = { [weak self] touch in
            self?.handleRootTouchDown(touch)
        }
        // Release the key from here too: if the host swallows the touch's end
        // before it reaches the router, the key would otherwise stay latched.
        rootTouchMonitor.onTouchMoved = { [weak self] touch in
            guard let self, self.interactionHost.directTouchRoutingEnabled else { return }
            self.interactionHost.recoverMergedFinger(
                for: ObjectIdentifier(touch), at: touch.location(in: self.interactionHost),
                previous: touch.previousLocation(in: self.interactionHost))
        }
        rootTouchMonitor.onTouchEnded = { [weak self] touch, cancelled in
            guard let self else { return }
            self.interactionHost.finishTrackedDirectKey(
                for: ObjectIdentifier(touch), at: touch.location(in: self.interactionHost),
                cancelled: cancelled)
        }
        rootTouchMonitor.isEnabled = !isPreview
        NSLayoutConstraint.activate([
            glassBackdrop.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            glassBackdrop.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            glassBackdrop.topAnchor.constraint(equalTo: surface.topAnchor),
            glassBackdrop.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        NSLayoutConstraint.activate([
            interactionHost.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            interactionHost.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            interactionHost.topAnchor.constraint(equalTo: surface.topAnchor),
            interactionHost.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: surface.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        stack.axis = .vertical
        stack.spacing = KeyboardPreferences.rowGap
        contentStack.axis = .horizontal
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        interactionHost.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: interactionHost.leadingAnchor, constant: 4),
            contentStack.trailingAnchor.constraint(equalTo: interactionHost.trailingAnchor, constant: -4),
            contentStack.topAnchor.constraint(equalTo: interactionHost.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: interactionHost.bottomAnchor)
        ])
        contentStack.addArrangedSubview(stack)
        // Messages overlay the existing strip; showing one never resizes the keys.
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.font = .systemFont(ofSize: 11)
        banner.textAlignment = .center
        banner.adjustsFontSizeToFitWidth = true
        banner.layer.cornerRadius = 6
        banner.clipsToBounds = true
        banner.isHidden = true
        interactionHost.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            banner.topAnchor.constraint(equalTo: stack.topAnchor),
            banner.heightAnchor.constraint(equalToConstant: 24)
        ])
        let preferredHeight = view.heightAnchor.constraint(equalToConstant: KeyboardPreferences.typingHeight)
        preferredHeight.priority = UILayoutPriority(999)
        preferredHeight.isActive = true
        keyboardHeightConstraint = preferredHeight
        glideRecognizer.isEnabled = typingOptions.glide
        view.addGestureRecognizer(glideRecognizer)
        if !isPreview {
        requestSupplementaryLexicon { [weak self] lexicon in
            DispatchQueue.main.async {
                self?.replacements = Dictionary(lexicon.entries.map { ($0.userInput, $0.documentText) },
                                                 uniquingKeysWith: { _, newer in newer })
                self?.suggestionRequestKey = nil
                self?.refreshSuggestions()
            }
        }
        }
        buildKeys()
    }

    func reloadAppearance() {
        guard isViewLoaded else { return }
        oneHandSide = KeyboardPreferences.oneHandSide
        buildKeys()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        rootTouchMonitor.isEnabled = !isPreview || touchDebuggerRunning
        if !isPreview { applyHostAppearance() }
        AukkhorSettings.refreshSharedSettings()
        if isViewLoaded {
            if lastAppearanceSignature != KeyboardPreferences.renderingSignature {
                oneHandSide = KeyboardPreferences.oneHandSide
                buildKeys()
            }
            prepareHaptic()
            updateAutoShift()
            refreshSuggestions()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        // Reuse the canvas installed by buildKeys instead of restarting its
        // material animations every time the host presents the keyboard.
        if !isPreview, hasFullAccess { ScreenshotClipboard.shared.start() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clearTouchDebugger()
        rootTouchMonitor.isEnabled = false
        interactionHost.cancelActiveTouches()
        stopDelete()
        spaceTouchResult = nil
        if !isPreview { ScreenshotClipboard.shared.stop() }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let required = isPreview ? previewNeedsInputModeSwitchKey : needsInputModeSwitchKey
        if inputSwitcher?.isHidden == required { inputSwitcher?.isHidden = !required }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle,
           isViewLoaded { buildKeys() }
    }

    // The keyboard plate iOS draws follows the host app (Temu forces light),
    // but this extension inherits the phone's dark-mode setting. When the
    // field declares an appearance, use it so labels match the plate.
    private func applyHostAppearance() {
        let style: UIUserInterfaceStyle
        switch textDocumentProxy.keyboardAppearance ?? .default {
        case .dark: style = .dark
        case .light: style = .light
        default: style = .unspecified
        }
        if overrideUserInterfaceStyle != style { overrideUserInterfaceStyle = style }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyHostAppearance()
        // A host can move the caret or rewrite the field at any time.
        if !renderedBuffer.isEmpty && !(textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(renderedBuffer) {
            buffer = ""; renderedBuffer = ""
        }
        updateAutoShift()
        refreshSuggestions()
    }

    private func prepareHaptic() {
        guard typingOptions.haptics else { return }
        switch typingOptions.hapticMode {
        case .impact: impact.prepare()
        case .selection: selectionFeedback.prepare()
        case .vibration: break
        }
    }

    // A keyboard extension can request UIKit feedback even when iOS declines
    // to play it. Offer an explicit, documented vibration alternative without
    // automatically replacing a subtle click with a full-strength alert.
    private func triggerHaptic(force: Bool = false) {
        guard force || typingOptions.haptics else { return }
        if touchDebuggerRunning { debugHapticRequests += 1 }
        switch typingOptions.hapticMode {
        case .impact:
            impact.impactOccurred(intensity: 0.85)
            impact.prepare()
        case .selection:
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
        case .vibration:
            let now = ProcessInfo.processInfo.systemUptime
            // Alert vibration lasts longer than a Taptic tap; do not stack
            // overlapping vibration requests during fast typing.
            guard now - lastVibrationAt >= 0.18 else { return }
            lastVibrationAt = now
            if touchDebuggerRunning { debugVibrationRequests += 1 }
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        }
    }

    private func feedback() {
        triggerHaptic()
        if typingOptions.sounds { UIDevice.current.playInputClick() }
    }

    private var acceptsTouchInput: Bool {
        #if DEBUG
        return !isPreview || testingAllowTouchEvents
        #else
        return !isPreview
        #endif
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard typingOptions.glide, mode == .english,
              !symbols, !emojiMode, !clipboardPanel,
              let key = (touch.view as? UIButton)?.title(for: .normal),
              key.count == 1, key.first?.isLetter == true else { return false }
        glideStartKey = key.lowercased()
        return true
    }

    @objc private func handleGlide(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            glideKeys = glideStartKey
        case .changed:
            let point = recognizer.location(in: view)
            if let button = view.hitTest(point, with: nil) as? UIButton,
               let text = button.title(for: .normal), text.count == 1,
               text.first?.isLetter == true, glideKeys.count < 80,
               glideKeys.last != text.lowercased().first {
                glideKeys += text.lowercased()
            }
        case .ended:
            if let word = KeyboardSuggestions.glideCandidate(for: glideKeys) {
                commitBuffer()
                textDocumentProxy.insertText(word + " ")
                show("Glide: \(word)")
            } else if glideKeys.count > 2 {
                show("No reliable glide match. Try tapping or a shorter swipe.")
            }
            glideKeys = ""
            refreshSuggestions()
        case .cancelled, .failed:
            glideKeys = ""
        default: break
        }
    }

    private func makeButton(_ title: String, action: @escaping () -> Void,
                            foreground: UIColor = .label, weight: CGFloat = 1, surface: Bool = true,
                            immediateInput: Bool = false) -> UIButton {
        let button = KeyboardButton(type: .custom)
        button.insertsOnTouchDown = immediateInput || title == "⌫"
        button.touchExpansion = KeyboardPreferences.touchExpansion
        // Clear Prism now belongs to the single keyboard-wide glass shell.
        // Do not draw a separate bubble around each pressed letter.
        button.usesPressLens = false
        if button.usesPressLens {
            button.onHighlightChanged = { [weak self] highlighted, key in
                self?.updatePressLens(for: key, highlighted: highlighted)
            }
        }
        button.setTitle(title, for: .normal)
        // Pop up typed characters, not controls (Shift, Delete, Space, 123...).
        if immediateInput, title.count == 1, !["⇧", "⇪", "⌫", "😊", "🌐", "⚙"].contains(title) {
            button.onHighlightChanged = { [weak self] highlighted, key in
                self?.updateKeyPopup(for: key, highlighted: highlighted)
            }
        }
        let symbols = ["⇧": "shift", "⇪": "shift.fill", "⌫": "delete.left",
                       "return": "return", "🌐": "globe", "😊": "face.smiling", "⚙": "gearshape"]
        if let name = symbols[title], let icon = UIImage(systemName: name) {
            button.setTitle(nil, for: .normal)
            button.setImage(icon, for: .normal)
            button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .regular), forImageIn: .normal)
            button.tintColor = palette.foreground
        }
        button.titleLabel?.font = .systemFont(ofSize: title.count > 3 ? 14 : 23, weight: .regular)
        button.setTitleColor(foreground == .label ? palette.foreground : foreground, for: .normal)
        if surface { KeyboardKeyAppearance.apply(to: button, palette: palette) }
        button.accessibilityLabel = title
        if title == "⌫" {
            let beginDelete = { [weak self, weak button] in
                guard let self, self.acceptsTouchInput, let button,
                      !button.immediateActionTriggered else { return }
                button.immediateActionTriggered = true
                self.startDelete()
                self.feedback()
            }
            button.addAction(UIAction { [weak self] _ in
                guard self?.acceptsTouchInput == true else { return }
                beginDelete()
            }, for: .touchDown)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, self.acceptsTouchInput else { return }
                // Accessibility activation can send only touchUpInside.
                if !self.deleteHeld { self.backspace() }
                self.stopDelete()
                button?.immediateActionTriggered = false
            }, for: .touchUpInside)
            button.addAction(UIAction { [weak self, weak button] _ in
                self?.stopDelete()
                button?.immediateActionTriggered = false
            },
                             for: [.touchUpOutside, .touchCancel])
        } else if immediateInput {
            let beginInput = { [weak self, weak button] in
                guard let self, self.acceptsTouchInput, let button,
                      !button.immediateActionTriggered else { return }
                button.immediateActionTriggered = true
                action()
                self.feedback()
            }
            button.addAction(UIAction { [weak self, weak button] _ in
                guard self?.acceptsTouchInput == true else { return }
                beginInput()
            }, for: .touchDown)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, self.acceptsTouchInput else { return }
                if button?.immediateActionTriggered != true { action(); self.feedback() }
                button?.immediateActionTriggered = false
            }, for: .touchUpInside)
            button.addAction(UIAction { [weak button] _ in button?.immediateActionTriggered = false },
                             for: [.touchUpOutside, .touchCancel])
            if title == "Space" {
                button.addAction(UIAction { [weak self] _ in self?.spaceTouchResult = nil },
                                 for: [.touchUpInside, .touchUpOutside])
            }
        } else {
            button.addAction(UIAction(identifier: UIAction.Identifier("aukkhor.tap")) { [weak self] _ in guard self?.acceptsTouchInput == true else { return }; action(); self?.feedback() }, for: .touchUpInside)
        }
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return button
    }

    private func updateKeyPopup(for key: KeyboardButton, highlighted: Bool) {
        guard keyPopupsEnabled else { return }
        if highlighted {
            let popup = keyPopups.first { $0.key === key }
                ?? keyPopups.first { $0.isHidden }
                ?? keyPopups.min { $0.shownAt < $1.shownAt }!
            popup.shownAt = ProcessInfo.processInfo.systemUptime
            view.bringSubviewToFront(popup)
            popup.show(for: key, keyFrame: key.convert(key.bounds, to: view), in: view.bounds,
                       dark: traitCollection.userInterfaceStyle == .dark)
        } else if let popup = keyPopups.first(where: { $0.key === key }) {
            // Keep a quick tap visible for at least ~90 ms so it registers.
            let shown = popup.shownAt
            let wait = max(0, 0.09 - (ProcessInfo.processInfo.systemUptime - shown))
            if wait == 0 { popup.hide(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak popup] in
                guard let popup, popup.shownAt == shown, popup.key?.isHighlighted != true else { return }
                popup.hide()
            }
        }
    }

    private func updatePressLens(for key: KeyboardButton, highlighted: Bool) {
        if highlighted {
            highlightedLensButton = key
            pressLens.display(over: key.convert(key.bounds, to: surface))
        } else if highlightedLensButton === key {
            highlightedLensButton = nil
            pressLens.isHidden = true
        }
    }

    private func row(_ items: [(String, () -> Void)], immediateInput: Bool = false) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = KeyboardPreferences.keySpacing
        for item in items { row.addArrangedSubview(makeButton(item.0, action: item.1, immediateInput: immediateInput)) }
        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        return row
    }

    private func typeCharacter(_ character: String) {
        if mode != .bangla && !symbols && !emojiMode && character.first?.isLetter == true {
            type(shift ? character.uppercased() : character.lowercased())
        } else { type(character) }
    }

    private func rememberLetters(_ chars: [String], in row: UIStackView) {
        guard !symbols, mode != .bangla, !emojiMode else { return }
        for (character, view) in zip(chars, row.arrangedSubviews) {
            if character.count == 1, character.first?.isLetter == true, let button = view as? UIButton {
                letterButtons.append((button, character.lowercased()))
            }
        }
    }

    private func refreshShiftKeys() {
        UIView.performWithoutAnimation {
        for (button, lowercase) in letterButtons {
            let title = shift ? lowercase.uppercased() : lowercase
            button.setTitle(title, for: .normal)
            button.accessibilityLabel = title
        }
        shiftButton?.setImage(UIImage(systemName: capsLock ? "shift.fill" : "shift"), for: .normal)
        shiftButton?.tintColor = shift ? palette.accent : palette.foreground
        }
    }

    private func addChars(_ chars: [String]) {
        let keys = row(chars.map { letter in
            (letter, { [weak self] in self?.typeCharacter(letter) })
        }, immediateInput: true)
        rememberLetters(chars, in: keys)
        // Match the staggered QWERTY geometry of the system keyboard.
        // Insets belong outside the key row so every key retains equal touch width.
        let englishLetters = !symbols && mode != .bangla &&
            chars.allSatisfy { $0.count == 1 && $0.first?.isLetter == true }
        if englishLetters && chars.count == 9 {
            // Half one key pitch at either side, scales with portrait/landscape/one-hand width.
            let wrapper = UIView()
            keys.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(keys)
            NSLayoutConstraint.activate([
                keys.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                keys.widthAnchor.constraint(equalTo: wrapper.widthAnchor, multiplier: 0.9,
                                            constant: -KeyboardPreferences.keySpacing * 0.1),
                keys.topAnchor.constraint(equalTo: wrapper.topAnchor),
                keys.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
            ])
            stack.addArrangedSubview(oneHandRow(wrapper))
        } else {
            stack.addArrangedSubview(oneHandRow(keys))
        }
    }

    // Third symbol row, matching the system keyboard on both pages:
    // [#+= or 123]  .  ,  ?  !  '  [delete]
    private func addSymbolsThirdRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = KeyboardPreferences.keySpacing
        row.distribution = .fill
        let morePage = symbolPage == 0
        let toggle = makeButton(morePage ? "#+=" : "123", action: { [weak self] in
            guard let self else { return }
            self.symbolPage = morePage ? 1 : 0
            self.buildKeys()
        })
        toggle.accessibilityLabel = morePage ? "More symbols" : "Numbers"
        toggle.titleLabel?.font = .systemFont(ofSize: 15)
        KeyboardKeyAppearance.apply(to: toggle, palette: palette, secondary: true)
        row.addArrangedSubview(toggle)
        let punctuation = UIStackView()
        punctuation.axis = .horizontal
        punctuation.distribution = .fillEqually
        punctuation.spacing = KeyboardPreferences.keySpacing
        for symbol in [".", ",", "?", "!", "'"] {
            punctuation.addArrangedSubview(makeButton(symbol, action: { [weak self] in self?.type(symbol) },
                                                      immediateInput: true))
        }
        let leftGap = UIView(), rightGap = UIView()
        row.addArrangedSubview(leftGap)
        row.addArrangedSubview(punctuation)
        row.addArrangedSubview(rightGap)
        let deleteKey = makeButton("⌫", action: { [weak self] in self?.backspace() })
        deleteKey.accessibilityLabel = "Delete"
        KeyboardKeyAppearance.apply(to: deleteKey, palette: palette, secondary: true)
        row.addArrangedSubview(deleteKey)
        NSLayoutConstraint.activate([
            toggle.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.15),
            deleteKey.widthAnchor.constraint(equalTo: toggle.widthAnchor),
            leftGap.widthAnchor.constraint(equalTo: rightGap.widthAnchor)
        ])
        // Narrow one-handed widths cannot fit the gaps; let them collapse.
        let punctuationWidth = punctuation.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.62)
        punctuationWidth.priority = UILayoutPriority(999)
        punctuationWidth.isActive = true
        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        stack.addArrangedSubview(oneHandRow(row))
    }

    private func addThirdRow(_ chars: [String]) {
        let container = UIStackView()
        container.spacing = 0
        // Shift acts on finger-down like the system keyboard. Fast typists
        // press the letter before lifting Shift; on touch-up that letter
        // was already typed in lowercase.
        let shiftKey = makeButton(capsLock ? "⇪" : "⇧", action: { [weak self] in
            self?.tapShift()
        }, immediateInput: true)
        shiftKey.accessibilityLabel = "Shift"
        shiftButton = shiftKey
        let deleteKey = makeButton("⌫", action: { [weak self] in self?.backspace() })
        deleteKey.accessibilityLabel = "Delete"
        let letters = row(chars.map { letter in (letter, { [weak self] in self?.typeCharacter(letter) }) },
                          immediateInput: true)
        rememberLetters(chars, in: letters)
        let leftGap = UIView(), rightGap = UIView()
        container.addArrangedSubview(shiftKey)
        container.addArrangedSubview(leftGap)
        container.addArrangedSubview(letters)
        container.addArrangedSubview(rightGap)
        container.addArrangedSubview(deleteKey)
        NSLayoutConstraint.activate([
            shiftKey.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.12),
            deleteKey.widthAnchor.constraint(equalTo: shiftKey.widthAnchor),
            letters.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.7,
                                           constant: -KeyboardPreferences.keySpacing * 0.3),
            leftGap.widthAnchor.constraint(equalTo: rightGap.widthAnchor)
        ])
        KeyboardKeyAppearance.apply(to: shiftKey, palette: palette, secondary: true)
        KeyboardKeyAppearance.apply(to: deleteKey, palette: palette, secondary: true)
        stack.addArrangedSubview(oneHandRow(container))
    }

    private func oneHandRow(_ keys: UIView) -> UIView { keys }

    private func configureToolsRail() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            if $0 !== stack { $0.removeFromSuperview() }
        }
        guard oneHandSide != 0 || toolsExpanded else {
            contentStack.addArrangedSubview(stack)
            return
        }
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        // iOS 26 frosts the top and bottom of every scroll view. In this
        // narrow column that smeared the first tool into a grey square.
        if #available(iOS 26.0, *) {
            scroll.topEdgeEffect.isHidden = true
            scroll.bottomEdgeEffect.isHidden = true
        }
        let tools = UIStackView()
        tools.axis = .vertical
        tools.spacing = 6
        tools.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(tools)
        if oneHandSide != 1 { contentStack.addArrangedSubview(scroll) }
        contentStack.addArrangedSubview(stack)
        if oneHandSide == 1 { contentStack.addArrangedSubview(scroll) }
        NSLayoutConstraint.activate([
            tools.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            tools.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            tools.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            tools.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 0.18)
        ])
        let controls: [(String, () -> Void)] = [
            ("⚙", { [weak self] in self?.openHostApp() }),
            ("Paste", { [weak self] in self?.paste() }),
            ("OTP", { [weak self] in self?.pasteOneTimeCode() }),
            ("Cut", { [weak self] in self?.cut() }),
            ("Define", { [weak self] in self?.define() }),
            ("Speak", { [weak self] in self?.speak() }),
            ("Clips", { [weak self] in self?.toggleClipboardPanel() }),
            ("⇥PC", { [weak self] in self?.sendClipboardToPC() }),
            ("PC⇤", { [weak self] in self?.getClipboardFromPC() }),
            ("↔", { [weak self] in self?.oneHandSide = 0; KeyboardPreferences.oneHandSide = 0; self?.toolsExpanded = false; self?.buildKeys() })
        ]
        for (title, action) in controls {
            let button = makeButton(title, action: action)
            if title == "⚙" {
                button.accessibilityLabel = "Open Aukkhor"
                button.accessibilityHint = "Opens the Aukkhor app"
            }
            button.titleLabel?.font = .systemFont(ofSize: title.count > 1 ? 11 : 20)
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            tools.addArrangedSubview(button)
        }

    }

    // Keyboard extensions have no public openURL. The host's UIApplication is
    // still in the responder chain, so send it openURL:options:completionHandler:
    // directly (the selector Apple keeps for apps).
    private func openHostApp() {
        guard let url = URL(string: "aukkhor://settings") else { return }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: UIApplication.self), current.responds(to: selector),
               let method = current.method(for: selector) {
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(method, to: OpenURL.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
        show("Open the Aukkhor app from the Home Screen")
    }

    private func cycleOneHand() {
        oneHandSide = (oneHandSide + 1) % 3
        KeyboardPreferences.oneHandSide = oneHandSide
        buildKeys()
    }

    private func stripButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = makeButton(title, action: action, surface: false)
        button.backgroundColor = .clear
        button.layer.borderWidth = 0
        button.layer.shadowOpacity = 0
        button.subviews.filter { $0.tag == 9401 }.forEach { $0.removeFromSuperview() }
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.6
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 16), forImageIn: .normal)
        let width = button.widthAnchor.constraint(equalToConstant: 30)
        width.priority = .defaultHigh // Hidden input switcher collapses without a constraint conflict.
        width.isActive = true
        return button
    }

    private func buildTopStrip() -> UIStackView {
        let strip = UIStackView()
        strip.axis = .horizontal
        strip.spacing = 3
        strip.accessibilityIdentifier = "keyboard.topStrip"
        strip.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let globe = stripButton("🌐", action: {})
        globe.accessibilityLabel = "Next keyboard"
        globe.removeAction(identifiedBy: UIAction.Identifier("aukkhor.tap"), for: .touchUpInside)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.isHidden = !(isPreview ? previewNeedsInputModeSwitchKey : needsInputModeSwitchKey)
        inputSwitcher = globe
        strip.addArrangedSubview(globe)
        suggestions.axis = .horizontal
        suggestions.distribution = .fillEqually
        suggestions.spacing = 4
        installSuggestionControls()
        strip.addArrangedSubview(suggestions)
        // Text tools live in the existing 24pt strip. Never add a keyboard row
        // or alter the expanded Settings panel to accommodate them.
        let format = stripButton("Aa", action: {})
        format.accessibilityLabel = "Format selected text"
        installFormatMenu(on: format)
        strip.addArrangedSubview(format)
        strip.addArrangedSubview(stripButton(mode.label, action: { [weak self] in self?.cycleMode() }))
        let hand = stripButton("↔", action: {})
        hand.accessibilityLabel = "One-handed layout"
        hand.menu = UIMenu(title: "One-handed layout", children: [("Left", 1), ("Full width", 0), ("Right", 2)].map { title, side in
            UIAction(title: title, state: oneHandSide == side ? .on : .off) { [weak self] _ in
                self?.oneHandSide = side; KeyboardPreferences.oneHandSide = side; self?.buildKeys()
            }
        })
        hand.showsMenuAsPrimaryAction = true
        strip.addArrangedSubview(hand)
        let settingsGear = stripButton("⚙", action: { [weak self] in
            self?.toggleAppearancePanel()
        })
        settingsGear.accessibilityLabel = "Keyboard settings"
        let debugHold = UILongPressGestureRecognizer(target: self, action: #selector(holdForTouchDebugger(_:)))
        debugHold.minimumPressDuration = 0.55
        settingsGear.addGestureRecognizer(debugHold)
        settingsGear.accessibilityHint = "Tap for settings or hold to run the touch debugger"
        strip.addArrangedSubview(settingsGear)
        return strip
    }

    private func buildKeys() {
        interactionHost.cancelActiveTouches()
        stopDelete()
        highlightedLensButton = nil
        pressLens.isHidden = true
        keyPopups.forEach { $0.hide() }
        keyPopupsEnabled = KeyboardPreferences.keyPopups
        lastAppearanceSignature = KeyboardPreferences.renderingSignature
        typingOptions = TypingOptions()
        glideRecognizer.isEnabled = typingOptions.glide
        interactionHost.touchExpansion = KeyboardPreferences.touchExpansion
        // Invisible keycaps must not make the entire keyboard surface vanish
        // from the extension host's composited touch region. This very faint
        // fill is on the shared plate, never on individual keys.
        interactionHost.backgroundColor = KeyboardPreferences.keycapStyle == 0
            ? .clear : UIColor.systemBackground.withAlphaComponent(0.016)
        interactionHost.directTouchRoutingEnabled = !isPreview && !typingOptions.glide && KeyboardPreferences.directTouchRouting
        suggestionRequestKey = nil
        palette = KeyboardPalette.selected(dark: traitCollection.userInterfaceStyle == .dark)
        letterButtons.removeAll()
        shiftButton = nil
        // With the number row on, the keyboard is sized for five rows. Symbol
        // pages have four (their first row is already numbers), so share the
        // spare row evenly instead of letting the bottom row swallow it.
        let baseRow = KeyboardPreferences.rowHeight
        rowHeight = symbols && !emojiMode && !clipboardPanel && !settingsPanel && KeyboardPreferences.numberRow
            ? baseRow + (baseRow + KeyboardPreferences.rowGap) / 4
            : baseRow
        KeyboardCanvasAppearance.apply(to: glassBackdrop, surface: surface, palette: palette)
        backgroundImageView.image = KeyboardPreferences.preset == .custom ? KeyboardPreferences.backgroundImage : nil
        backgroundImageView.isHidden = KeyboardPreferences.usesSystemCanvas
        hasPhotoBackground = backgroundImageView.image != nil
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        configureToolsRail()
        stack.addArrangedSubview(buildTopStrip())
        if settingsPanel {
            buildAppearancePanel()
        } else if clipboardPanel {
            buildClipboardPanel()
        } else if emojiMode {
            buildEmojiPanel()
        } else if symbols {
            if symbolPage == 0 {
                addChars(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
                addChars(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
            } else {
                addChars(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
                addChars(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"])
            }
            addSymbolsThirdRow()
        } else if mode == .bangla {
            if KeyboardPreferences.numberRow { addChars(["১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "০"]) }
            if nativeSigns {
                addChars(["অ", "আ", "ই", "ঈ", "উ", "ঊ", "ঋ", "এ", "ঐ", "ও", "ঔ"])
                addChars(["া", "ি", "ী", "ু", "ূ", "ৃ", "ে", "ৈ", "ো", "ৌ", "্"])
                addChars(["ং", "ঃ", "ঁ", "ৎ", "ড়", "ঢ়", "য়", "০", "১", "২"])
            } else {
                addChars(["ক", "খ", "গ", "ঘ", "ঙ", "চ", "ছ", "জ", "ঝ", "ঞ"])
                addChars(["ট", "ঠ", "ড", "ঢ", "ণ", "ত", "থ", "দ", "ধ", "ন"])
                addChars(["প", "ফ", "ব", "ভ", "ম", "য", "র", "ল", "শ", "স", "ষ", "হ"])
            }
        } else {
            if KeyboardPreferences.numberRow { addChars(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]) }
            for line in ["qwertyuiop", "asdfghjkl"] {
                addChars(line.map { String(shift ? $0.uppercased() : String($0)) })
            }
            addThirdRow("zxcvbnm".map { shift ? $0.uppercased() : String($0) })
        }
        // Symbol pages carry their own Delete in the third row, like iOS.
        let needsEditingKeys = !symbols && (mode == .bangla || emojiMode || clipboardPanel || settingsPanel)
        var bottomControls: [(String, () -> Void)] = [
            (symbols ? "ABC" : "123", { [weak self] in
                guard let self else { return }
                self.commitBuffer()
                if self.symbols { self.symbols = false; self.symbolPage = 0 }
                else { self.symbols = true; self.symbolPage = 0 }
                self.emojiMode = false
                self.clipboardPanel = false; self.settingsPanel = false; self.buildKeys()
            }),
            ("😊", { [weak self] in self?.toggleEmoji() }),
            ("Space", { [weak self] in self?.typeSpaceFromTouchDown() }),
            ("return", { [weak self] in self?.type("\n") })
        ]
        if needsEditingKeys {
            bottomControls.insert(("⌫", { [weak self] in self?.backspace() }), at: 3)
        }
        if mode == .bangla && !symbols && !emojiMode && !clipboardPanel && !settingsPanel {
            bottomControls.insert((nativeSigns ? "ব্যঞ্জন" : "স্বর", { [weak self] in
                self?.nativeSigns.toggle(); self?.buildKeys()
            }), at: 1)
        }
        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = KeyboardPreferences.keySpacing
        bottom.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        for (label, action) in bottomControls {
            let button = makeButton(label, action: action,
                                    immediateInput: label == "Space" || label == "return")
            bottom.addArrangedSubview(button)
            if label == "Space" {
                button.setTitle(mode == .english ? "space" : mode.label, for: .normal)
                button.accessibilityLabel = "Space"
                button.titleLabel?.font = .systemFont(ofSize: 16)
                button.setContentHuggingPriority(.defaultLow, for: .horizontal)
                let gesture = UILongPressGestureRecognizer(target: self, action: #selector(moveCaret(_:)))
                gesture.minimumPressDuration = 0.35
                button.addGestureRecognizer(gesture)
            } else {
                button.widthAnchor.constraint(equalTo: bottom.widthAnchor,
                    multiplier: label == "return" ? 0.24 : 0.12).isActive = true
                button.titleLabel?.font = .systemFont(ofSize: label == "😊" ? 23 : 15)
                KeyboardKeyAppearance.apply(to: button, palette: palette, secondary: true)
            }
        }
        stack.addArrangedSubview(oneHandRow(bottom))
        banner.text = nil
        banner.isHidden = true
        refreshShiftKeys()
        updateAutoShift()
        refreshSuggestions()
        // Fit settings/emoji content without a separate hard-coded panel height.
        let availableWidth = max(160, view.bounds.width - 8)
        let keyWidth = oneHandSide == 0 && !toolsExpanded ? availableWidth : availableWidth * 0.82 - 6
        let contentHeight = stack.systemLayoutSizeFitting(
            CGSize(width: keyWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let height = max(KeyboardPreferences.typingHeight, contentHeight)
        keyboardHeightConstraint?.constant = height
        (inputView as? KeyboardInputView)?.contentHeight = height
    }

    private func colorControl(_ title: String, set: @escaping (String) -> Void) -> UIButton {
        let button = makeButton(title, action: {})
        button.titleLabel?.font = .systemFont(ofSize: 12)
        let colors = [("Black", "#000000"), ("White", "#FFFFFF"), ("Graphite", "#35363C"),
                      ("Blue", "#2155CD"), ("Purple", "#714AC4"), ("Pink", "#E783AA"),
                      ("Mint", "#79C6AD"), ("Gold", "#E3BE62")]
        button.menu = UIMenu(title: title, children: colors.map { name, hex in
            UIAction(title: name) { [weak self] _ in
                set(hex); KeyboardPreferences.preset = .custom; self?.buildKeys()
            }
        })
        button.showsMenuAsPrimaryAction = true
        return button
    }

    func toggleAppearancePanel() {
        if oneHandSide == 0 { toolsExpanded = !settingsPanel }
        settingsPanel.toggle()
        buildKeys()
    }

    @objc private func holdForTouchDebugger(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        toggleTouchDebugger()
    }

    private func toggleTouchDebugger() {
        if touchDebugOverlay != nil { clearTouchDebugger(); return }
        if touchDebuggerRunning { finishTouchDebugger() }
        else { startTouchDebugger() }
    }

    private func handleRootTouchDown(_ touch: UITouch) {
        // The root hit-test returns interactionHost for direct letter keys.
        // Do not intercept Space, settings, keyboard switching, or overlays.
        if touch.view === interactionHost, interactionHost.directTouchRoutingEnabled {
            let position = touch.location(in: interactionHost)
            interactionHost.beginTrackedDirectKey(
                for: ObjectIdentifier(touch), at: position, early: true, touch: touch)
        }
        observeRootTouch(touch)
    }

    private func observeRootTouch(_ touch: UITouch) {
        guard touchDebuggerRunning else { return }
        let point = touch.location(in: interactionHost)
        let padding = interactionHost.touchExpansion
        let candidate = letterButtons.first { button, _ in
            let hitRect = button.convert(button.bounds.insetBy(dx: -padding, dy: -padding),
                                         to: interactionHost)
            return hitRect.contains(point)
        }?.1
        let receiver: String
        if touch.view === interactionHost {
            receiver = "router"
        } else if let button = touch.view as? UIButton {
            // Name the button so settings-panel taps can be checked against
            // where the finger actually was.
            let name = button.accessibilityLabel ?? button.title(for: .normal) ?? "button"
            receiver = "'\(name)'"
        } else if let view = touch.view {
            receiver = view.accessibilityIdentifier ?? String(describing: Swift.type(of: view))
        } else {
            receiver = "no view"
        }
        let delay = Int(max(0, min(10_000,
            (ProcessInfo.processInfo.systemUptime - touch.timestamp) * 1_000)))
        if rootTouchSamples.count == 160 { rootTouchSamples.removeFirst() }
        rootTouchSamples.append(KeyboardRootTouchSample(
            keyCandidate: candidate, position: point, receivingView: receiver,
            deliveryMs: delay))
    }

    private func startTouchDebugger() {
        clearTouchDebugger()
        touchDebuggerRunning = true
        debugStartStaleCount = interactionHost.staleTouchRecoveryCount
        debugStartEarlyRoutedCount = interactionHost.earlyRootRoutedCount
        debugHapticRequests = 0
        debugVibrationRequests = 0
        rootTouchMonitor.isEnabled = true
        debugInitialContextLength = textDocumentProxy.documentContextBeforeInput?.count
        let liveMaterial = KeyboardPreferences.glassEnabled &&
            !KeyboardPreferences.usesSystemCanvas && !UIAccessibility.isReduceTransparencyEnabled
        debugCanvasDescription = "\(KeyboardPreferences.preset.title), " +
            (KeyboardPreferences.usesSystemCanvas ? "iOS canvas" : "custom canvas") +
            ", live material \(liveMaterial ? "on" : "off"), " +
            "direct \(interactionHost.directTouchRoutingEnabled ? "on" : "off"), " +
            "touch \(Int(interactionHost.touchExpansion))pt"
        interactionHost.onTouchDiagnostic = { [weak self] point, key, delivery, action, gap in
            guard let self, self.touchDebuggerRunning else { return }
            // Bound the ring; do not touch disk or read the host document here.
            if self.touchSamples.count == 160 { self.touchSamples.removeFirst() }
            self.touchSamples.append(KeyboardTouchSample(
                key: key, position: point, deliveryMs: delivery,
                actionMs: action, usedGapRouting: gap))
        }
        show(settingsPanel ? "Touch DEBUG ON · tap settings, then Touch debug: Finish"
             : "Touch DEBUG ON · type qwertyuiopasdfghjklzxcvbnm, then hold ⚙ again")
    }

    private func finishTouchDebugger() {
        touchDebuggerRunning = false
        rootTouchMonitor.isEnabled = !isPreview
        interactionHost.onTouchDiagnostic = nil
        lastTouchDebugReport = touchDebugReport()
        showTouchDebugReport(lastTouchDebugReport)
    }

    private func touchDebugReport() -> String {
        let expected = Array("qwertyuiopasdfghjklzxcvbnm")
        let observed = touchSamples.compactMap { $0.key?.lowercased() }
            .filter { $0.count == 1 && $0.first?.isLetter == true }.joined()
        let attempted = debugProxyInsertions.joined()
        var missing: [Character] = []
        var expectedIndex = 0
        var isExpectedSubsequence = true
        // Judge misses by what was actually inserted. A late duplicate that
        // was correctly blocked shows up as an unlabeled router touch, not a
        // miss.
        let typedLetters = attempted.lowercased().filter { $0.isLetter }
        for character in typedLetters {
            guard let next = expected[expectedIndex...].firstIndex(of: character) else {
                isExpectedSubsequence = false
                break
            }
            missing.append(contentsOf: expected[expectedIndex..<next])
            expectedIndex = next + 1
        }
        if isExpectedSubsequence { missing.append(contentsOf: expected[expectedIndex...]) }
        let hostGrowth: String
        if let start = debugInitialContextLength,
           let end = textDocumentProxy.documentContextBeforeInput?.count {
            hostGrowth = String(end - start)
        } else { hostGrowth = "unavailable" }
        let maxDelivery = touchSamples.map(\.deliveryMs).max() ?? 0
        let maxAction = touchSamples.map(\.actionMs).max() ?? 0
        let maxInsert = debugProxyTimes.max() ?? 0
        let slowInserts = debugProxyTimes.filter { $0 > 30 }.count
        let gapHits = touchSamples.filter(\.usedGapRouting).count
        let recoveredStale = max(0, interactionHost.staleTouchRecoveryCount - debugStartStaleCount)
        let earlyRouted = max(0, interactionHost.earlyRootRoutedCount - debugStartEarlyRoutedCount)
        let rootLetterTouches = rootTouchSamples.filter { $0.keyCandidate != nil }
        let rootSequence = rootLetterTouches.compactMap(\.keyCandidate).joined()
        let rootOnlyEstimate = max(0, rootLetterTouches.count - observed.count)
        let maxRootDelivery = rootTouchSamples.map(\.deliveryMs).max() ?? 0
        let recentRoot = rootTouchSamples.suffix(20).map { sample in
            "\(sample.keyCandidate ?? "?")@\(Int(sample.position.x)),\(Int(sample.position.y)):" +
                "\(sample.receivingView)/\(sample.deliveryMs)ms"
        }.joined(separator: " ")
        let recent = touchSamples.suffix(18).map { sample in
            "\(sample.key ?? "?")@\(Int(sample.position.x)),\(Int(sample.position.y)):" +
                "\(sample.deliveryMs)/\(sample.actionMs)ms"
        }.joined(separator: " ")
        return """
        AUKKHOR TOUCH DEBUG (local session)
        Only use non-sensitive test text. Nothing is uploaded or saved.

        Theme: \(debugCanvasDescription)
        Keyboard height: \(Int(view.bounds.height)) pt, window: \(Int(view.window?.bounds.height ?? 0)) pt, in-window y: \(Int(view.convert(CGPoint.zero, to: nil).y))
        Field appearance: \(Self.appearanceName(textDocumentProxy.keyboardAppearance)), keyboard style: \(traitCollection.userInterfaceStyle == .dark ? "dark" : "light")
        Expected test: \(String(expected))
        Root touch-downs seen: \(rootTouchSamples.count)
        Root touches in letter area: \(rootLetterTouches.count)
        Root letter candidate sequence: \(rootSequence.isEmpty ? "(none)" : rootSequence)
        Estimated root letter touches not routed: \(rootOnlyEstimate)
        Max root touch delivery delay: \(maxRootDelivery) ms
        Gap-rescued touches: \(gapHits)
        Stale touches recovered: \(recoveredStale)
        Late duplicate deliveries blocked: \(interactionHost.lateDuplicateCount)
        Merged-finger letters recovered: \(interactionHost.mergedFingerRecoveryCount)
        Root-early-routed key presses: \(earlyRouted)
        Haptic enabled: \(typingOptions.haptics ? "yes" : "no")
        Haptic mode: \(typingOptions.hapticMode.title)
        Haptic requests issued: \(debugHapticRequests)
        Vibration fallback requests: \(debugVibrationRequests)
        Touches delivered to router: \(touchSamples.count)
        Proxy insert calls: \(debugProxyInsertions.count)
        Host text growth: \(hostGrowth) characters (best effort)
        Max touch delivery delay: \(maxDelivery) ms
        Max key action time: \(maxAction) ms
        Max proxy insertion time: \(maxInsert) ms
        Slow insertions (>30 ms): \(slowInserts)

        Key touch sequence: \(observed.isEmpty ? "(none)" : observed)
        Proxy attempt sequence: \(attempted.isEmpty ? "(none)" : attempted)
        Missing in expected test: \(isExpectedSubsequence ? (missing.isEmpty ? "none" : String(missing)) : "test order differs")

        Recent key@x,y:delivery/action:
        \(recent.isEmpty ? "(none)" : recent)

        Recent root key@x,y:recipient/delivery:
        \(recentRoot.isEmpty ? "(none)" : recentRoot)
        """
    }

    private func showTouchDebugReport(_ report: String) {
        touchDebugOverlay?.removeFromSuperview()
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.accessibilityIdentifier = "keyboard.touchDebugOverlay"
        overlay.backgroundColor = palette.background.withAlphaComponent(0.98)
        overlay.layer.cornerRadius = 10
        overlay.clipsToBounds = true
        interactionHost.addSubview(overlay)
        interactionHost.modalOverlay = overlay
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: interactionHost.leadingAnchor, constant: 4),
            overlay.trailingAnchor.constraint(equalTo: interactionHost.trailingAnchor, constant: -4),
            overlay.topAnchor.constraint(equalTo: interactionHost.topAnchor, constant: 24),
            overlay.bottomAnchor.constraint(equalTo: interactionHost.bottomAnchor, constant: -4)
        ])
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            column.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            column.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),
            column.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -6)
        ])
        let title = UILabel()
        title.text = "Touch debugger · session only"
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = palette.foreground
        column.addArrangedSubview(title)
        let detail = UITextView()
        detail.accessibilityIdentifier = "keyboard.touchDebugReport"
        detail.text = report
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = palette.foreground
        detail.backgroundColor = .clear
        detail.isEditable = false
        detail.isScrollEnabled = true
        detail.textContainerInset = .zero
        column.addArrangedSubview(detail)
        let status = UILabel()
        status.accessibilityIdentifier = "keyboard.touchDebugStatus"
        status.font = .systemFont(ofSize: 11)
        status.textColor = palette.foreground
        status.numberOfLines = 2
        status.text = hasFullAccess
            ? "Copy to clipboard, or insert the report into the current text field."
            : "Clipboard needs Full Access. Use Insert text, then copy from the current app."
        column.addArrangedSubview(status)
        let actions = UIStackView()
        actions.distribution = .fillEqually
        actions.spacing = 4
        let copy = UIButton(type: .system)
        copy.accessibilityIdentifier = "keyboard.touchDebugCopy"
        copy.setTitle("Copy", for: .normal)
        copy.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            guard self.hasFullAccess else {
                status.text = "iOS blocks clipboard access here. Tap Insert text instead."
                return
            }
            UIPasteboard.general.string = self.lastTouchDebugReport
            status.text = UIPasteboard.general.string == self.lastTouchDebugReport
                ? "Copied. Paste it into your reply."
                : "Clipboard write failed. Tap Insert text instead."
        }, for: .touchUpInside)
        let insert = UIButton(type: .system)
        insert.accessibilityIdentifier = "keyboard.touchDebugInsert"
        insert.setTitle("Insert text", for: .normal)
        insert.addAction(UIAction { [weak self] _ in
            guard let self, !self.lastTouchDebugReport.isEmpty else { return }
            self.textDocumentProxy.insertText(self.lastTouchDebugReport)
            status.text = "Inserted in the current text field. Select it there to copy."
        }, for: .touchUpInside)
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.addAction(UIAction { [weak self] _ in self?.clearTouchDebugger() }, for: .touchUpInside)
        for button in [copy, insert, done] {
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
        }
        actions.addArrangedSubview(copy)
        actions.addArrangedSubview(insert)
        actions.addArrangedSubview(done)
        actions.heightAnchor.constraint(equalToConstant: 38).isActive = true
        column.addArrangedSubview(actions)
        touchDebugOverlay = overlay
    }

    private func clearTouchDebugger() {
        touchDebuggerRunning = false
        rootTouchMonitor.isEnabled = !isPreview
        interactionHost.onTouchDiagnostic = nil
        interactionHost.modalOverlay = nil
        touchDebugOverlay?.removeFromSuperview()
        touchDebugOverlay = nil
        touchSamples.removeAll()
        rootTouchSamples.removeAll()
        debugStartStaleCount = 0
        debugStartEarlyRoutedCount = 0
        debugHapticRequests = 0
        debugVibrationRequests = 0
        debugProxyInsertions.removeAll()
        debugProxyTimes.removeAll()
        debugInitialContextLength = nil
        debugCanvasDescription = ""
        lastTouchDebugReport = ""
    }

    private func buildAppearancePanel() {
        // Start/finish from here too, so settings-page taps can be measured.
        stack.addArrangedSubview(row([
            (touchDebuggerRunning ? "Touch debug: Finish" : "Touch debug: Start", { [weak self] in
                guard let self else { return }
                let wasRunning = self.touchDebuggerRunning
                self.toggleTouchDebugger()
                if !wasRunning {
                    self.buildKeys() // Relabel this button as Finish.
                    self.show("Touch DEBUG ON · tap settings, then Touch debug: Finish")
                }
            })
        ]))
        stack.addArrangedSubview(row([
            (KeyboardPreferences.autoCapitalize ? "Auto-caps: On" : "Auto-caps: Off", { [weak self] in
                KeyboardPreferences.autoCapitalize.toggle(); self?.buildKeys()
            }),
            (KeyboardPreferences.autocorrect ? "Autocorrect: On" : "Autocorrect: Off", { [weak self] in
                KeyboardPreferences.autocorrect.toggle(); self?.buildKeys()
            }),
            (KeyboardPreferences.textReplacement ? "Replacements: On" : "Replacements: Off", { [weak self] in
                KeyboardPreferences.textReplacement.toggle(); self?.buildKeys()
            })
        ]))
        stack.addArrangedSubview(row([
            (AukkhorSettings.keyboardClipboardEnabled ? "Windows tools: On" : "Windows tools: Off", { [weak self] in
                AukkhorSettings.keyboardClipboardEnabled.toggle(); self?.buildKeys()
            }),
            (KeyboardPreferences.haptics ? "Taptic: On" : "Taptic: Off", { [weak self] in
                KeyboardPreferences.haptics.toggle()
                self?.buildKeys()
                self?.prepareHaptic()
            })
        ]))
        stack.addArrangedSubview(row([
            ("Feedback: " + KeyboardPreferences.hapticMode.title, { [weak self] in
                KeyboardPreferences.hapticMode = KeyboardPreferences.hapticMode.next
                self?.buildKeys()
                self?.prepareHaptic()
            }),
            ("Test feedback", { [weak self] in
                self?.triggerHaptic(force: true)
            })
        ]))
        stack.addArrangedSubview(row([
            ("Theme: " + KeyboardPreferences.preset.title, { [weak self] in self?.cycleTheme() }),
            ("Done", { [weak self] in self?.settingsPanel = false; self?.buildKeys() })
        ]))
        stack.addArrangedSubview(row([
            (["Keycaps: Normal", "Keycaps: Borderless", "Keycaps: None"][KeyboardPreferences.keycapStyle], { [weak self] in
                KeyboardPreferences.keycapStyle = (KeyboardPreferences.keycapStyle + 1) % 3
                self?.buildKeys()
            }),
            (KeyboardPreferences.numberRow ? "Numbers: On" : "Numbers: Off", { [weak self] in
                KeyboardPreferences.numberRow.toggle(); self?.buildKeys()
            })
        ]))
        let touchControls = row([
            ("Roundness −", { [weak self] in KeyboardPreferences.cornerRadius = max(0, KeyboardPreferences.cornerRadius - 2); self?.buildKeys() }),
            ("Roundness +", { [weak self] in KeyboardPreferences.cornerRadius = min(24, KeyboardPreferences.cornerRadius + 2); self?.buildKeys() }),
            ("Touch: \(Int(KeyboardPreferences.touchExpansion))", { [weak self] in
                KeyboardPreferences.increaseTouchExpansion()
                self?.buildKeys()
                if let self {
                    self.show("Touch: \(Int(KeyboardPreferences.touchExpansion)) pt · received \(self.interactionHost.receivedTouchCount) · direct \(self.interactionHost.routedTouchCount)")
                }
            })
        ])
        if let touchButton = touchControls.arrangedSubviews.last as? UIButton {
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(toggleDirectTouchRoutingFromLongPress(_:)))
            hold.minimumPressDuration = 0.55
            touchButton.addGestureRecognizer(hold)
            touchButton.accessibilityHint = "Tap to adjust sensitivity. Hold to toggle direct touch routing."
        }
        stack.addArrangedSubview(touchControls)
        stack.addArrangedSubview(row([
            ("Opacity −", { [weak self] in KeyboardPreferences.keyOpacity -= 0.1; self?.buildKeys() }),
            ("Opacity +", { [weak self] in KeyboardPreferences.keyOpacity += 0.1; self?.buildKeys() })
        ]))
        stack.addArrangedSubview(row([
            (KeyboardPreferences.usesSystemCanvas ? "Background: iOS" : "Background: Custom", { [weak self] in
                let system = !KeyboardPreferences.usesSystemCanvas
                KeyboardPreferences.seamlessBackground = system
                if system { KeyboardPreferences.setGlassEnabled(true) }
                self?.buildKeys()
            })
        ]))
        if !KeyboardPreferences.seamlessBackground {
        stack.addArrangedSubview(row([
            (KeyboardPreferences.clearGlass ? "Clear glass" : "Frosted glass", { [weak self] in
                KeyboardPreferences.clearGlass.toggle(); self?.buildKeys()
            }),
            ("Tint −", { [weak self] in KeyboardPreferences.glassTintStrength -= 0.04; self?.buildKeys() }),
            ("Tint +", { [weak self] in KeyboardPreferences.glassTintStrength += 0.04; self?.buildKeys() })
        ]))
        }
        let colors = UIStackView(arrangedSubviews: [
            colorControl("Background", set: { KeyboardPreferences.customBackground = $0 }),
            colorControl("Keys", set: { KeyboardPreferences.customKey = $0 }),
            colorControl("Actions", set: { KeyboardPreferences.customSecondaryKey = $0 }),
            colorControl("Text", set: { KeyboardPreferences.customForeground = $0 })
        ])
        colors.distribution = .fillEqually
        colors.spacing = 4
        colors.heightAnchor.constraint(equalToConstant: 36).isActive = true
        stack.addArrangedSubview(colors)

    }

    @objc private func toggleDirectTouchRoutingFromLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        KeyboardPreferences.directTouchRouting.toggle()
        buildKeys()
        show(KeyboardPreferences.directTouchRouting ? "Direct touch handling: On" : "Direct touch handling: Off")
    }

    func tapShift() {
        if autoShifted && shift && !capsLock {
            // Declining an automatic capital at this position.
            autoShiftDeclinedContext = textDocumentProxy.documentContextBeforeInput ?? ""
        }
        autoShifted = false
        if Date().timeIntervalSince(lastShiftTap) < 0.35 {
            capsLock.toggle()
            shift = capsLock
        } else if capsLock {
            capsLock = false
            shift = false
        } else {
            shift.toggle()
        }
        lastShiftTap = Date()
        refreshShiftKeys()
    }

    private func cycleTheme() {
        let presets = KeyboardPreset.allCases
        let index = presets.firstIndex(of: KeyboardPreferences.preset) ?? 0
        KeyboardPreferences.preset = presets[(index + 1) % presets.count]
        buildKeys()
        show("Theme: \(KeyboardPreferences.preset.title)")
    }

    private func toggleEmoji() {
        commitBuffer()
        settingsPanel = false
        emojiMode.toggle()
        clipboardPanel = false
        emojiSearch = false; emojiQuery = ""
        buildKeys()
    }

    private func toggleClipboardPanel() {
        commitBuffer()
        clipboardPanel.toggle()
        emojiMode = false
        buildKeys()
    }

    private func buildEmojiPanel() {
        if emojiSearch {
            let found = EmojiCatalog.search(emojiQuery, group: emojiGroup)
            if !found.isEmpty {
                for start in stride(from: 0, to: min(found.count, 14), by: 7) {
                    let chunk = Array(found[start..<min(start + 7, found.count)])
                    stack.addArrangedSubview(row(chunk.map { entry in
                        (entry.glyph, { [weak self] in self?.insertEmoji(entry.glyph) })
                    }))
                }
            }
            for line in ["qwertyuiop", "asdfghjkl", "zxcvbnm"] {
                addChars(line.map(String.init))
            }
        } else {
            stack.addArrangedSubview(row(EmojiCatalog.groups.map { group in
                (String(group.prefix(3)), { [weak self] in self?.emojiGroup = group; self?.buildKeys() })
            }))
            let found = EmojiCatalog.search("", group: emojiGroup)
            for start in stride(from: 0, to: found.count, by: 7) {
                let chunk = Array(found[start..<min(start + 7, found.count)])
                stack.addArrangedSubview(row(chunk.map { entry in
                    (entry.glyph, { [weak self] in self?.insertEmoji(entry.glyph) })
                }))
            }
        }
        stack.addArrangedSubview(row([
            (emojiSearch ? "Clear search" : "🔍 Search", { [weak self] in
                guard let self else { return }
                if self.emojiSearch { self.emojiQuery = "" }
                else { self.emojiSearch = true }
                self.buildKeys()
            }),
            ("ABC", { [weak self] in self?.emojiMode = false; self?.buildKeys() })
        ]))
    }

    private func insertEmoji(_ emoji: String) {
        commitBuffer()
        textDocumentProxy.insertText(emoji)
        refreshSuggestions()
    }

    private func buildClipboardPanel() {
        stack.addArrangedSubview(row([
            (ScreenshotClipboard.enabled ? "Auto screenshots: On" : "Auto screenshots: Off", { [weak self] in
                self?.toggleScreenshotCopy()
            }),
            ("Refresh status", { [weak self] in self?.buildKeys() })
        ]))
        let access = UILabel()
        access.text = "iOS Full Access: \(hasFullAccess ? "On" : "Off") · Shared settings: \(AukkhorSettings.sharedSettingsAvailable ? "Yes" : "No")\n" + ScreenshotClipboard.shared.status
        access.font = .systemFont(ofSize: 11)
        access.numberOfLines = 3
        access.textColor = palette.foreground
        access.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(access)
        stack.addArrangedSubview(row([
            ("Read current clipboard", { [weak self] in self?.saveCurrentClipboard() }),
            ("Clear session history", { [weak self] in
                self?.clipboardHistory.removeAll(); self?.buildKeys()
            })
        ]))
        for value in clipboardHistory.prefix(3) {
            let title = String(value.prefix(37)).replacingOccurrences(of: "\n", with: " ")
            stack.addArrangedSubview(row([(title, { [weak self] in
                self?.commitBuffer()
                self?.textDocumentProxy.insertText(value)
                self?.clipboardPanel = false
                self?.buildKeys()
            })]))
        }
        if clipboardHistory.isEmpty {
            stack.addArrangedSubview(row([("No saved clips in this session", { })]))
        }
    }

    private func recordClip(_ text: String) {
        guard !text.isEmpty else { return }
        clipboardHistory.removeAll(where: { $0 == text })
        clipboardHistory.insert(String(text.prefix(1024)), at: 0)
        if clipboardHistory.count > 5 { clipboardHistory.removeLast() }
    }

    private func toggleScreenshotCopy() {
        guard requireClipboardAccess() else { return }
        if ScreenshotClipboard.enabled {
            ScreenshotClipboard.enabled = false
            ScreenshotClipboard.shared.stop()
            buildKeys()
            return
        }
        Task { @MainActor [weak self] in
            let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard let self else { return }
            guard permission == .authorized || permission == .limited else {
                self.show("Allow Photos access in iOS Settings for Aukkhor.")
                return
            }
            ScreenshotClipboard.enabled = true
            ScreenshotClipboard.shared.start()
            self.buildKeys()
            self.show(ScreenshotClipboard.shared.status)
        }
    }

    private func saveCurrentClipboard() {
        guard requireClipboardAccess() else { return }
        guard let value = UIPasteboard.general.string else { show("Clipboard has no text"); return }
        recordClip(value)
        buildKeys()
        show("Clipboard saved for this keyboard session")
    }

    private func currentWord() -> String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        return String(before.reversed().prefix(while: { $0.isLetter || $0 == "'" }).reversed())
    }

    private func replaceWord(_ original: String, with replacement: String) {
        guard !original.isEmpty else { return }
        commitBuffer()
        for _ in original { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement)
    }

    private func applyTextReplacementIfNeeded(delimiter: String) {
        guard mode == .english, !symbols, !emojiMode else { return }
        // Read the two live settings independently. System shortcut expansion
        // and dictionary autocorrect are different features.
        let allowShortcuts = KeyboardPreferences.textReplacement
        let allowCorrection = KeyboardPreferences.autocorrect
        guard allowShortcuts || allowCorrection else { return }
        let current = currentWord()
        guard !current.isEmpty, current != suppressedReplacement else { return }
        // iOS's supplementary lexicon can contain case-only transformations.
        // They look like random auto-capitalization even with Autocorrect Off.
        // Never silently change the case of an otherwise identical word.
        let shortcut = allowShortcuts ? replacements[current].flatMap { replacement in
            replacement.caseInsensitiveCompare(current) == .orderedSame ? nil : replacement
        } : nil
        // Never autocorrect acronyms, mixed-case words, or manual Shift input.
        let suggestion = shortcut ?? (allowCorrection && current == current.lowercased()
            ? KeyboardSuggestions.correction(current, replacements: [:]) : nil)
        guard let suggestion, suggestion != current else { return }
        // Autocorrect must never introduce uppercase characters. Explicit
        // multiword shortcuts remain available under Replacements: On.
        if shortcut == nil && suggestion != suggestion.lowercased() { return }
        replaceWord(current, with: suggestion)
        pendingReplacement = (current, suggestion + delimiter, textDocumentProxy.documentIdentifier)
    }

    private func applySuggestion(_ value: String) {
        if mode == .phonetic {
            guard !renderedBuffer.isEmpty else { return }
            replaceWord(renderedBuffer, with: value)
        } else {
            replaceWord(currentWord(), with: value)
        }
        textDocumentProxy.insertText(" ")
        if shift && !capsLock { shift = false; autoShifted = false; refreshShiftKeys() }
        updateAutoShift()
        refreshSuggestions()
    }

    // Keep the case the user started typing in: "Hel" -> "Hello", "HEL" -> "HELLO".
    static func matchingCase(of typed: String, _ word: String) -> String {
        guard let first = typed.first, first.isUppercase else { return word }
        if typed.count > 1, typed == typed.uppercased(), typed.contains(where: \.isLetter) {
            return word.uppercased()
        }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    // iOS's own spelling dictionary: frequency-ranked completions and real
    // corrections, instead of the tiny alphabetical starter list.
    private func systemCompletions(for prefix: String) -> [String] {
        guard let language = checkerLanguage, !prefix.isEmpty else { return [] }
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        var found: [String] = []
        if prefix.count >= 3,
           textChecker.rangeOfMisspelledWord(in: prefix, range: range, startingAt: 0,
                                             wrap: false, language: language).location != NSNotFound,
           let guess = textChecker.guesses(forWordRange: range, in: prefix, language: language)?.first {
            found.append(guess)
        }
        found += (textChecker.completions(forPartialWordRange: range, in: prefix,
                                          language: language) ?? []).prefix(6)
        return found
    }

    private func installSuggestionControls() {
        if candidateButtons.isEmpty {
            suggestionHeading.font = .systemFont(ofSize: 11)
            suggestionHeading.textAlignment = .center
            suggestionHeading.adjustsFontSizeToFitWidth = true
            suggestionHeading.isHidden = true
            suggestions.addArrangedSubview(suggestionHeading)
            for index in 0..<3 {
                let button = stripButton("", action: { [weak self] in
                    guard let self else { return }
                    let value = self.candidateValues[index]
                    if self.otpActionsVisible {
                        if index < self.otpCandidates.count {
                            if let code = OTPInbox.consume(self.otpCandidates[index]) {
                                self.commitBuffer()
                                self.textDocumentProxy.insertText(code)
                                self.show("VaultBridge code filled")
                                self.refreshSuggestions()
                            }
                        } else if value == "Paste OTP" { self.pasteOneTimeCode() }
                        else if value == "Next keyboard" { self.switchForSystemOTP() }
                    } else if !value.isEmpty { self.applySuggestion(value) }
                })
                button.accessibilityIdentifier = "keyboard.candidate.\(index)"
                button.constraints.filter { $0.firstAttribute == .width }.forEach { $0.isActive = false }
                button.titleLabel?.font = .systemFont(ofSize: 12)
                button.isHidden = true
                candidateButtons.append(button)
                suggestions.addArrangedSubview(button)
            }
        }
        suggestionHeading.textColor = palette.muted
        for button in candidateButtons { button.setTitleColor(palette.foreground, for: .normal) }
    }

    private func setCandidates(_ values: [String], heading: String? = nil) {
        UIView.performWithoutAnimation {
            suggestionHeading.text = heading
            suggestionHeading.isHidden = heading == nil
            for (index, button) in candidateButtons.enumerated() {
                let value = heading == nil && index < values.count ? values[index] : ""
                if candidateValues[index] != value {
                    candidateValues[index] = value
                    button.setTitle(value, for: .normal)
                    button.accessibilityLabel = value
                }
                if button.isHidden != value.isEmpty { button.isHidden = value.isEmpty }
            }
        }
    }

    // Keep candidate generation off the input/main thread. A late result must
    // never overwrite a newer word's suggestions.
    func requestSuggestions(prefix: String, phonetic: Bool, bangla: Bool) {
        let key = "\(phonetic):\(bangla):\(prefix)"
        // An empty word always clears, even if the last request was also
        // empty; otherwise stale candidates stayed up after deleting a word.
        guard !prefix.isEmpty else { suggestionRequestKey = key; setCandidates([]); return }
        guard suggestionRequestKey != key else { return }
        suggestionRequestKey = key
        let shortcuts = replacements
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let values = phonetic ? [PhoneticBangla.transliterate(prefix)]
                : KeyboardSuggestions.complete(prefix, banglaMode: bangla, replacements: shortcuts)
            DispatchQueue.main.async {
                // The host may report an unchanged context again after the
                // lookup began. Comparing the prefix (not just a generation)
                // avoids dropping valid results for that same word.
                guard let self, self.suggestionRequestKey == key,
                      !self.settingsPanel, !self.emojiMode, !self.clipboardPanel,
                      !self.symbols, self.typingOptions.suggestions else { return }
                guard !phonetic, !bangla else { self.setCandidates(values); return }
                let lower = prefix.lowercased()
                // Explicit shortcut first, then a correction, then the most
                // frequent completions; the starter list only fills gaps.
                let shortcut = shortcuts[lower]
                var ranked: [String] = []
                if let shortcut { ranked.append(shortcut) }
                if let fix = KeyboardSuggestions.correction(lower, replacements: [:]) { ranked.append(fix) }
                ranked += self.systemCompletions(for: lower) + values
                var seen: Set<String> = [lower]
                var final: [String] = []
                for word in ranked {
                    let shaped = word == shortcut ? word : Self.matchingCase(of: prefix, word)
                    guard seen.insert(shaped.lowercased()).inserted else { continue }
                    final.append(shaped)
                    if final.count == 3 { break }
                }
                self.setCandidates(final)
            }
        }
    }

    private func refreshSuggestions() {
        contextRefreshGeneration += 1
        let generation = contextRefreshGeneration
        contextRefreshWork?.cancel()
        // iOS owns SMS/Mail AutoFill. A keyboard extension gets only input traits,
        // never the system's secret code suggestions. Do not inspect the clipboard
        // until the user explicitly taps Paste OTP.
        if textDocumentProxy.textContentType == .oneTimeCode,
           !emojiMode, !clipboardPanel, !settingsPanel {
            otpActionsVisible = true
            suggestionRequestKey = nil
            otpCandidates = Array(OTPInbox.availableCandidates().prefix(3))
            if otpCandidates.isEmpty {
                setCandidates(["Paste OTP", "Next keyboard"])
            } else {
                setCandidates(otpCandidates.map { "\($0.title)  \($0.code)" })
            }
            return
        }
        otpActionsVisible = false
        if emojiMode || clipboardPanel || settingsPanel || symbols || !typingOptions.suggestions {
            suggestionRequestKey = nil
            let heading: String? = emojiMode ? (emojiSearch ? "🔍 \(emojiQuery)" : "Emoji: \(emojiGroup)")
                : (clipboardPanel ? "Session clipboard" : nil)
            setCandidates([], heading: heading)
            return
        }
        // Host context is cross-process. Coalesce callbacks and leave the key
        // action before reading it; ordinary English insertion stays immediate.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.contextRefreshGeneration == generation else { return }
            let text = self.mode == .phonetic && !self.buffer.isEmpty ? self.buffer : self.currentWord()
            self.requestSuggestions(prefix: text, phonetic: self.mode == .phonetic,
                                    bangla: self.mode == .bangla)
        }
        contextRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: work)
    }

    @objc private func moveCaret(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            undoSpaceForCaretMovement()
            commitBuffer()
            dragCaretOffset = 0
            dragStartX = recognizer.location(in: recognizer.view).x
            show("Move finger left/right to position the cursor")
        case .changed:
            let offset = Int((recognizer.location(in: recognizer.view).x - dragStartX) / 14)
            let delta = offset - dragCaretOffset
            if delta != 0 {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
                dragCaretOffset = offset
            }
        case .ended, .cancelled, .failed:
            dragCaretOffset = 0
            refreshSuggestions()
        default: break
        }
    }

    private func cycleMode() {
        commitBuffer()
        mode = InputMode(rawValue: (mode.rawValue + 1) % InputMode.allCases.count)!
        symbols = false; shift = false; capsLock = false; autoShifted = false
        emojiMode = false; clipboardPanel = false
        buildKeys()
    }

    private func typeSpaceFromTouchDown() {
        let searchingEmoji = emojiMode && emojiSearch
        type(" ")
        if !searchingEmoji {
            spaceTouchResult = lastSpaceTap == .distantPast ? .doubleSpacePeriod : .ordinary
        }
    }

    private func undoSpaceForCaretMovement() {
        guard let inserted = spaceTouchResult else { return }
        spaceTouchResult = nil
        switch inserted {
        case .ordinary:
            // A long press should move the caret, not leave an extra Space
            // or a newly expanded text replacement behind.
            backspace(refresh: false)
        case .doubleSpacePeriod:
            textDocumentProxy.deleteBackward()
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(" ")
        }
        lastSpaceTap = .distantPast
    }

    private func insertTypedText(_ value: String) {
        guard touchDebuggerRunning else {
            textDocumentProxy.insertText(value)
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        textDocumentProxy.insertText(value)
        let elapsedMs = Int(max(0, min(10_000,
            (ProcessInfo.processInfo.systemUptime - started) * 1_000)))
        if debugProxyInsertions.count == 160 { debugProxyInsertions.removeFirst() }
        if debugProxyTimes.count == 160 { debugProxyTimes.removeFirst() }
        debugProxyInsertions.append(value)
        debugProxyTimes.append(elapsedMs)
    }

    private func type(_ value: String) {
        // A deliberate Shift tap followed by typing is not a Caps Lock double
        // tap, even if the user is fast enough to hit Shift again in 350ms.
        lastShiftTap = .distantPast
        pendingReplacement = nil
        if value.first?.isLetter == true { suppressedReplacement = nil }
        if emojiMode && emojiSearch {
            if value == "\n" { emojiSearch = false; buildKeys(); return }
            if value.count == 1 && (value.first?.isLetter == true || value == " ") {
                emojiQuery += value.lowercased()
                buildKeys()
            }
            return
        }
        if value == " " && typingOptions.doubleSpace && mode == .english && !symbols &&
            Date().timeIntervalSince(lastSpaceTap) < 0.45 &&
            (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(" ") {
            textDocumentProxy.deleteBackward()
            insertTypedText(". ")
            lastSpaceTap = .distantPast
            return
        }
        if value == " " { lastSpaceTap = Date() }
        else { lastSpaceTap = .distantPast }
        if mode == .phonetic && !symbols && value.count == 1 && value.range(of: "^[A-Za-z]$", options: .regularExpression) != nil {
            if !renderedBuffer.isEmpty && !(textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(renderedBuffer) {
                buffer = ""; renderedBuffer = ""
            }
            buffer += value
            let newText = PhoneticBangla.transliterate(buffer)
            for _ in renderedBuffer { textDocumentProxy.deleteBackward() }
            insertTypedText(newText)
            renderedBuffer = newText
        } else {
            if value == " " || value == "." || value == "," || value == "\n" || value == "!" || value == "?" {
                applyTextReplacementIfNeeded(delimiter: value)
            }
            commitBuffer()
            insertTypedText(value)
            if mode == .english && !symbols {
                if value.count == 1 && value.first?.isLetter == true && shift && !capsLock {
                    shift = false
                    autoShifted = false
                    refreshShiftKeys()
                }
            }
            if value.count == 1, value.first?.isLetter != true { updateAutoShift() }
        }
        refreshSuggestions()
    }

    // Turn Shift on at the start of a sentence (or every word/letter when the
    // field asks for it) and back off when that no longer applies. Never
    // touches a Shift the user set themselves.
    private func updateAutoShift() {
        guard isViewLoaded, mode == .english, !capsLock else { return }
        // The host app's embedded preview and plain layout tests have no real
        // field; only a live field (or an injected test field) drives this.
        #if DEBUG
        guard !isPreview || testingProxy != nil else { return }
        #else
        guard !isPreview else { return }
        #endif
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if let declined = autoShiftDeclinedContext {
            if declined == before { return }
            autoShiftDeclinedContext = nil
        }
        var wanted = false
        if typingOptions.autoCaps, !symbols, !emojiMode, !settingsPanel, !clipboardPanel {
            switch textDocumentProxy.autocapitalizationType ?? .sentences {
            case .none:
                wanted = false
            case .allCharacters:
                wanted = true
            case .words:
                wanted = before.isEmpty || before.last?.isWhitespace == true
            default:
                wanted = Self.isSentenceStart(before)
            }
            if textDocumentProxy.isSecureTextEntry == true || textDocumentProxy.keyboardType == .emailAddress
                || textDocumentProxy.keyboardType == .URL || textDocumentProxy.keyboardType == .webSearch
                || textDocumentProxy.textContentType == .oneTimeCode { wanted = false }
        }
        if wanted && !shift {
            shift = true
            autoShifted = true
            refreshShiftKeys()
        } else if !wanted && shift && autoShifted {
            shift = false
            autoShifted = false
            refreshShiftKeys()
        }
    }

    static func appearanceName(_ appearance: UIKeyboardAppearance?) -> String {
        switch appearance {
        case .some(.dark): return "dark"
        case .some(.light): return "light"
        case .some(.default): return "default"
        default: return "unknown"
        }
    }

    static func isSentenceStart(_ before: String) -> Bool {
        if before.isEmpty || before.last == "\n" { return true }
        guard before.last?.isWhitespace == true else { return false }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        if last == "\n" { return true }
        // "Done." / "Really?!" / "Wait..." / closing quote or bracket after them.
        let closing: Set<Character> = ["\"", "'", ")", "]", "”", "’"]
        let core = trimmed.reversed().drop { closing.contains($0) }.first
        return core.map { ".!?".contains($0) } ?? false
    }

    private func commitBuffer() { buffer = ""; renderedBuffer = "" }

    private func startDelete() {
        stopDelete()
        deleteHeld = true
        deleteTicks = 0
        backspace()
        guard deleteHeld else { return }
        let timer = Timer(fire: Date().addingTimeInterval(0.35), interval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.deleteHeld else { return }
            self.deleteTicks += 1
            // A burst of 120 cross-process deleteBackward() calls per second
            // blocked normal taps on actual iPhones. Bound the IPC burst.
            let count = self.deleteTicks > 36 ? 3 : 1
            for _ in 0..<count { self.backspace(refresh: false) }
            if self.deleteTicks % 3 == 0 { self.refreshSuggestions() }
        }
        deleteTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        deleteHeld = false
    }

    private func backspace(refresh: Bool = true) {
        if let undo = pendingReplacement {
            pendingReplacement = nil
            if textDocumentProxy.documentIdentifier == undo.document,
               (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(undo.inserted) {
                for _ in undo.inserted { textDocumentProxy.deleteBackward() }
                textDocumentProxy.insertText(undo.original)
                suppressedReplacement = undo.original
                commitBuffer()
                if refresh { refreshSuggestions() }
                return
            }
        }
        if emojiMode && emojiSearch {
            if !emojiQuery.isEmpty { emojiQuery.removeLast() }
            buildKeys()
            return
        }
        if mode == .phonetic && !buffer.isEmpty &&
            (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(renderedBuffer) {
            buffer.removeLast()
            for _ in renderedBuffer { textDocumentProxy.deleteBackward() }
            renderedBuffer = PhoneticBangla.transliterate(buffer)
            textDocumentProxy.insertText(renderedBuffer)
        } else {
            commitBuffer()
            textDocumentProxy.deleteBackward()
        }
        updateAutoShift()
        if refresh { refreshSuggestions() }
    }

    private func selectedOrNearbyText() -> String? {
        if let selected = textDocumentProxy.selectedText, !selected.isEmpty { return selected }
        return textDocumentProxy.documentContextBeforeInput?.split(whereSeparator: { !$0.isLetter }).last.map(String.init)
    }

    private enum SelectionFormat: String {
        case uppercase, lowercase, titlecase, bold, italic, strikethrough, indent, outdent
    }

    private func installFormatMenu(on button: UIButton) {
        func choice(_ title: String, _ format: SelectionFormat) -> UIAction {
            UIAction(title: title) { [weak self] _ in self?.formatSelection(format) }
        }
        button.menu = UIMenu(title: "Select text in the app first", children: [
            UIMenu(title: "Change case", children: [
                choice("UPPERCASE", .uppercase),
                choice("lowercase", .lowercase),
                choice("Title Case", .titlecase)
            ]),
            UIMenu(title: "Plain-text / Markdown", children: [
                choice("**Bold** (Markdown)", .bold),
                choice("*Italic* (Markdown)", .italic),
                choice("~~Strikethrough~~ (Markdown)", .strikethrough),
                choice("Indent (4 spaces)", .indent),
                choice("Outdent", .outdent)
            ])
        ])
        button.showsMenuAsPrimaryAction = true
    }

    private func formatSelection(_ format: SelectionFormat) {
        guard let text = textDocumentProxy.selectedText, !text.isEmpty else {
            show("Select text first to format it")
            return
        }
        let transformed: String
        switch format {
        case .uppercase: transformed = text.uppercased()
        case .lowercase: transformed = text.lowercased()
        case .titlecase: transformed = text.capitalized
        case .bold: transformed = "**\(text)**"
        case .italic: transformed = "*\(text)*"
        case .strikethrough: transformed = "~~\(text)~~"
        case .indent:
            transformed = text.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
        case .outdent:
            transformed = text.components(separatedBy: "\n").map {
                let count = $0.prefix(4).prefix(while: { $0 == " " }).count
                return String($0.dropFirst(count))
            }.joined(separator: "\n")
        }
        guard transformed != text else { return }
        commitBuffer()
        pendingReplacement = nil
        // insertText replaces the host's current selection; the extension has
        // no supported API for setting Notes' NSAttributedString attributes.
        textDocumentProxy.insertText(transformed)
        refreshSuggestions()
    }

    @discardableResult
    private func insertOneTimeCode(from text: String) -> Bool {
        guard let code = CodeExtractor.extract(text) else { return false }
        commitBuffer()
        pendingReplacement = nil
        textDocumentProxy.insertText(code)
        refreshSuggestions()
        return true
    }

    private func pasteOneTimeCode() {
        guard requireClipboardAccess() else { return }
        guard let value = UIPasteboard.general.string else {
            show("Copy a verification code first, or switch to Apple's keyboard for AutoFill")
            return
        }
        guard insertOneTimeCode(from: value) else {
            show("No unique 4–8 digit code in clipboard")
            return
        }
        show("Verification code pasted")
    }

    private func switchForSystemOTP() {
        // advanceToNextInputMode is the supported API; it may lead to another
        // third-party keyboard, depending on the user's installed keyboard order.
        advanceToNextInputMode()
    }

    private func paste() {
        guard requireClipboardAccess() else { return }
        if let value = UIPasteboard.general.string {
            commitBuffer(); textDocumentProxy.insertText(value)
            recordClip(value); refreshSuggestions()
        }
        else if UIPasteboard.general.hasImages {
            show("Image ready: touch and hold the app's text field, then Paste")
        } else { show("Clipboard has no text") }
    }

    private func requireClipboardAccess(network: Bool = false) -> Bool {
        AukkhorSettings.refreshSharedSettings()
        guard hasFullAccess else {
            show("iOS reports Full Access off. Enable it, then switch away and back to Aukkhor.")
            return false
        }
        if network && !AukkhorSettings.keyboardClipboardEnabled {
            show("Windows tools are off. Enable Windows tools in the keyboard's gear menu.")
            return false
        }
        return true
    }

    private func cut() {
        guard requireClipboardAccess() else { return }
        guard let selected = textDocumentProxy.selectedText, !selected.isEmpty else { show("Select text first") ; return }
        UIPasteboard.general.string = selected
        recordClip(selected)
        commitBuffer()
        textDocumentProxy.deleteBackward()
        show("Cut selected text")
    }

    private func define() {
        guard let word = selectedOrNearbyText(), !word.isEmpty else { show("Select or type a word") ; return }
        guard UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word) else {
            show("No installed dictionary definition for \(word)")
            return
        }
        present(UIReferenceLibraryViewController(term: word), animated: true)
    }

    private func speak() {
        guard let phrase = selectedOrNearbyText(), !phrase.isEmpty else { show("Select or type text") ; return }
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: mode == .english ? "en-US" : "bn-BD")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        speech.speak(utterance)
    }

    private func sendClipboardToPC() {
        guard requireClipboardAccess(network: true) else { return }
        guard let value = UIPasteboard.general.string else { show("Clipboard has no text") ; return }
        recordClip(value)
        Task { [weak self] in
            do { try await AukkhorLink.shared.sendClipboard(value); await MainActor.run { self?.show("Clipboard sent to PC") } }
            catch { await MainActor.run { self?.show(error.localizedDescription) } }
        }
    }

    private func getClipboardFromPC() {
        guard requireClipboardAccess(network: true) else { return }
        Task { [weak self] in
            do {
                let value = try await AukkhorLink.shared.receiveClipboard()
                await MainActor.run {
                    UIPasteboard.general.string = value
                    self?.recordClip(value)
                    self?.show("Windows text ready to paste")
                }
            } catch { await MainActor.run { self?.show(error.localizedDescription) } }
        }
    }

    func show(_ message: String) {
        banner.textColor = palette.foreground
        banner.backgroundColor = palette.secondaryKey
        banner.text = message
        banner.accessibilityLabel = message
        banner.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.banner.text == message { self?.banner.isHidden = true }
        }
    }
}

