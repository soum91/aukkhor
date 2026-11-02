import XCTest
import UIKit
@testable import Aukkhor

private final class MemoryTextProxy: NSObject, UITextDocumentProxy {
    var text = ""
    private var selection: Range<String.Index>?
    var documentIdentifier = UUID()
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { selection.map { String(text[$0]) } }
    var documentInputMode: UITextInputMode? { nil }
    var hasText: Bool { !text.isEmpty }
    func select(_ substring: String) { selection = text.range(of: substring) }
    func insertText(_ text: String) {
        if let selection { self.text.replaceSubrange(selection, with: text); self.selection = nil }
        else { self.text += text }
    }
    func deleteBackward() {
        if let selection { text.removeSubrange(selection); self.selection = nil }
        else if !text.isEmpty { text.removeLast() }
    }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) { text += markedText }
    func unmarkText() {}
}

@MainActor final class KeyboardBehaviorTests: XCTestCase {
    private var saved: [String: Any] = [:]
    private let keys = ["keyboardAutocorrect", "keyboardTextReplacement", "keyboardSuggestions",
                        "keyboardDoubleSpace", "keyboardPreset", "keyboardKeycapStyle",
                        "keyboardSeamlessBackground", "keyboardNumberRow"]
    override func setUp() {
        super.setUp()
        for key in keys { saved[key] = AukkhorSettings.defaults.object(forKey: key) }
        KeyboardPreferences.autocorrect = false
        KeyboardPreferences.textReplacement = true
        KeyboardPreferences.suggestions = false
        KeyboardPreferences.doubleSpacePeriod = false
    }
    override func tearDown() {
        for key in keys {
            if let value = saved[key] { AukkhorSettings.defaults.set(value, forKey: key) }
            else { AukkhorSettings.defaults.removeObject(forKey: key) }
        }
        saved.removeAll()
        super.tearDown()
    }
    private func keyboard() -> (KeyboardViewController, MemoryTextProxy) {
        let proxy = MemoryTextProxy()
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.testingProxy = proxy
        keyboard.loadViewIfNeeded()
        keyboard.testingReplacements = ["omw": "on my way"]
        return (keyboard, proxy)
    }
    func testBackspaceUndoesReplacementAndDoesNotImmediatelyExpandAgain() {
        let (keyboard, proxy) = keyboard()
        keyboard.testingType("omw")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "on my way ")
        keyboard.testingDelete()
        XCTAssertEqual(proxy.text, "omw")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "omw ")
    }
    func testReplacementUndoDoesNotEditAnotherDocument() {
        let (keyboard, proxy) = keyboard()
        keyboard.testingType("omw")
        keyboard.testingType(" ")
        proxy.documentIdentifier = UUID()
        proxy.text = "on my way "
        keyboard.testingDelete()
        XCTAssertEqual(proxy.text, "on my way")
    }
    func testLiveAutocorrectOffAndIndependentTextReplacementOff() {
        let (keyboard, proxy) = keyboard()
        KeyboardPreferences.autocorrect = true
        keyboard.testingType("teh")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "the ")
        KeyboardPreferences.autocorrect = false
        proxy.text = ""
        keyboard.testingType("teh")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "teh ")
        KeyboardPreferences.textReplacement = false
        proxy.text = ""
        keyboard.testingType("omw")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "omw ")
    }
    func testNoAutomaticCapitalsAfterPunctuationOrNewlines() {
        let (keyboard, proxy) = keyboard()
        KeyboardPreferences.textReplacement = false
        keyboard.testingTypeCharacter("a")
        keyboard.testingType(".")
        keyboard.testingTypeCharacter("b")
        keyboard.testingType("?")
        keyboard.testingTypeCharacter("c")
        keyboard.testingType("\n")
        keyboard.testingTypeCharacter("d")
        XCTAssertEqual(proxy.text, "a.b?c\nd")
        // Manual Shift still affects exactly the next letter.
        keyboard.tapShift()
        keyboard.testingTypeCharacter("e")
        keyboard.testingTypeCharacter("f")
        XCTAssertEqual(proxy.text, "a.b?c\ndEf")
    }
    func testCaseOnlySystemReplacementIsNeverAppliedEvenWhenAutocorrectOff() {
        let (keyboard, proxy) = keyboard()
        keyboard.testingReplacements = ["auto": "AUTO", "Auto": "AUTO", "omw": "On my way"]
        KeyboardPreferences.autocorrect = false
        keyboard.testingType("Auto")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "Auto ")
        proxy.text = ""
        keyboard.testingType("auto")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "auto ")
        proxy.text = ""
        keyboard.testingType("omw")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "On my way ", "Real multiword text replacements still work")
        KeyboardPreferences.textReplacement = false
        proxy.text = ""
        keyboard.testingType("auto")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "auto ")
    }
    func testNoAccidentalCapsLockFromRapidShiftLetterShift() {
        let (keyboard, proxy) = keyboard()
        keyboard.tapShift()
        keyboard.testingTypeCharacter("a")
        keyboard.tapShift()
        keyboard.testingTypeCharacter("b")
        keyboard.testingTypeCharacter("c")
        XCTAssertEqual(proxy.text, "ABc", "Two separate one-shot shifts must not become Caps Lock")
    }
    func testRapidTypingPreservesEveryCharacterAndOriginalCase() {
        KeyboardPreferences.suggestions = true
        KeyboardPreferences.autocorrect = false
        let (keyboard, proxy) = keyboard()
        let input = String(repeating: "auto", count: 45)
        keyboard.testingReplacements = ["auto": "AUTO"]
        for character in input { keyboard.testingTypeCharacter(String(character)) }
        XCTAssertEqual(proxy.text, input)
    }
    func testRealTouchDownActionsNeverMissOrDoubleInsert() throws {
        KeyboardPreferences.autocorrect = false
        KeyboardPreferences.suggestions = false
        let (keyboard, proxy) = keyboard()
        keyboard.testingAllowTouchEvents = true
        func buttons(_ view: UIView) -> [KeyboardButton] {
            (view as? KeyboardButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let q = try XCTUnwrap(buttons(keyboard.view).first { $0.accessibilityLabel == "q" })
        XCTAssertTrue(q.insertsOnTouchDown)
        for count in 1...80 {
            // UIButton.touchesBegan invokes this before UIKit sends .touchDown.
            // Both paths must safely deliver exactly one character.
            q.touchBeginAction?()
            q.sendActions(for: .touchDown)
            XCTAssertEqual(proxy.text.count, count, "Touch down #\(count) must insert immediately")
            q.sendActions(for: .touchUpInside)
            XCTAssertEqual(proxy.text.count, count, "Touch up must not double insert")
        }
        XCTAssertEqual(proxy.text, String(repeating: "q", count: 80))
    }
    func testSelectedTextCaseAndMarkdownFormattingNeverResizeKeyboard() throws {
        let (keyboard, proxy) = keyboard()
        let initialHeight = try XCTUnwrap(keyboard.inputView as? KeyboardInputView).contentHeight
        proxy.text = "hello WORLD"
        proxy.select("hello WORLD")
        keyboard.testingFormatSelection("uppercase")
        XCTAssertEqual(proxy.text, "HELLO WORLD")
        proxy.select("HELLO WORLD")
        keyboard.testingFormatSelection("lowercase")
        XCTAssertEqual(proxy.text, "hello world")
        proxy.select("hello world")
        keyboard.testingFormatSelection("titlecase")
        XCTAssertEqual(proxy.text, "Hello World")
        proxy.select("Hello World")
        keyboard.testingFormatSelection("bold")
        XCTAssertEqual(proxy.text, "**Hello World**")
        proxy.select("Hello World")
        keyboard.testingFormatSelection("strikethrough")
        XCTAssertEqual(proxy.text, "**~~Hello World~~**")
        proxy.text = "one\ntwo"
        proxy.select("one\ntwo")
        keyboard.testingFormatSelection("indent")
        XCTAssertEqual(proxy.text, "    one\n    two")
        proxy.select("    one\n    two")
        keyboard.testingFormatSelection("outdent")
        XCTAssertEqual(proxy.text, "one\ntwo")
        XCTAssertEqual(try XCTUnwrap(keyboard.inputView as? KeyboardInputView).contentHeight,
                       initialHeight, "Formatting must not affect build 61 key geometry")
    }
    func testDictionaryCorrectionNeverChangesManualCapitalization() {
        let (keyboard, proxy) = keyboard()
        KeyboardPreferences.autocorrect = true
        KeyboardPreferences.textReplacement = false
        for word in ["TEH", "Teh", "tEh"] {
            proxy.text = ""
            keyboard.testingType(word)
            keyboard.testingType(" ")
            XCTAssertEqual(proxy.text, word + " ")
        }
        proxy.text = ""
        keyboard.testingType("teh")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "the ")
    }
    func testHeldDeleteRepeatsToEmptyAndStopsOnRelease() async throws {
        let (keyboard, proxy) = keyboard()
        proxy.text = "abcdefgh"
        keyboard.testingStartDelete()
        defer { keyboard.testingStopDelete() }
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(proxy.text, "")
        keyboard.testingStopDelete()
        proxy.text = "keep"
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(proxy.text, "keep")
    }
    func testTouchDownSpaceLongPressDoesNotLeaveExtraText() {
        let (keyboard, proxy) = keyboard()
        keyboard.testingType("omw")
        keyboard.testingTouchDownSpace()
        XCTAssertEqual(proxy.text, "on my way ")
        keyboard.testingBeginSpaceCaret()
        XCTAssertEqual(proxy.text, "omw")
    }
    func testDoubleSpaceLongPressRestoresPriorSpace() {
        KeyboardPreferences.doubleSpacePeriod = true
        let (keyboard, proxy) = keyboard()
        keyboard.testingType("hi")
        keyboard.testingTouchDownSpace()
        keyboard.testingTouchDownSpace()
        XCTAssertEqual(proxy.text, "hi. ")
        keyboard.testingBeginSpaceCaret()
        XCTAssertEqual(proxy.text, "hi ")
    }
    func testScreenshotRecoveryFreshness() {
        let now = Date()
        let enabled = now.addingTimeInterval(-300)
        XCTAssertTrue(PendingScreenshotStore.isFresh(now.addingTimeInterval(-10), enabledAt: enabled, now: now))
        XCTAssertFalse(PendingScreenshotStore.isFresh(now.addingTimeInterval(-121), enabledAt: enabled, now: now))
        XCTAssertFalse(PendingScreenshotStore.isFresh(now.addingTimeInterval(-301), enabledAt: enabled, now: now))
        XCTAssertFalse(PendingScreenshotStore.isFresh(now.addingTimeInterval(5), enabledAt: enabled, now: now))
    }
    func testClearPrismRestoresBuild61RefractiveCanvasAndTransientLens() throws {
        let savedPreset = KeyboardPreferences.preset
        let savedStyle = KeyboardPreferences.keycapStyle
        let savedSeamless = KeyboardPreferences.seamlessBackground
        defer {
            KeyboardPreferences.preset = savedPreset
            KeyboardPreferences.keycapStyle = savedStyle
            KeyboardPreferences.seamlessBackground = savedSeamless
        }
        KeyboardPreferences.preset = .clearPrism
        KeyboardPreferences.keycapStyle = 0
        // Build 62 silently forced system blending and removed Clear Prism's glass.
        KeyboardPreferences.seamlessBackground = false
        XCTAssertFalse(KeyboardPreferences.seamlessBackground)
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        func views(_ parent: UIView) -> [UIView] { [parent] + parent.subviews.flatMap(views) }
        let all = views(keyboard.view)
        let effects = all.compactMap { $0 as? UIVisualEffectView }
        XCTAssertEqual(effects.count, 1)
        let lens = try XCTUnwrap(all.compactMap { $0 as? KeyboardPressLensView }.first)
        XCTAssertTrue(lens.isHidden) // No permanent rainbow border.
        XCTAssertFalse(KeyboardPreferences.usesSystemCanvas)
        XCTAssertEqual(KeyboardPreferences.glassTintStrength, 0)
        if #available(iOS 26.0, *) {
            let glass = try XCTUnwrap(effects.first?.effect as? UIGlassEffect)
            XCTAssertFalse(glass.isInteractive, "Glass is decorative and cannot delay key events")
        } else {
            XCTAssertTrue(effects.first?.effect is UIBlurEffect)
        }
        let surface = try XCTUnwrap(all.first { $0.accessibilityIdentifier == "keyboard.surface" })
        XCTAssertEqual(surface.layer.cornerRadius, 20)
        XCTAssertEqual(surface.backgroundColor?.cgColor.alpha ?? 1, 0)
        XCTAssertTrue(all.compactMap { $0 as? UIButton }.allSatisfy {
            !$0.subviews.contains { $0 is UIVisualEffectView }
        })
        let letter = try XCTUnwrap(all.compactMap { $0 as? KeyboardButton }
            .first(where: { $0.title(for: .normal) == "q" }))
        letter.isHighlighted = true
        XCTAssertFalse(lens.isHidden)
        letter.isHighlighted = false
        XCTAssertTrue(lens.isHidden)
    }
    func testBuild61SettingsAndCriticalKeysInsertOnTouchDown() throws {
        let savedPreset = KeyboardPreferences.preset
        let savedNumberRow = KeyboardPreferences.numberRow
        defer {
            KeyboardPreferences.preset = savedPreset
            KeyboardPreferences.numberRow = savedNumberRow
        }
        KeyboardPreferences.preset = .clearPrism
        KeyboardPreferences.numberRow = true
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let expectedHeight = KeyboardPreferences.typingHeight
        keyboard.toggleAppearancePanel()
        let root = try XCTUnwrap(keyboard.inputView as? KeyboardInputView)
        XCTAssertGreaterThan(root.contentHeight, expectedHeight,
                             "Keep build 61's expanded settings layout")
        func views(_ parent: UIView) -> [UIView] { [parent] + parent.subviews.flatMap(views) }
        let all = views(keyboard.view)
        XCTAssertNil(all.first { $0.accessibilityIdentifier == "keyboard.settingsScroll" })
        keyboard.toggleAppearancePanel()
        for label in ["q", "a", "z", "Space", "return"] {
            let key = try XCTUnwrap(views(keyboard.view).compactMap { $0 as? KeyboardButton }
                .first(where: { $0.accessibilityLabel == label }))
            XCTAssertTrue(key.insertsOnTouchDown, "\(label) must not wait for finger release")
        }
    }
    func testClearPrismRestoresBuild61KeyInk() {
        let savedPreset = KeyboardPreferences.preset
        defer { KeyboardPreferences.preset = savedPreset }
        KeyboardPreferences.preset = .clearPrism
        let light = KeyboardPalette.selected(dark: false)
        let dark = KeyboardPalette.selected(dark: true)
        XCTAssertEqual(light.foreground, UIColor.white)
        XCTAssertEqual(light.border, UIColor.white)
        XCTAssertEqual(dark.foreground, UIColor.white)
        XCTAssertEqual(dark.border, UIColor.white)
    }
}
