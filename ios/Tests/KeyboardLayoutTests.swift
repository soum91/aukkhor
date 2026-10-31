import XCTest
import UIKit
@testable import Aukkhor

private final class KeyboardHostField: UITextField {
    var suppliedKeyboard: UIInputViewController?
    override var inputViewController: UIInputViewController? { suppliedKeyboard }
}

@MainActor final class KeyboardLayoutTests: XCTestCase {
    private func buttons(in view: UIView) -> [UIButton] {
        (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    private func capture(_ keyboard: KeyboardViewController, name: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("No window scene for on-screen keyboard evidence")
            return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = keyboard.view.frame
        window.rootViewController = keyboard
        window.isHidden = false
        keyboard.view.layoutIfNeeded()
        let rendered = UIGraphicsImageRenderer(bounds: keyboard.view.bounds).image { _ in
            keyboard.view.drawHierarchy(in: keyboard.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }

    func testNativeGeometryAndBackgroundRemoval() {
        let savedNumberRow = KeyboardPreferences.numberRow
        let savedStyle = KeyboardPreferences.keycapStyle
        let savedSide = KeyboardPreferences.oneHandSide
        let savedPreset = KeyboardPreferences.preset
        defer {
            KeyboardPreferences.numberRow = savedNumberRow
            KeyboardPreferences.keycapStyle = savedStyle
            KeyboardPreferences.oneHandSide = savedSide
            KeyboardPreferences.preset = savedPreset
        }
        for numberRow in [false, true] {
            KeyboardPreferences.numberRow = numberRow
            for width: CGFloat in [320, 390, 430, 844] {
            for side in [0, 1, 2] {
                for preset: KeyboardPreset in [.system, .fullBlack, .liquidGlass, .custom] {
                    KeyboardPreferences.keycapStyle = 2
                    KeyboardPreferences.oneHandSide = side
                    KeyboardPreferences.preset = preset
                    let keyboard = KeyboardViewController()
                    keyboard.isPreview = true
                    keyboard.loadViewIfNeeded()
                    keyboard.view.frame = CGRect(x: 0, y: 0, width: width, height: KeyboardPreferences.typingHeight)
                    keyboard.view.layoutIfNeeded()
                    let all = buttons(in: keyboard.view)
                    func key(_ title: String) -> UIButton {
                        all.first { $0.title(for: .normal) == title }!
                    }
                    let q = key("q"), a = key("a"), z = key("z")
                    XCTAssertEqual(q.bounds.width, a.bounds.width, accuracy: 0.5)
                    XCTAssertEqual(q.bounds.width, z.bounds.width, accuracy: 0.5)
                    let shift = all.first { $0.accessibilityLabel == "Shift" }!
                    let delete = all.first { $0.accessibilityLabel == "Delete" }!
                    let space = all.first { $0.accessibilityLabel == "Space" }!
                    XCTAssertEqual(shift.convert(shift.bounds, to: keyboard.view).midY,
                                   z.convert(z.bounds, to: keyboard.view).midY, accuracy: 0.5)
                    XCTAssertEqual(delete.convert(delete.bounds, to: keyboard.view).midY,
                                   z.convert(z.bounds, to: keyboard.view).midY, accuracy: 0.5)
                    XCTAssertGreaterThan(space.bounds.width, q.bounds.width * 3.8)
                    XCTAssertEqual(space.convert(space.bounds, to: keyboard.view).maxY,
                                   keyboard.view.bounds.maxY, accuracy: 0.5,
                                   "No duplicate Aukkhor footer below Space")
                    for button in all {
                        XCTAssertEqual(button.backgroundColor?.cgColor.alpha ?? 0, 0)
                        XCTAssertEqual(button.layer.borderWidth, 0)
                        XCTAssertEqual(button.layer.shadowOpacity, 0)
                        XCTAssertFalse(button.subviews.contains { $0 is UIVisualEffectView })
                    }
                    if width == 390 && preset == .liquidGlass {
                        capture(keyboard, name: "background-free-side-\(side)-numbers-\(numberRow)")
                    }
                }
            }
        }
        }
    }

    func testCompactControlsAndStableTypingViews() {
        let oldHeight = KeyboardPreferences.keyHeight
        let oldNumbers = KeyboardPreferences.numberRow
        defer {
            KeyboardPreferences.keyHeight = oldHeight
            KeyboardPreferences.numberRow = oldNumbers
        }
        KeyboardPreferences.keyHeight = 43
        KeyboardPreferences.numberRow = false
        KeyboardPreferences.oneHandSide = 0
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.keycapStyle = 0
        XCTAssertEqual(KeyboardPreferences.typingHeight, 220)
        for needsSwitcher in [false, true] {
            let keyboard = KeyboardViewController()
            keyboard.isPreview = true
            keyboard.previewNeedsInputModeSwitchKey = needsSwitcher
            keyboard.loadViewIfNeeded()
            keyboard.view.frame = CGRect(x: 0, y: 0, width: 390, height: KeyboardPreferences.typingHeight)
            keyboard.view.layoutIfNeeded()
            let all = buttons(in: keyboard.view)
            XCTAssertEqual(all.filter { $0.accessibilityLabel == "Next keyboard" && !$0.isHidden }.count,
                           needsSwitcher ? 1 : 0)
            let letterKeys = ["q", "a", "z"].map { title in all.first { $0.title(for: .normal) == title }! }
            let q = letterKeys[0]
            let material = q.subviews.first { $0 is UIVisualEffectView }!
            let oldFrame = q.convert(q.bounds, to: keyboard.view)
            keyboard.tapShift()
            keyboard.view.layoutIfNeeded()
            let capitalQ = buttons(in: keyboard.view).first { $0.title(for: .normal) == "Q" }!
            for (button, title) in zip(letterKeys, ["Q", "A", "Z"]) {
                XCTAssertTrue(button === buttons(in: keyboard.view).first { $0.title(for: .normal) == title },
                              "Shift updates every letter row without rebuilding keys")
            }
            XCTAssertTrue(q === capitalQ, "Shift updates labels without rebuilding letter keys")
            XCTAssertTrue(material === capitalQ.subviews.first { $0 is UIVisualEffectView })
            XCTAssertEqual(oldFrame, capitalQ.convert(capitalQ.bounds, to: keyboard.view))
            keyboard.show("Clipboard sent")
            keyboard.view.layoutIfNeeded()
            XCTAssertEqual(oldFrame, capitalQ.convert(capitalQ.bounds, to: keyboard.view),
                           "Status messages must not shift typing targets")
        }
        KeyboardPreferences.numberRow = true
        XCTAssertEqual(KeyboardPreferences.typingHeight, 269)
    }

    func testSelfSizingKeyboardInsideResponderHost() async throws {
        let savedNumber = KeyboardPreferences.numberRow
        let savedSide = KeyboardPreferences.oneHandSide
        let savedPreset = KeyboardPreferences.preset
        let savedStyle = KeyboardPreferences.keycapStyle
        defer {
            KeyboardPreferences.numberRow = savedNumber
            KeyboardPreferences.oneHandSide = savedSide
            KeyboardPreferences.preset = savedPreset
            KeyboardPreferences.keycapStyle = savedStyle
        }
        KeyboardPreferences.numberRow = true
        KeyboardPreferences.oneHandSide = 2
        KeyboardPreferences.preset = .fullBlack
        KeyboardPreferences.keycapStyle = 2
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let root = try XCTUnwrap(keyboard.inputView as? KeyboardInputView)
        XCTAssertTrue(root.allowsSelfSizing)
        XCTAssertFalse(root.isOpaque)
        XCTAssertEqual(root.backgroundColor?.cgColor.alpha ?? 0, 0)
        for width: CGFloat in [320, 390, 430, 844] {
            XCTAssertEqual(root.systemLayoutSizeFitting(CGSize(width: width, height: 1000)),
                           CGSize(width: width, height: KeyboardPreferences.typingHeight))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        let field = KeyboardHostField(frame: CGRect(x: 20, y: 100, width: 250, height: 44))
        field.suppliedKeyboard = keyboard
        field.keyboardAppearance = .dark
        host.view.addSubview(field)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        XCTAssertTrue(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(800))
        keyboard.view.layoutIfNeeded()
        XCTAssertNotNil(root.window, "Exercise UIKit's real responder input-view presentation")
        XCTAssertEqual(root.bounds.height, KeyboardPreferences.typingHeight, accuracy: 1)
        let surface = try XCTUnwrap(root.subviews.first { $0.accessibilityIdentifier == "keyboard.surface" })
        XCTAssertEqual(surface.frame, root.bounds, "Background fills the hosted input view without an inset band")
        XCTAssertEqual(surface.layer.cornerRadius, 20)
        let space = try XCTUnwrap(buttons(in: root).first { $0.accessibilityLabel == "Space" })
        XCTAssertEqual(space.convert(space.bounds, to: root).maxY, root.bounds.maxY, accuracy: 0.5)
        let image = UIGraphicsImageRenderer(bounds: root.bounds).image { _ in
            root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "hosted-full-black-with-numbers"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSuggestionsReuseButtonsAndRejectStaleResults() async throws {
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let candidateButtons = buttons(in: keyboard.view).filter {
            $0.accessibilityIdentifier?.hasPrefix("keyboard.candidate.") == true
        }
        XCTAssertEqual(candidateButtons.count, 3)
        keyboard.requestSuggestions(prefix: "he", phonetic: false, bangla: false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(candidateButtons.contains { $0.title(for: .normal) == "hello" })
        for i in 0..<100 {
            keyboard.requestSuggestions(prefix: "h\(i)", phonetic: false, bangla: false)
        }
        keyboard.requestSuggestions(prefix: "key", phonetic: false, bangla: false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(candidateButtons.contains { $0.title(for: .normal) == "keyboard" && !$0.isHidden })
        let after = buttons(in: keyboard.view).filter {
            $0.accessibilityIdentifier?.hasPrefix("keyboard.candidate.") == true
        }
        XCTAssertEqual(after.map(ObjectIdentifier.init), candidateButtons.map(ObjectIdentifier.init))
        keyboard.requestSuggestions(prefix: "", phonetic: false, bangla: false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(candidateButtons.allSatisfy(\.isHidden), "An older lookup must not repaint after clearing input")
    }

    func testGlassAndSpaceUseSameAppearance() {
        KeyboardPreferences.oneHandSide = 0
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.keycapStyle = 0
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        keyboard.view.frame = CGRect(x: 0, y: 0, width: 390, height: KeyboardPreferences.typingHeight)
        keyboard.view.layoutIfNeeded()
        let all = buttons(in: keyboard.view)
        let q = all.first { $0.title(for: .normal) == "q" }!
        let space = all.first { $0.accessibilityLabel == "Space" }!
        for button in [q, space] {
            XCTAssertTrue(button.subviews.contains { $0 is UIVisualEffectView })
            XCTAssertEqual(button.layer.cornerRadius, KeyboardPreferences.cornerRadius)
        }
        for button in all where button.image(for: .normal) != nil {
            if let backdropIndex = button.subviews.firstIndex(where: { $0 is UIVisualEffectView }),
               let imageView = button.imageView,
               let iconIndex = button.subviews.firstIndex(of: imageView) {
                XCTAssertGreaterThan(iconIndex, backdropIndex, "Glass must stay behind symbols")
            }
        }
        capture(keyboard, name: "liquid-glass-keycaps")
    }
}
