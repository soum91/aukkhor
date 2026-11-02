import XCTest
import UIKit
@testable import Aukkhor

private final class MemoryTextProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var documentIdentifier = UUID()
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var hasText: Bool { !text.isEmpty }
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
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
    func testNoUnsolicitedUppercaseOrCaseInsensitiveShortcutExpansion() {
        let (keyboard, proxy) = keyboard()
        keyboard.testingReplacements = ["auto": "AUTO"]
        KeyboardPreferences.autocorrect = false
        keyboard.testingType("Auto")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "Auto ")
        proxy.text = ""
        keyboard.testingType("auto")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "AUTO ") // Explicit user shortcut is preserved.
        KeyboardPreferences.textReplacement = false
        proxy.text = ""
        keyboard.testingType("auto")
        keyboard.testingType(" ")
        XCTAssertEqual(proxy.text, "auto ")
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
    func testExpandedSettingsAndCriticalKeysInsertOnTouchDown() throws {
        KeyboardPreferences.preset = .clearPrism
        KeyboardPreferences.numberRow = true
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let expectedHeight = KeyboardPreferences.typingHeight
        keyboard.toggleAppearancePanel()
        let root = try XCTUnwrap(keyboard.inputView as? KeyboardInputView)
        let settingsRows: CGFloat = KeyboardPreferences.seamlessBackground ? 7 : 8
        let settingsHeight = 24 + (settingsRows + 1) * KeyboardPreferences.rowHeight + 36
            + (settingsRows + 2) * KeyboardPreferences.rowGap
        XCTAssertGreaterThan(settingsHeight, expectedHeight)
        XCTAssertEqual(root.contentHeight, settingsHeight, accuracy: 1,
                       "Expanded settings must request its complete height, never typing height")
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
        KeyboardPreferences.preset = .clearPrism
        let light = KeyboardPalette.selected(dark: false)
        let dark = KeyboardPalette.selected(dark: true)
        XCTAssertEqual(light.foreground, UIColor.white)
        XCTAssertEqual(light.border, UIColor.white)
        XCTAssertEqual(dark.foreground, UIColor.white)
        XCTAssertEqual(dark.border, UIColor.white)
    }
}
