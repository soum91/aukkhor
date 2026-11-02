import UIKit
import AVFoundation
import Photos

private enum InputMode: Int, CaseIterable {
    case english, phonetic, bangla
    var label: String {
        switch self { case .english: return "EN"; case .phonetic: return "বাংলা Ph"; case .bangla: return "বাংলা" }
    }
}

private struct TypingOptions {
    let haptics = KeyboardPreferences.haptics
    let sounds = KeyboardPreferences.keySounds
    let suggestions = KeyboardPreferences.suggestions
    let doubleSpace = KeyboardPreferences.doubleSpacePeriod
    let glide = KeyboardPreferences.experimentalGlide
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
    private var lastSpaceTap = Date.distantPast
    private var symbols = false
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
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private var typingOptions = TypingOptions()
    private var lastAppearanceSignature: String?
    private var candidateButtons: [UIButton] = []
    private var candidateValues = [String](repeating: "", count: 3)
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
    #if DEBUG
    var testingProxy: UITextDocumentProxy?
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
    #endif

    private let glassBackdrop = UIVisualEffectView(effect: nil)
    private let pressLens = KeyboardPressLensView()
    private weak var highlightedLensButton: KeyboardButton?
    // Keep every control in a plain view above the decorative material. An
    // effectless UIVisualEffectView can still install private hit-test views
    // when UIKit moves a keyboard extension between remote host windows.
    private let interactionHost = KeyboardInteractionView()
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
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private let suggestions = UIStackView()
    private let banner = UILabel()
    private var palette = KeyboardPalette.selected(dark: false)
    var enableInputClicks: Bool { typingOptions.sounds }

    override func loadView() {
        let root = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                                   height: KeyboardPreferences.typingHeight), inputViewStyle: .default)
        root.allowsSelfSizing = true
        root.autoresizingMask = [.flexibleWidth]
        root.backgroundColor = .clear
        root.isOpaque = false
        root.accessibilityIdentifier = "aukkhor.keyboard.content"
        inputView = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        surface.translatesAutoresizingMaskIntoConstraints = false
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
        impact.prepare()
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
        interactionHost.backgroundColor = .clear
        interactionHost.isOpaque = false
        interactionHost.isUserInteractionEnabled = true
        interactionHost.accessibilityIdentifier = "keyboard.interactionHost"
        surface.addSubview(interactionHost)
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
        // A weaker priority lets UIKit's original compact keyboard height win
        // after settings expands. The primary view must own its requested
        // height so the entire settings grid is visible without scrolling.
        preferredHeight.priority = .required
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
        AukkhorSettings.refreshSharedSettings()
        if isViewLoaded {
            if lastAppearanceSignature != KeyboardPreferences.renderingSignature {
                oneHandSide = KeyboardPreferences.oneHandSide
                buildKeys()
            }
            impact.prepare()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Reuse the canvas installed by buildKeys instead of restarting its
        // material animations every time the host presents the keyboard.
        if !isPreview, hasFullAccess { ScreenshotClipboard.shared.start() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // A host can move the caret or rewrite the field at any time.
        if !renderedBuffer.isEmpty && !(textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(renderedBuffer) {
            buffer = ""; renderedBuffer = ""
        }
        refreshSuggestions()
    }

    private func feedback() {
        if typingOptions.haptics { impact.impactOccurred() }
        if typingOptions.sounds { UIDevice.current.playInputClick() }
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
        button.usesPressLens = KeyboardPreferences.preset == .clearPrism
        if button.usesPressLens {
            button.onHighlightChanged = { [weak self] highlighted, key in
                self?.updatePressLens(for: key, highlighted: highlighted)
            }
        }
        button.setTitle(title, for: .normal)
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
            button.addAction(UIAction { [weak self] _ in
                guard let self, !self.isPreview else { return }
                self.startDelete()
                self.feedback()
            }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in
                guard let self, !self.isPreview else { return }
                // Accessibility activation can send only touchUpInside.
                if !self.deleteHeld { self.backspace() }
                self.stopDelete()
            }, for: .touchUpInside)
            button.addAction(UIAction { [weak self] _ in self?.stopDelete() },
                             for: [.touchUpOutside, .touchCancel])
        } else if immediateInput {
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, !self.isPreview else { return }
                button?.immediateActionTriggered = true
                action(); self.feedback()
            }, for: .touchDown)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, !self.isPreview else { return }
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
            button.addAction(UIAction(identifier: UIAction.Identifier("aukkhor.tap")) { [weak self] _ in guard self?.isPreview != true else { return }; action(); self?.feedback() }, for: .touchUpInside)
        }
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return button
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
        row.heightAnchor.constraint(equalToConstant: KeyboardPreferences.rowHeight).isActive = true
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

    private func addThirdRow(_ chars: [String]) {
        let container = UIStackView()
        container.spacing = 0
        let shiftKey = makeButton(capsLock ? "⇪" : "⇧", action: { [weak self] in
            self?.tapShift()
        })
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
            ("⚙", { [weak self] in self?.toggleAppearancePanel() }),
            ("Paste", { [weak self] in self?.paste() }),
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
            button.titleLabel?.font = .systemFont(ofSize: title.count > 1 ? 11 : 20)
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            tools.addArrangedSubview(button)
        }

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
        strip.addArrangedSubview(stripButton("⚙", action: { [weak self] in
            self?.toggleAppearancePanel()
        }))
        return strip
    }

    private func buildKeys() {
        stopDelete()
        highlightedLensButton = nil
        pressLens.isHidden = true
        lastAppearanceSignature = KeyboardPreferences.renderingSignature
        typingOptions = TypingOptions()
        glideRecognizer.isEnabled = typingOptions.glide
        suggestionRequestKey = nil
        palette = KeyboardPalette.selected(dark: traitCollection.userInterfaceStyle == .dark)
        letterButtons.removeAll()
        shiftButton = nil
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
            addChars(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
            addChars(["@", "#", "$", "%", "&", "-", "+", "(", ")", "/"])
            addChars(["*", "\"", ":", ";", "!", "?", "'", ",", ".", "_"])
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
        let needsEditingKeys = symbols || mode == .bangla || emojiMode || clipboardPanel || settingsPanel
        var bottomControls: [(String, () -> Void)] = [
            (symbols ? "ABC" : "123", { [weak self] in
                self?.commitBuffer(); self?.symbols.toggle(); self?.emojiMode = false
                self?.clipboardPanel = false; self?.settingsPanel = false; self?.buildKeys()
            }),
            ("😊", { [weak self] in self?.toggleEmoji() }),
            ("Space", { [weak self] in self?.typeSpaceFromTouchDown() }),
            ("return", { [weak self] in self?.type("\n") })
        ]
        if needsEditingKeys {
            bottomControls.insert(("⌫", { [weak self] in self?.backspace() }), at: 3)
        }
        if mode == .bangla && !emojiMode && !clipboardPanel && !settingsPanel {
            bottomControls.insert((nativeSigns ? "ব্যঞ্জন" : "স্বর", { [weak self] in
                self?.nativeSigns.toggle(); self?.buildKeys()
            }), at: 1)
        }
        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = KeyboardPreferences.keySpacing
        bottom.heightAnchor.constraint(equalToConstant: KeyboardPreferences.rowHeight).isActive = true
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

    private func buildAppearancePanel() {
        stack.addArrangedSubview(row([
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
        stack.addArrangedSubview(row([
            ("Roundness −", { [weak self] in KeyboardPreferences.cornerRadius = max(0, KeyboardPreferences.cornerRadius - 2); self?.buildKeys() }),
            ("Roundness +", { [weak self] in KeyboardPreferences.cornerRadius = min(24, KeyboardPreferences.cornerRadius + 2); self?.buildKeys() }),
            (KeyboardPreferences.glassEnabled ? "Glass: On" : "Glass: Off", { [weak self] in
                KeyboardPreferences.setGlassEnabled(!KeyboardPreferences.glassEnabled); self?.buildKeys()
            })
        ]))
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

    func tapShift() {
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
        // System text shortcuts are explicit, case-sensitive user choices.
        // Don't turn "auto" into "AUTO" (or vice versa) by normalizing them.
        let shortcut = allowShortcuts ? replacements[current] : nil
        // Never autocorrect acronyms, mixed-case words, or manual Shift input.
        let suggestion = shortcut ?? (allowCorrection && current == current.lowercased()
            ? KeyboardSuggestions.correction(current, replacements: [:]) : nil)
        guard let suggestion, suggestion != current else { return }
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
        refreshSuggestions()
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
                    if !value.isEmpty { self.applySuggestion(value) }
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

    // The indexed local dictionary is small. Once host-context reads have been
    // coalesced, a synchronous lookup avoids background-queue contention and
    // stale callbacks resetting suggestions during fast typing.
    func requestSuggestions(prefix: String, phonetic: Bool, bangla: Bool) {
        contextRefreshGeneration += 1
        contextRefreshWork?.cancel()
        let key = "\(phonetic):\(bangla):\(prefix)"
        guard suggestionRequestKey != key else { return }
        suggestionRequestKey = key
        guard !prefix.isEmpty else { setCandidates([]); return }
        let values = phonetic ? [PhoneticBangla.transliterate(prefix)]
            : KeyboardSuggestions.complete(prefix, banglaMode: bangla, replacements: replacements)
        setCandidates(values)
    }

    private func refreshSuggestions() {
        contextRefreshGeneration += 1
        let generation = contextRefreshGeneration
        contextRefreshWork?.cancel()
        if emojiMode || clipboardPanel || settingsPanel || symbols || !typingOptions.suggestions {
            suggestionRequestKey = nil
            let heading: String? = emojiMode ? (emojiSearch ? "🔍 \(emojiQuery)" : "Emoji: \(emojiGroup)")
                : (clipboardPanel ? "Session clipboard" : nil)
            setCandidates([], heading: heading)
            return
        }
        // Host context is cross-process. Coalesce callbacks and leave the key
        // action before reading it; ordinary English insertion stays immediate.
        suggestionRequestKey = nil
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.contextRefreshGeneration == generation else { return }
            let text = self.mode == .phonetic && !self.buffer.isEmpty ? self.buffer : self.currentWord()
            self.requestSuggestions(prefix: text, phonetic: self.mode == .phonetic,
                                    bangla: self.mode == .bangla)
        }
        contextRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
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
        symbols = false; shift = false; capsLock = false
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

    private func type(_ value: String) {
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
            textDocumentProxy.insertText(". ")
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
            textDocumentProxy.insertText(newText)
            renderedBuffer = newText
        } else {
            if value == " " || value == "." || value == "," || value == "\n" || value == "!" || value == "?" {
                applyTextReplacementIfNeeded(delimiter: value)
            }
            commitBuffer()
            textDocumentProxy.insertText(value)
            if mode == .english && !symbols {
                if value.count == 1 && value.first?.isLetter == true && shift && !capsLock {
                    shift = false
                    refreshShiftKeys()
                }
            }
        }
        refreshSuggestions()
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
            let count = self.deleteTicks > 36 ? 6 : (self.deleteTicks > 12 ? 2 : 1)
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
        if refresh { refreshSuggestions() }
    }

    private func selectedOrNearbyText() -> String? {
        if let selected = textDocumentProxy.selectedText, !selected.isEmpty { return selected }
        return textDocumentProxy.documentContextBeforeInput?.split(whereSeparator: { !$0.isLetter }).last.map(String.init)
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

