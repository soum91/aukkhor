import XCTest
import UIKit
@testable import Aukkhor

private final class MemoryTextProxy: NSObject, UITextDocumentProxy {
    var text = ""
    private var selection: Range<String.Index>?
    var documentIdentifier = UUID()
    var textContentType: UITextContentType! = nil
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
                        "keyboardSeamlessBackground", "keyboardNumberRow", "keyboardTouchExpansion",
                        "keyboardDirectTouchRouting", "keyboardHaptics", "keyboardHapticMode"]
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
    func testOTPFieldShowsExplicitActionsWhenWordSuggestionsAreOff() {
        let (keyboard, proxy) = keyboard()
        proxy.textContentType = .oneTimeCode
        keyboard.textDidChange(nil)
        XCTAssertTrue(keyboard.testingOTPActionVisible)
        XCTAssertEqual(Array(keyboard.testingCandidateTitles.prefix(2)), ["Paste OTP", "Next keyboard"])
        XCTAssertEqual(proxy.text, "", "Opening the OTP bar must never inspect or type a secret")
        XCTAssertTrue(keyboard.testingInsertOTP(from: "Your sign-in code is 827641."))
        XCTAssertEqual(proxy.text, "827641")
        XCTAssertFalse(keyboard.testingInsertOTP(from: "Codes: 827641 and 123456"),
                       "Ambiguous clipboard text must not paste a guessed OTP")
        XCTAssertEqual(proxy.text, "827641")
        proxy.textContentType = nil
        keyboard.textDidChange(nil)
        XCTAssertFalse(keyboard.testingOTPActionVisible)
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
    func testControlTouchDownActionsNeverMissOrDoubleInsert() throws {
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
            // Use UIKit's .touchDown route, as in the pre-Prism keyboard.
            // Touch-up is a fallback only, never a duplicate insertion.
            q.sendActions(for: .touchDown)
            XCTAssertEqual(proxy.text.count, count, "Touch down #\(count) must insert immediately")
            q.sendActions(for: .touchUpInside)
            XCTAssertEqual(proxy.text.count, count, "Touch up must not double insert")
        }
        XCTAssertEqual(proxy.text, String(repeating: "q", count: 80))
        q.sendActions(for: .touchUpInside)
        XCTAssertEqual(proxy.text.count, 81, "Touch-up must recover a tap whose down event was missed")
    }
    func testSensitivityKeepsRoutedGapTouchesInsideButtonAcceptance() {
        let saved = KeyboardPreferences.touchExpansion
        defer { KeyboardPreferences.touchExpansion = saved }
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let button = KeyboardButton(type: .custom)
        button.frame = CGRect(x: 40, y: 20, width: 40, height: 40)
        host.addSubview(button)
        for padding: CGFloat in [0, 6, 10, 14, 16] {
            KeyboardPreferences.touchExpansion = padding
            button.touchExpansion = KeyboardPreferences.touchExpansion
            host.touchExpansion = KeyboardPreferences.touchExpansion
            let point = CGPoint(x: 80 + padding - 0.5, y: 40)
            let selected = host.hitTest(point, with: nil)
            XCTAssertTrue(selected === button, "Padding \(padding) should route this tap to the key")
            XCTAssertTrue(button.point(inside: button.convert(point, from: host), with: nil),
                          "The routed key must actually accept the point")
            XCTAssertFalse(host.hitTest(CGPoint(x: 80 + padding + 0.5, y: 40), with: nil) === button,
                           "A hit beyond the configured tolerance must not be misrouted")
        }
        KeyboardPreferences.touchExpansion = 10
        KeyboardPreferences.increaseTouchExpansion()
        XCTAssertEqual(KeyboardPreferences.touchExpansion, 14)
    }
    func testHapticModeSwitchPreservesAukkhorSettings() {
        KeyboardPreferences.hapticMode = .impact
        XCTAssertEqual(KeyboardPreferences.hapticMode.title, "Light")
        KeyboardPreferences.hapticMode = KeyboardPreferences.hapticMode.next
        XCTAssertEqual(KeyboardPreferences.hapticMode, .selection)
        KeyboardPreferences.hapticMode = KeyboardPreferences.hapticMode.next
        XCTAssertEqual(KeyboardPreferences.hapticMode, .vibration)
        KeyboardPreferences.hapticMode = KeyboardPreferences.hapticMode.next
        XCTAssertEqual(KeyboardPreferences.hapticMode, .impact)
    }

    func testLiveKeyboardReceivesOverlappingFingerTouches() {
        let (keyboard, _) = keyboard()
        XCTAssertTrue(keyboard.view.isMultipleTouchEnabled,
                      "UIKit must deliver multiple simultaneous touches to the keyboard root")
        let surface = keyboard.view.subviews.first {
            $0.accessibilityIdentifier == "keyboard.surface"
        }
        XCTAssertNotNil(surface)
        XCTAssertTrue(surface?.isMultipleTouchEnabled == true)
        let router = surface?.subviews.compactMap { $0 as? KeyboardInteractionView }.first
        XCTAssertNotNil(router)
        XCTAssertTrue(router?.isMultipleTouchEnabled == true,
                      "The shared letter router must receive every concurrent finger")
    }

    func testAllKeycapStylesKeepFullSizeTouchRoutingTargets() throws {
        let savedStyle = KeyboardPreferences.keycapStyle
        let savedPreset = KeyboardPreferences.preset
        defer {
            KeyboardPreferences.keycapStyle = savedStyle
            KeyboardPreferences.preset = savedPreset
        }
        KeyboardPreferences.preset = .custom
        func buttons(in view: UIView) -> [UIButton] {
            (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        var originalFrames: [String: CGRect] = [:]
        for style in 0...2 {
            KeyboardPreferences.keycapStyle = style
            let keyboard = KeyboardViewController()
            keyboard.isPreview = true
            keyboard.loadViewIfNeeded()
            keyboard.view.frame = CGRect(x: 0, y: 0, width: 390,
                                         height: KeyboardPreferences.typingHeight)
            keyboard.view.layoutIfNeeded()
            let surface = try XCTUnwrap(keyboard.view.subviews.first {
                $0.accessibilityIdentifier == "keyboard.surface"
            })
            let router = try XCTUnwrap(surface.subviews.compactMap {
                $0 as? KeyboardInteractionView
            }.first)
            XCTAssertEqual(router.bounds, surface.bounds)
            XCTAssertTrue(router.isUserInteractionEnabled)
            XCTAssertTrue(router.isMultipleTouchEnabled)
            let backgroundAlpha = router.backgroundColor?.cgColor.alpha ?? 0
            if style == 0 { XCTAssertEqual(backgroundAlpha, 0) }
            else { XCTAssertGreaterThan(backgroundAlpha, 0); XCTAssertLessThan(backgroundAlpha, 0.02) }
            for character in ["q", "w", "a", "s", "z", "x"] {
                let button = try XCTUnwrap(buttons(in: keyboard.view).first {
                    $0.accessibilityLabel == character
                })
                let frame = button.convert(button.bounds, to: keyboard.view)
                if style == 0 { originalFrames[character] = frame }
                else { XCTAssertEqual(frame, try XCTUnwrap(originalFrames[character]),
                                      "Removing keycaps must not shrink the touch cell") }
                let center = CGPoint(x: frame.midX, y: frame.midY)
                XCTAssertTrue(keyboard.view.hitTest(center, with: nil) === button,
                              "Key \(character) should receive touches without a visible cap")
                router.directTouchRoutingEnabled = true
                XCTAssertTrue(keyboard.view.hitTest(center, with: nil) === router,
                              "Direct input must use the same touch cell with every keycap style")
                router.directTouchRoutingEnabled = false
            }
        }
    }

    func testStaleTrackedTouchCannotSwallowTheNextPress() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        host.directTouchRoutingEnabled = true
        var inserted: [String] = []
        let key = KeyboardButton(type: .custom)
        key.accessibilityLabel = "q"
        key.insertsOnTouchDown = true
        key.frame = CGRect(x: 20, y: 20, width: 45, height: 45)
        key.addAction(UIAction { [weak key] _ in
            guard let key, !key.immediateActionTriggered else { return }
            key.immediateActionTriggered = true
            inserted.append("q")
        }, for: .touchDown)
        host.addSubview(key)
        let center = CGPoint(x: 42, y: 42)
        let first = NSObject(), second = NSObject()
        // First press: its end is never delivered (system gate swallowed it).
        XCTAssertNotNil(host.beginTrackedDirectKey(for: ObjectIdentifier(first), at: center))
        // Next finger on the same key must still type.
        XCTAssertNotNil(host.beginTrackedDirectKey(for: ObjectIdentifier(second), at: center))
        XCTAssertEqual(inserted, ["q", "q"])
    }

    func testLateViewDeliveryAfterEarlyReleaseDoesNotTypeTwice() {
        // Edge keys: the root monitor presses and releases the touch, then
        // UIKit delivers touchesBegan to the router 100+ ms late.
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        host.directTouchRoutingEnabled = true
        let key = KeyboardButton(type: .custom)
        key.accessibilityLabel = "p"
        key.insertsOnTouchDown = true
        key.frame = CGRect(x: 20, y: 20, width: 45, height: 45)
        var inserted = 0
        key.addAction(UIAction { _ in inserted += 1 }, for: .touchDown)
        host.addSubview(key)
        let touch = UITouch()
        let id = ObjectIdentifier(touch)
        let center = CGPoint(x: 42, y: 42)
        host.beginTrackedDirectKey(for: id, at: center, early: true, touch: touch)
        host.finishTrackedDirectKey(for: id, at: center)
        XCTAssertNil(host.beginTrackedDirectKey(for: id, at: center, touch: touch))
        XCTAssertEqual(inserted, 1)
        XCTAssertEqual(host.lateDuplicateCount, 1)
        // A genuinely new finger still types.
        let next = UITouch()
        host.beginTrackedDirectKey(for: ObjectIdentifier(next), at: center, touch: next)
        XCTAssertEqual(inserted, 2)
    }

    func testMergedSecondFingerTypesButDriftDoesNot() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        host.directTouchRoutingEnabled = true
        var inserted: [String] = []
        for (label, x) in [("s", CGFloat(20)), ("d", CGFloat(60))] {
            let key = KeyboardButton(type: .custom)
            key.accessibilityLabel = label
            key.insertsOnTouchDown = true
            key.frame = CGRect(x: x, y: 20, width: 34, height: 44)
            key.addAction(UIAction { _ in inserted.append(label) }, for: .touchDown)
            host.addSubview(key)
        }
        let id = ObjectIdentifier(NSObject())
        host.beginTrackedDirectKey(for: id, at: CGPoint(x: 37, y: 42))
        // Gradual drift across the border: same press.
        host.recoverMergedFinger(for: id, at: CGPoint(x: 52, y: 42), previous: CGPoint(x: 46, y: 42))
        host.recoverMergedFinger(for: id, at: CGPoint(x: 64, y: 42), previous: CGPoint(x: 52, y: 42))
        XCTAssertEqual(inserted, ["s"])
        // A second finger merged into this touch: one sample jumps a key.
        let other = ObjectIdentifier(NSObject())
        host.beginTrackedDirectKey(for: other, at: CGPoint(x: 37, y: 42))
        host.recoverMergedFinger(for: other, at: CGPoint(x: 77, y: 42), previous: CGPoint(x: 38, y: 42))
        host.recoverMergedFinger(for: other, at: CGPoint(x: 78, y: 42), previous: CGPoint(x: 77, y: 42))
        host.finishTrackedDirectKey(for: other, at: CGPoint(x: 78, y: 42))
        XCTAssertEqual(inserted, ["s", "s", "d"])
        XCTAssertEqual(host.mergedFingerRecoveryCount, 1)
    }

    func testRootMonitorReleaseIsIdempotentWithViewRelease() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        host.directTouchRoutingEnabled = true
        let key = KeyboardButton(type: .custom)
        key.accessibilityLabel = "p"
        key.insertsOnTouchDown = true
        key.frame = CGRect(x: 20, y: 20, width: 45, height: 45)
        var released = 0
        key.addAction(UIAction { _ in released += 1 }, for: .touchUpInside)
        host.addSubview(key)
        let id = ObjectIdentifier(NSObject())
        let center = CGPoint(x: 42, y: 42)
        host.beginTrackedDirectKey(for: id, at: center, early: true)
        host.finishTrackedDirectKey(for: id, at: center)
        host.finishTrackedDirectKey(for: id, at: center)
        XCTAssertEqual(released, 1)
        XCTAssertEqual(host.activeTouchCount, 0)
    }

    func testRowEdgeGapTypesNearestKeyInsteadOfDroppingTouch() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        host.directTouchRoutingEnabled = true
        host.touchExpansion = 6
        let a = KeyboardButton(type: .custom)
        a.accessibilityLabel = "a"
        a.insertsOnTouchDown = true
        a.frame = CGRect(x: 30, y: 20, width: 34, height: 44)
        host.addSubview(a)
        var inserted = 0
        a.addAction(UIAction { _ in inserted += 1 }, for: .touchDown)
        // 18pt left of "a": beyond the hit expansion but in the row's edge inset.
        XCTAssertTrue(host.beginDirectKey(at: CGPoint(x: 12, y: 40)) === a)
        XCTAssertEqual(inserted, 1)
        // Far below the row stays empty.
        XCTAssertNil(host.beginDirectKey(at: CGPoint(x: 8, y: 95)))
    }

    func testDirectTouchRoutingInsertsOnContactOnceAndSupportsSensitivity() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        host.directTouchRoutingEnabled = true
        host.touchExpansion = 12
        let button = KeyboardButton(type: .custom)
        button.insertsOnTouchDown = true
        button.touchExpansion = 12
        button.accessibilityLabel = "q"
        button.frame = CGRect(x: 30, y: 20, width: 45, height: 45)
        host.addSubview(button)
        var inserted = 0
        var released = 0
        button.addAction(UIAction { _ in inserted += 1 }, for: .touchDown)
        button.addAction(UIAction { _ in released += 1 }, for: .touchUpInside)
        let nearEdge = CGPoint(x: 86, y: 42)
        XCTAssertTrue(host.hitTest(nearEdge, with: nil) === host,
                      "The direct route must intercept key hit testing in the extension")
        for count in 1...100 {
            let pressed = host.beginDirectKey(at: nearEdge)
            XCTAssertTrue(pressed === button)
            XCTAssertEqual(inserted, count, "Each touch should insert on finger down")
            if let pressed { host.endDirectKey(pressed, at: nearEdge) }
            XCTAssertEqual(released, count, "Each touch must release exactly once")
        }
        XCTAssertEqual(host.receivedTouchCount, 100)
        XCTAssertEqual(host.routedTouchCount, 100)
        host.directTouchRoutingEnabled = false
        XCTAssertTrue(host.hitTest(nearEdge, with: nil) === button,
                      "The user must be able to restore the previous UIControl route")
        XCTAssertNil(host.beginDirectKey(at: nearEdge))
    }
    func testEarlyRootRoutingDeduplicatesTheSameTouch() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 180, height: 100))
        host.directTouchRoutingEnabled = true
        let key = KeyboardButton(type: .custom)
        key.frame = CGRect(x: 30, y: 20, width: 50, height: 45)
        key.accessibilityLabel = "p"
        key.insertsOnTouchDown = true
        host.addSubview(key)
        var inserted = 0
        key.addAction(UIAction { _ in inserted += 1 }, for: .touchDown)
        let id = ObjectIdentifier(NSObject())
        let point = CGPoint(x: 50, y: 40)
        XCTAssertTrue(host.beginTrackedDirectKey(for: id, at: point, early: true) === key)
        XCTAssertTrue(host.beginTrackedDirectKey(for: id, at: point) === key)
        XCTAssertEqual(inserted, 1, "Root and UIKit callbacks must insert only once")
        XCTAssertEqual(host.receivedTouchCount, 1)
        XCTAssertEqual(host.earlyRootRoutedCount, 1)
    }

    func testDirectTouchRoutingKeepsSpaceNativeForCaretLongPress() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 250, height: 100))
        host.directTouchRoutingEnabled = true
        let space = KeyboardButton(type: .custom)
        space.frame = CGRect(x: 25, y: 20, width: 200, height: 50)
        space.accessibilityLabel = "Space"
        space.insertsOnTouchDown = true
        host.addSubview(space)
        let point = CGPoint(x: 100, y: 45)
        XCTAssertTrue(host.hitTest(point, with: nil) === space)
        XCTAssertNil(host.beginDirectKey(at: point), "The caret long press must stay on Space")
    }
    func testFingerMovementNeverTypesAGhostLetter() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        host.directTouchRoutingEnabled = true
        host.touchExpansion = 10
        var inserted: [String] = []
        for (label, x) in [("q", CGFloat(20)), ("w", CGFloat(73))] {
            let key = KeyboardButton(type: .custom)
            key.accessibilityLabel = label
            key.insertsOnTouchDown = true
            key.frame = CGRect(x: x, y: 20, width: 45, height: 45)
            key.addAction(UIAction { _ in inserted.append(label) }, for: .touchDown)
            host.addSubview(key)
        }
        let id = ObjectIdentifier(NSObject())
        XCTAssertNotNil(host.beginTrackedDirectKey(for: id, at: CGPoint(x: 62, y: 42)))
        // A sloppy tap that drifts into the neighbor before lifting.
        host.touchesMoved([], with: nil)
        host.finishTrackedDirectKey(for: id, at: CGPoint(x: 95, y: 42))
        XCTAssertEqual(inserted, ["q"])
    }

    func testSymbolPagesToggleBothWaysLikeTheSystemKeyboard() throws {
        let (keyboard, proxy) = keyboard()
        keyboard.testingAllowTouchEvents = true
        keyboard.view.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        func allButtons(_ view: UIView) -> [UIButton] {
            (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { allButtons($0) }
        }
        func button(_ label: String) -> UIButton? {
            allButtons(keyboard.view).first { $0.accessibilityLabel == label }
        }
        try XCTUnwrap(button("123")).sendActions(for: .touchUpInside)
        XCTAssertNotNil(button("More symbols"))
        XCTAssertNotNil(button("ABC"))
        XCTAssertEqual(allButtons(keyboard.view).filter { $0.accessibilityLabel == "Delete" }.count, 1,
                       "Symbol pages have exactly one Delete")
        try XCTUnwrap(button("More symbols")).sendActions(for: .touchUpInside)
        XCTAssertNotNil(button("["))
        XCTAssertNotNil(button("€"))
        let back = try XCTUnwrap(button("Numbers"), "The #+= page must offer a way back to 123")
        back.sendActions(for: .touchUpInside)
        XCTAssertNotNil(button("1"))
        XCTAssertNotNil(button("More symbols"))
        try XCTUnwrap(button("?")).sendActions(for: .touchDown)
        try XCTUnwrap(button("?")).sendActions(for: .touchUpInside)
        XCTAssertEqual(proxy.text, "?", "Punctuation types once, on finger-down")
        try XCTUnwrap(button("ABC")).sendActions(for: .touchUpInside)
        XCTAssertNotNil(button("q"))
    }

    func testShiftActsOnFingerDownForRollover() throws {
        let (keyboard, proxy) = keyboard()
        keyboard.testingAllowTouchEvents = true
        func allButtons(_ view: UIView) -> [UIButton] {
            (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { allButtons($0) }
        }
        let shift = try XCTUnwrap(allButtons(keyboard.view).first { $0.accessibilityLabel == "Shift" })
        shift.sendActions(for: .touchDown)
        // Letter lands before Shift is lifted.
        keyboard.testingTypeCharacter("h")
        shift.sendActions(for: .touchUpInside)
        keyboard.testingTypeCharacter("i")
        XCTAssertEqual(proxy.text, "Hi")
    }

    func testKeyboardRequestsPublicEdgeGestureDeferral() {
        let (keyboard, _) = keyboard()
        XCTAssertEqual(keyboard.preferredScreenEdgesDeferringSystemGestures,
                       [.left, .right])
    }

    func testInputRootRoutesKeysAheadOfDecorativeHitTargets() {
        let root = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: 240, height: 160),
                                     inputViewStyle: .default)
        let router = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 240, height: 120))
        router.directTouchRoutingEnabled = true
        let key = KeyboardButton(type: .custom)
        key.accessibilityLabel = "q"
        key.insertsOnTouchDown = true
        key.frame = CGRect(x: 30, y: 25, width: 48, height: 44)
        router.addSubview(key)
        root.addSubview(router)
        // Simulate a material/backdrop layer becoming hittable above the keys.
        let decoration = UIView(frame: root.bounds)
        root.addSubview(decoration)
        root.keyRoutingView = router
        XCTAssertTrue(root.hitTest(CGPoint(x: 50, y: 46), with: nil) === router,
                      "Root hit testing must always return the direct key router")
        XCTAssertTrue(root.hitTest(CGPoint(x: 50, y: 140), with: nil) === decoration,
                      "Root must not steal touches outside the keyboard router")
    }

    func testRootTouchProbeIsDisabledExceptDuringManualDebugger() {
        let (keyboard, _) = keyboard()
        let monitor = keyboard.view.gestureRecognizers?.first { $0 is KeyboardRootTouchMonitor }
        XCTAssertNotNil(monitor)
        XCTAssertFalse(monitor?.isEnabled ?? true,
                       "Normal typing must not attach an active touch logger")
        keyboard.testingToggleTouchDebugger()
        XCTAssertTrue(monitor?.isEnabled == true)
        keyboard.testingToggleTouchDebugger()
        XCTAssertFalse(monitor?.isEnabled ?? true)
        keyboard.testingToggleTouchDebugger()
        XCTAssertFalse(monitor?.isEnabled ?? true)
    }

    func testOptInTouchDebuggerShowsLocalReportWithoutResizingKeyboard() throws {
        let (keyboard, _) = keyboard()
        let originalHeight = try XCTUnwrap(keyboard.inputView as? KeyboardInputView).contentHeight
        keyboard.testingToggleTouchDebugger()
        for letter in "qwerty" { keyboard.testingTypeCharacter(String(letter)) }
        keyboard.testingToggleTouchDebugger()
        let overlay = try XCTUnwrap(keyboard.testingTouchDebugOverlay)
        XCTAssertEqual(overlay.accessibilityIdentifier, "keyboard.touchDebugOverlay")
        func findText(_ parent: UIView) -> UITextView? {
            if let text = parent as? UITextView { return text }
            for child in parent.subviews {
                if let text = findText(child) { return text }
            }
            return nil
        }
        let report = try XCTUnwrap(findText(overlay)?.text)
        XCTAssertTrue(report.contains("Proxy insert calls: 6"))
        XCTAssertTrue(report.contains("Proxy attempt sequence: qwerty"))
        XCTAssertEqual(try XCTUnwrap(keyboard.inputView as? KeyboardInputView).contentHeight, originalHeight)
        keyboard.testingToggleTouchDebugger()
        XCTAssertNil(keyboard.testingTouchDebugOverlay)
    }
    func testTouchDebuggerCanInsertReportWithoutPasteboardAccess() throws {
        let (keyboard, proxy) = keyboard()
        keyboard.testingToggleTouchDebugger()
        for letter in "qwerty" { keyboard.testingTypeCharacter(String(letter)) }
        keyboard.testingToggleTouchDebugger()
        let overlay = try XCTUnwrap(keyboard.testingTouchDebugOverlay)
        func descendants(_ parent: UIView) -> [UIView] {
            [parent] + parent.subviews.flatMap(descendants)
        }
        let insert = try XCTUnwrap(descendants(overlay).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "keyboard.touchDebugInsert" })
        insert.sendActions(for: .touchUpInside)
        XCTAssertTrue(proxy.text.contains("AUKKHOR TOUCH DEBUG (local session)"))
        XCTAssertTrue(proxy.text.contains("Proxy attempt sequence: qwerty"))
        let status = try XCTUnwrap(descendants(overlay).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "keyboard.touchDebugStatus" })
        XCTAssertTrue(status.text?.contains("Inserted in the current text field") == true)
        XCTAssertNotNil(descendants(overlay).first { $0.accessibilityIdentifier == "keyboard.touchDebugCopy" })
    }
    func testDebuggerOverlayTakesPriorityOverUnderlyingKeys() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 250, height: 120))
        host.directTouchRoutingEnabled = true
        let key = KeyboardButton(type: .custom)
        key.frame = CGRect(x: 20, y: 50, width: 200, height: 60)
        key.insertsOnTouchDown = true
        host.addSubview(key)
        let overlay = UIView(frame: host.bounds)
        let copy = UIButton(type: .system)
        copy.frame = CGRect(x: 20, y: 50, width: 200, height: 60)
        overlay.addSubview(copy)
        host.addSubview(overlay)
        host.modalOverlay = overlay
        XCTAssertTrue(host.hitTest(CGPoint(x: 100, y: 80), with: nil) === copy)
        host.modalOverlay = nil
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
    func testLegacyClearPrismMigratesToFastSystemCanvasWithoutLens() throws {
        let savedPreset = KeyboardPreferences.preset
        let savedStyle = KeyboardPreferences.keycapStyle
        let savedSeamless = KeyboardPreferences.seamlessBackground
        let savedGlass = KeyboardPreferences.usesGlass
        let savedClear = KeyboardPreferences.clearGlass
        defer {
            KeyboardPreferences.preset = savedPreset
            KeyboardPreferences.keycapStyle = savedStyle
            KeyboardPreferences.seamlessBackground = savedSeamless
            KeyboardPreferences.usesGlass = savedGlass
            KeyboardPreferences.clearGlass = savedClear
        }
        AukkhorSettings.defaults.set(KeyboardPreset.clearPrism.rawValue, forKey: "keyboardPreset")
        KeyboardPreferences.keycapStyle = 0
        KeyboardPreferences.seamlessBackground = false
        KeyboardPreferences.usesGlass = true
        KeyboardPreferences.clearGlass = true
        XCTAssertEqual(KeyboardPreferences.preset, .system)
        XCTAssertFalse(KeyboardPreferences.glassEnabled)
        XCTAssertTrue(KeyboardPreferences.seamlessBackground)
        XCTAssertFalse(KeyboardPreferences.clearGlass)
        XCTAssertFalse(KeyboardPreset.allCases.contains(.clearPrism))
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        func views(_ parent: UIView) -> [UIView] { [parent] + parent.subviews.flatMap(views) }
        let all = views(keyboard.view)
        let effects = all.compactMap { $0 as? UIVisualEffectView }
        XCTAssertEqual(effects.count, 1)
        let lens = try XCTUnwrap(all.compactMap { $0 as? KeyboardPressLensView }.first)
        XCTAssertTrue(lens.isHidden)
        XCTAssertFalse(all.contains { $0.accessibilityIdentifier == "keyboard.panelLens" })
        XCTAssertTrue(KeyboardPreferences.usesSystemCanvas)
        XCTAssertNil(effects.first?.effect, "No live glass or blur is allowed on the migrated canvas")
        let surface = try XCTUnwrap(all.first { $0.accessibilityIdentifier == "keyboard.surface" })
        XCTAssertEqual(surface.layer.cornerRadius, 0)
        XCTAssertEqual(surface.backgroundColor?.cgColor.alpha ?? 1, 0)
        XCTAssertTrue(all.compactMap { $0 as? UIButton }.allSatisfy {
            !$0.subviews.contains { $0 is UIVisualEffectView }
        })
        let letter = try XCTUnwrap(all.compactMap { $0 as? KeyboardButton }
            .first(where: { $0.title(for: .normal) == "q" }))
        XCTAssertFalse(letter.usesPressLens)
        letter.isHighlighted = true
        XCTAssertTrue(lens.isHidden, "No old bubble around an individual key")
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
        KeyboardPreferences.preset = .system
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
        XCTAssertNotNil(all.compactMap { $0 as? UIButton }
            .first { $0.title(for: .normal)?.hasPrefix("Touch:") == true },
            "Keep sensitivity accessible in the existing expanded gear panel")
        XCTAssertNotNil(all.compactMap { $0 as? UIButton }
            .first { $0.accessibilityLabel == "Touch debugger" },
            "The blocked app-launch gear should offer an in-keyboard debugger")
        XCTAssertNotNil(all.compactMap { $0 as? UIButton }
            .first { $0.accessibilityLabel == "Keyboard settings" },
            "Keep the right gear for existing keyboard settings")
        keyboard.toggleAppearancePanel()
        for label in ["q", "a", "z", "Space", "return"] {
            let key = try XCTUnwrap(views(keyboard.view).compactMap { $0 as? KeyboardButton }
                .first(where: { $0.accessibilityLabel == label }))
            XCTAssertTrue(key.insertsOnTouchDown, "\(label) must not wait for finger release")
        }
    }
    func testRetiredClearPrismCannotBeSelectedAgain() {
        let savedPreset = KeyboardPreferences.preset
        defer { KeyboardPreferences.preset = savedPreset }
        KeyboardPreferences.preset = .clearPrism
        XCTAssertEqual(KeyboardPreferences.preset, .system)
        XCTAssertEqual(KeyboardPalette.selected(dark: false).foreground, UIColor.label)
    }
}
