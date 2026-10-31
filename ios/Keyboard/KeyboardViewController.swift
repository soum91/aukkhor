import UIKit
import AVFoundation

private enum InputMode: Int, CaseIterable {
    case english, phonetic, bangla
    var label: String {
        switch self { case .english: return "EN"; case .phonetic: return "বাংলা Ph"; case .bangla: return "বাংলা" }
    }
}

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback, UIGestureRecognizerDelegate {
    var isPreview = false
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
    private let backgroundImageView = UIImageView()
    private let glassBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let stack = UIStackView()
    private let contentStack = UIStackView()
    private var toolsExpanded = false
    private let suggestions = UIStackView()
    private let banner = UILabel()
    private var palette: KeyboardPalette {
        KeyboardPalette.selected(dark: traitCollection.userInterfaceStyle == .dark)
    }
    var enableInputClicks: Bool { KeyboardPreferences.keySounds }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = palette.background
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundImageView)
        glassBackdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glassBackdrop)
        NSLayoutConstraint.activate([
            glassBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glassBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glassBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            glassBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        stack.axis = .vertical
        stack.spacing = 7
        contentStack.axis = .horizontal
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)
        suggestions.heightAnchor.constraint(greaterThanOrEqualToConstant: 29).isActive = true
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        let glide = UIPanGestureRecognizer(target: self, action: #selector(handleGlide(_:)))
        glide.cancelsTouchesInView = true
        glide.delegate = self
        view.addGestureRecognizer(glide)
        if !isPreview {
        requestSupplementaryLexicon { [weak self] lexicon in
            DispatchQueue.main.async {
                self?.replacements = Dictionary(lexicon.entries.map { ($0.userInput.lowercased(), $0.documentText) },
                                                 uniquingKeysWith: { _, newer in newer })
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
        if isViewLoaded { buildKeys() } // Reload preferences changed in the host app.
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
        if KeyboardPreferences.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if KeyboardPreferences.keySounds { UIDevice.current.playInputClick() }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard KeyboardPreferences.experimentalGlide, mode == .english,
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
                            foreground: UIColor = .label, weight: CGFloat = 1) -> UIButton {
        let button = UIButton(type: .system)
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
        KeyboardKeyAppearance.apply(to: button, palette: palette)
        button.accessibilityLabel = title
        button.addAction(UIAction(identifier: UIAction.Identifier("aukkhor.tap")) { [weak self] _ in guard self?.isPreview != true else { return }; self?.feedback(); action() }, for: .touchUpInside)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return button
    }

    private func row(_ items: [(String, () -> Void)]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = KeyboardPreferences.keySpacing
        for item in items { row.addArrangedSubview(makeButton(item.0, action: item.1)) }
        row.heightAnchor.constraint(equalToConstant: KeyboardPreferences.keyHeight).isActive = true
        return row
    }

    private func addChars(_ chars: [String]) {
        let keys = row(chars.map { letter in
            (letter, { [weak self] in self?.type(letter) })
        })
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
            self?.tapShift(); self?.buildKeys()
        })
        shiftKey.accessibilityLabel = "Shift"
        let deleteKey = makeButton("⌫", action: { [weak self] in self?.backspace() })
        deleteKey.accessibilityLabel = "Delete"
        let letters = row(chars.map { letter in (letter, { [weak self] in self?.type(letter) }) })
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
        contentStack.arrangedSubviews.forEach { contentStack.removeArrangedSubview($0); $0.removeFromSuperview() }
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
            ("⚙", { [weak self] in self?.settingsPanel.toggle(); self?.buildKeys() }),
            ("Paste", { [weak self] in self?.paste() }),
            ("Cut", { [weak self] in self?.cut() }),
            ("Define", { [weak self] in self?.define() }),
            ("Speak", { [weak self] in self?.speak() }),
            ("📋", { [weak self] in self?.toggleClipboardPanel() }),
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

    private func buildKeys() {
        view.backgroundColor = palette.background
        glassBackdrop.isHidden = !(KeyboardPreferences.preset == .liquidGlass || KeyboardPreferences.usesGlass)
        glassBackdrop.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        backgroundImageView.image = KeyboardPreferences.preset == .custom ? KeyboardPreferences.backgroundImage : nil
        hasPhotoBackground = backgroundImageView.image != nil
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        configureToolsRail()
        suggestions.axis = .horizontal
        suggestions.distribution = .fillEqually
        suggestions.spacing = 4
        stack.addArrangedSubview(suggestions)
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
            ("Space", { [weak self] in self?.type(" ") }),
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
        bottom.heightAnchor.constraint(equalToConstant: KeyboardPreferences.keyHeight).isActive = true
        for (label, action) in bottomControls {
            let button = makeButton(label, action: action)
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
        let footer = row([
            ("🌐", { [weak self] in self?.commitBuffer(); self?.advanceToNextInputMode() }),
            (mode.label, { [weak self] in self?.cycleMode() }),
            ("↔", { [weak self] in self?.cycleOneHand() }),
            ("⚙", { [weak self] in
                guard let self else { return }
                if self.oneHandSide == 0 { self.toolsExpanded.toggle() }
                self.settingsPanel.toggle(); self.buildKeys()
            })
        ])
        for case let button as UIButton in footer.arrangedSubviews {
            button.backgroundColor = .clear
            button.layer.borderWidth = 0
            button.layer.shadowOpacity = 0
            button.subviews.filter { $0.tag == 9401 }.forEach { $0.removeFromSuperview() }
        }
        if let globe = footer.arrangedSubviews.first as? UIButton {
            globe.removeAction(identifiedBy: UIAction.Identifier("aukkhor.tap"), for: .touchUpInside)
            // Keep Apple's keyboard-switcher menu, including long-press behavior.
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        }
        if let hand = footer.arrangedSubviews.dropFirst(2).first as? UIButton {
            hand.menu = UIMenu(title: "One-handed layout", children: [("Left", 1), ("Full width", 0), ("Right", 2)].map { title, side in
                UIAction(title: title, state: oneHandSide == side ? .on : .off) { [weak self] _ in
                    self?.oneHandSide = side; KeyboardPreferences.oneHandSide = side; self?.buildKeys()
                }
            })
            hand.showsMenuAsPrimaryAction = true
            hand.accessibilityLabel = "One-handed layout"
        }
        stack.addArrangedSubview(footer)
        banner.font = .systemFont(ofSize: 11)
        banner.textAlignment = .center
        banner.textColor = palette.muted
        banner.text = nil
        banner.isHidden = true
        stack.addArrangedSubview(banner)
        refreshSuggestions()
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

    private func buildAppearancePanel() {
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
            ("Glass", { [weak self] in KeyboardPreferences.usesGlass.toggle(); self?.buildKeys() })
        ]))
        stack.addArrangedSubview(row([
            ("Opacity −", { [weak self] in KeyboardPreferences.keyOpacity -= 0.1; self?.buildKeys() }),
            ("Opacity +", { [weak self] in KeyboardPreferences.keyOpacity += 0.1; self?.buildKeys() })
        ]))
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

    private func tapShift() {
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

    private func saveCurrentClipboard() {
        guard hasFullAccess, AukkhorSettings.keyboardClipboardEnabled else {
            show("Enable Full Access and keyboard tools")
            return
        }
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

    private func applyTextReplacementIfNeeded() {
        guard mode == .english, !symbols, !emojiMode else { return }
        let current = currentWord()
        guard !current.isEmpty else { return }
        let suggestion = KeyboardSuggestions.correction(current, replacements: replacements)
        guard let suggestion,
              (replacements[current.lowercased()] != nil || KeyboardPreferences.autocorrect) else { return }
        let capitalized = current.first?.isUppercase == true
            ? suggestion.prefix(1).uppercased() + String(suggestion.dropFirst()) : suggestion
        replaceWord(current, with: capitalized)
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

    private func refreshSuggestions() {
        suggestions.arrangedSubviews.forEach { suggestions.removeArrangedSubview($0); $0.removeFromSuperview() }
        if emojiMode {
            let heading = emojiSearch ? "🔍 \(emojiQuery)" : "Emoji: \(emojiGroup)"
            let label = UILabel(); label.text = heading; label.textAlignment = .center
            label.textColor = palette.foreground; label.font = .systemFont(ofSize: 13)
            suggestions.addArrangedSubview(label)
            return
        }
        if clipboardPanel {
            let label = UILabel(); label.text = "Clipboard clips stay in memory only"
            label.textAlignment = .center; label.textColor = palette.muted
            label.font = .systemFont(ofSize: 12)
            suggestions.addArrangedSubview(label)
            return
        }
        guard KeyboardPreferences.suggestions, !symbols else { return }
        let text = mode == .phonetic && !buffer.isEmpty ? buffer : currentWord()
        let candidates = mode == .phonetic
            ? [PhoneticBangla.transliterate(text)]
            : KeyboardSuggestions.complete(text, banglaMode: mode == .bangla, replacements: replacements)
        for candidate in candidates where !candidate.isEmpty {
            let button = makeButton(candidate, action: { [weak self] in self?.applySuggestion(candidate) })
            button.titleLabel?.font = .systemFont(ofSize: 15)
            KeyboardKeyAppearance.apply(to: button, palette: palette, secondary: true)
            suggestions.addArrangedSubview(button)
        }
    }

    @objc private func moveCaret(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
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

    private func type(_ value: String) {
        if emojiMode && emojiSearch {
            if value == "\n" { emojiSearch = false; buildKeys(); return }
            if value.count == 1 && (value.first?.isLetter == true || value == " ") {
                emojiQuery += value.lowercased()
                buildKeys()
            }
            return
        }
        if value == " " && KeyboardPreferences.doubleSpacePeriod && mode == .english && !symbols &&
            Date().timeIntervalSince(lastSpaceTap) < 0.45 &&
            (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(" ") {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpaceTap = .distantPast
            if KeyboardPreferences.autoCapitalize && !capsLock { shift = true; buildKeys() }
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
                applyTextReplacementIfNeeded()
            }
            commitBuffer()
            textDocumentProxy.insertText(value)
            if mode == .english && !symbols {
                if value == "." || value == "!" || value == "?" || value == "\n" {
                    if KeyboardPreferences.autoCapitalize && !capsLock { shift = true; buildKeys() }
                } else if value.count == 1 && value.first?.isLetter == true && shift && !capsLock {
                    shift = false
                    buildKeys()
                }
            }
        }
        refreshSuggestions()
    }

    private func commitBuffer() { buffer = ""; renderedBuffer = "" }

    private func backspace() {
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
        refreshSuggestions()
    }

    private func selectedOrNearbyText() -> String? {
        if let selected = textDocumentProxy.selectedText, !selected.isEmpty { return selected }
        return textDocumentProxy.documentContextBeforeInput?.split(whereSeparator: { !$0.isLetter }).last.map(String.init)
    }

    private func paste() {
        guard hasFullAccess, AukkhorSettings.keyboardClipboardEnabled else { show("Enable Full Access and keyboard tools in Aukkhor") ; return }
        if let value = UIPasteboard.general.string {
            commitBuffer(); textDocumentProxy.insertText(value)
            recordClip(value); refreshSuggestions()
        }
        else { show("Clipboard has no text") }
    }

    private func cut() {
        guard hasFullAccess, AukkhorSettings.keyboardClipboardEnabled else { show("Enable Full Access and keyboard tools") ; return }
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
        guard hasFullAccess, AukkhorSettings.keyboardClipboardEnabled else { show("Full Access is required") ; return }
        guard let value = UIPasteboard.general.string else { show("Clipboard has no text") ; return }
        recordClip(value)
        Task { [weak self] in
            do { try await AukkhorLink.shared.sendClipboard(value); await MainActor.run { self?.show("Clipboard sent to PC") } }
            catch { await MainActor.run { self?.show(error.localizedDescription) } }
        }
    }

    private func getClipboardFromPC() {
        guard hasFullAccess, AukkhorSettings.keyboardClipboardEnabled else { show("Full Access is required") ; return }
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

    private func show(_ message: String) {
        banner.isHidden = false
        banner.text = message
        banner.accessibilityLabel = message
    }
}

