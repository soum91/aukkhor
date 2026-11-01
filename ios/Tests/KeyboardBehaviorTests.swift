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
                        "keyboardDoubleSpace", "keyboardPreset", "keyboardKeycapStyle"]
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
    func testScreenshotRecoveryFreshness() {
        let now = Date()
        let enabled = now.addingTimeInterval(-300)
        XCTAssertTrue(PendingScreenshotStore.isFresh(now.addingTimeInterval(-10), enabledAt: enabled, now: now))
        XCTAssertFalse(PendingScreenshotStore.isFresh(now.addingTimeInterval(-121), enabledAt: enabled, now: now))
        XCTAssertFalse(PendingScreenshotStore.isFresh(now.addingTimeInterval(-301), enabledAt: enabled, now: now))
        XCTAssertFalse(PendingScreenshotStore.isFresh(now.addingTimeInterval(5), enabledAt: enabled, now: now))
    }
    func testClearPrismUsesOneNoninteractiveClearCanvas() throws {
        KeyboardPreferences.preset = .clearPrism
        KeyboardPreferences.keycapStyle = 0
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        func views(_ parent: UIView) -> [UIView] { [parent] + parent.subviews.flatMap(views) }
        let all = views(keyboard.view)
        let effects = all.compactMap { $0 as? UIVisualEffectView }
        XCTAssertEqual(effects.count, 1)
        XCTAssertFalse(KeyboardPreferences.usesSystemCanvas)
        XCTAssertEqual(KeyboardPreferences.glassTintStrength, 0)
        if #available(iOS 26.0, *) {
            let material = try XCTUnwrap(effects.first?.effect as? UIGlassEffect)
            XCTAssertFalse(material.isInteractive)
        }
        XCTAssertTrue(all.compactMap { $0 as? UIButton }.allSatisfy {
            !$0.subviews.contains { $0 is UIVisualEffectView }
        })
    }
}
