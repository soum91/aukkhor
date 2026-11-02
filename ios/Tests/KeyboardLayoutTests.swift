import XCTest
import UIKit
@testable import Aukkhor

private final class GlassTestBackdrop: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let colors = ["#143B68", "#16716F", "#5B327E", "#955332", "#17314A", "#4E315E"]
        let width = bounds.width / CGFloat(colors.count)
        for (index, hex) in colors.enumerated() {
            context.setFillColor(UIColor(keyboardHex: hex).cgColor)
            context.fill(CGRect(x: CGFloat(index) * width, y: 0, width: width + 1, height: bounds.height))
        }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(3)
        for y in stride(from: CGFloat(25), to: bounds.height, by: 45) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y + 25))
        }
        context.strokePath()
    }
}

private final class KeyboardHostField: UITextField {
    var suppliedKeyboard: UIInputViewController?
    override var inputViewController: UIInputViewController? { suppliedKeyboard }
}

@MainActor final class KeyboardLayoutTests: XCTestCase {
    private var evidenceWindow: UIWindow?
    private var evidenceKeyboard: ObjectIdentifier?
    private func buttons(in view: UIView) -> [UIButton] {
        (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    private func capture(_ keyboard: KeyboardViewController, name: String, patternedBackdrop: Bool = false) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("No window scene for on-screen keyboard evidence")
            return
        }
        let window: UIWindow
        if patternedBackdrop, evidenceKeyboard == ObjectIdentifier(keyboard), let existing = evidenceWindow {
            // Updating a panel should resize the existing window, as it does on-device.
            // Moving a live material to another window invalidates its backdrop group.
            window = existing
            window.frame = keyboard.view.frame
            window.rootViewController?.view.frame = window.bounds
            keyboard.view.frame = window.bounds
        } else {
            evidenceWindow?.isHidden = true
            evidenceWindow = nil
            evidenceKeyboard = nil
            window = UIWindow(windowScene: scene)
            window.frame = keyboard.view.frame
            if patternedBackdrop {
                let host = UIViewController()
                host.view.frame = window.bounds
                let pattern = GlassTestBackdrop(frame: window.bounds)
                pattern.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                host.view.addSubview(pattern)
                if keyboard.parent != nil {
                    keyboard.willMove(toParent: nil)
                    keyboard.view.removeFromSuperview()
                    keyboard.removeFromParent()
                }
                host.addChild(keyboard)
                host.view.addSubview(keyboard.view)
                keyboard.view.frame = window.bounds
                keyboard.didMove(toParent: host)
                window.rootViewController = host
                evidenceWindow = window
                evidenceKeyboard = ObjectIdentifier(keyboard)
            } else { window.rootViewController = keyboard }
        }
        window.isHidden = false
        let target = patternedBackdrop ? window.rootViewController!.view! : keyboard.view!
        target.layoutIfNeeded()
        let rendered = UIGraphicsImageRenderer(bounds: target.bounds).image { _ in
            target.drawHierarchy(in: target.bounds, afterScreenUpdates: true)
        }
        // Freeze the pixel buffer before another test changes an effect or window.
        let snapshot = rendered.pngData().flatMap(UIImage.init(data:)) ?? rendered
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if !patternedBackdrop { window.isHidden = true }
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
        let oldScale = KeyboardPreferences.heightScale
        let oldNumbers = KeyboardPreferences.numberRow
        defer {
            KeyboardPreferences.keyHeight = oldHeight
            KeyboardPreferences.heightScale = oldScale
            KeyboardPreferences.numberRow = oldNumbers
        }
        KeyboardPreferences.keyHeight = 43
        KeyboardPreferences.heightScale = 0.9
        KeyboardPreferences.numberRow = false
        KeyboardPreferences.oneHandSide = 0
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.keycapStyle = 0
        XCTAssertEqual(KeyboardPreferences.typingHeight, 196)
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
            let canvas = keyboard.view.subviews.flatMap { $0.subviews }
                .first { $0.accessibilityIdentifier == "keyboard.canvasGlass" } as? UIVisualEffectView
            XCTAssertNotNil(canvas, "One shared canvas supplies the entire keyboard")
            let oldFrame = q.convert(q.bounds, to: keyboard.view)
            keyboard.tapShift()
            keyboard.view.layoutIfNeeded()
            let capitalQ = buttons(in: keyboard.view).first { $0.title(for: .normal) == "Q" }!
            for (button, title) in zip(letterKeys, ["Q", "A", "Z"]) {
                XCTAssertTrue(button === buttons(in: keyboard.view).first { $0.title(for: .normal) == title },
                              "Shift updates every letter row without rebuilding keys")
            }
            XCTAssertTrue(q === capitalQ, "Shift updates labels without rebuilding letter keys")
            XCTAssertFalse(capitalQ.subviews.contains { $0 is UIVisualEffectView },
                           "Fast keys must never own separate backdrop effects")
            XCTAssertEqual(oldFrame, capitalQ.convert(capitalQ.bounds, to: keyboard.view))
            keyboard.show("Clipboard sent")
            keyboard.view.layoutIfNeeded()
            XCTAssertEqual(oldFrame, capitalQ.convert(capitalQ.bounds, to: keyboard.view),
                           "Status messages must not shift typing targets")
        }
        KeyboardPreferences.numberRow = true
        XCTAssertEqual(KeyboardPreferences.typingHeight, 239)
        KeyboardPreferences.heightScale = 1
        XCTAssertEqual(KeyboardPreferences.typingHeight, 259, "Height control must resize the entire row stack")
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
        XCTAssertGreaterThan(root.bounds.width, 250, "Keyboard must be visible at a usable width on first presentation")
        XCTAssertEqual(root.bounds.height, KeyboardPreferences.typingHeight, accuracy: 1)
        let surface = try XCTUnwrap(root.subviews.first { $0.accessibilityIdentifier == "keyboard.surface" })
        XCTAssertEqual(surface.frame, root.bounds, "Background fills the hosted input view without an inset band")
        XCTAssertEqual(surface.layer.cornerRadius, 20)
        let space = try XCTUnwrap(buttons(in: root).first { $0.accessibilityLabel == "Space" })
        XCTAssertEqual(space.convert(space.bounds, to: root).maxY, root.bounds.maxY, accuracy: 0.5)
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: root.bounds).image { _ in
            rendered = root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "Hosted keyboard evidence must contain a completed screen render")
        XCTAssertGreaterThan(image.size.width, 250)
        XCTAssertGreaterThan(image.size.height, 180)
        let attachment = XCTAttachment(image: image)
        attachment.name = "hosted-full-black-with-numbers"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExpandedSettingsActuallyResizesHostedKeyboard() async throws {
        let savedPreset = KeyboardPreferences.preset
        let savedNumbers = KeyboardPreferences.numberRow
        let savedSide = KeyboardPreferences.oneHandSide
        let savedSeamless = KeyboardPreferences.seamlessBackground
        let savedKeycaps = KeyboardPreferences.keycapStyle
        defer {
            KeyboardPreferences.preset = savedPreset
            KeyboardPreferences.numberRow = savedNumbers
            KeyboardPreferences.oneHandSide = savedSide
            KeyboardPreferences.seamlessBackground = savedSeamless
            KeyboardPreferences.keycapStyle = savedKeycaps
        }
        KeyboardPreferences.preset = .system
        KeyboardPreferences.numberRow = false
        KeyboardPreferences.oneHandSide = 0
        KeyboardPreferences.seamlessBackground = true
        KeyboardPreferences.keycapStyle = 0
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let root = try XCTUnwrap(keyboard.inputView as? KeyboardInputView)
        let initialHeight = KeyboardPreferences.typingHeight

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        let field = KeyboardHostField(frame: CGRect(x: 20, y: 80, width: 250, height: 44))
        field.suppliedKeyboard = keyboard
        host.view.addSubview(field)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        XCTAssertTrue(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNotNil(root.window)
        XCTAssertEqual(root.bounds.height, initialHeight, accuracy: 1)

        keyboard.toggleAppearancePanel()
        try await Task.sleep(for: .milliseconds(600))
        root.layoutIfNeeded()
        XCTAssertGreaterThan(root.bounds.height, initialHeight + 150,
                             "UIKit must expand the *visible* input view, not merely record a desired height")
        XCTAssertEqual(root.bounds.height, root.contentHeight, accuracy: 1)
        for title in ["Keycaps: Normal", "Opacity −", "Background: iOS", "Text", "space"] {
            let button = try XCTUnwrap(buttons(in: root).first { $0.title(for: .normal) == title },
                                       "Missing settings control: \(title)")
            let frame = button.convert(button.bounds, to: root)
            XCTAssertGreaterThan(frame.width, 0, "\(title) was horizontally squished")
            XCTAssertLessThanOrEqual(frame.maxY, root.bounds.maxY + 1,
                                     "\(title) is clipped below the visible settings panel")
        }
        keyboard.toggleAppearancePanel()
        try await Task.sleep(for: .milliseconds(400))
        root.layoutIfNeeded()
        XCTAssertEqual(root.bounds.height, initialHeight, accuracy: 1,
                       "Closing settings must restore the original compact keyboard")
    }

    // Release regression coverage for narrow keys and the gaps between them.
    func testKeyTouchToleranceAndGaps() {
        let host = KeyboardInteractionView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        let first = KeyboardButton(type: .custom)
        let second = KeyboardButton(type: .custom)
        first.frame = CGRect(x: 4, y: 4, width: 40, height: 36)
        second.frame = CGRect(x: 50, y: 4, width: 40, height: 36)
        host.addSubview(first)
        host.addSubview(second)
        XCTAssertTrue(host.hitTest(CGPoint(x: 45, y: 22), with: nil) === first)
        XCTAssertTrue(host.hitTest(CGPoint(x: 49, y: 22), with: nil) === second)
        XCTAssertTrue(first.point(inside: CGPoint(x: 43, y: 18), with: nil))
        XCTAssertFalse(first.point(inside: CGPoint(x: 48, y: 18), with: nil))
        second.isHidden = true
        XCTAssertFalse(host.hitTest(CGPoint(x: 70, y: 22), with: nil) === second)
        XCTAssertNil(host.hitTest(CGPoint(x: -1, y: 22), with: nil))
    }

    func testSystemCanvasHasNoSeparatePanel() {
        let oldPreset = KeyboardPreferences.preset
        let oldStyle = KeyboardPreferences.keycapStyle
        let oldSeamless = KeyboardPreferences.seamlessBackground
        let oldNumbers = KeyboardPreferences.numberRow
        defer {
            KeyboardPreferences.preset = oldPreset
            KeyboardPreferences.keycapStyle = oldStyle
            KeyboardPreferences.seamlessBackground = oldSeamless
            KeyboardPreferences.numberRow = oldNumbers
        }
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.seamlessBackground = true
        for style in [0, 2] {
            KeyboardPreferences.keycapStyle = style
            for numbers in [false, true] {
                KeyboardPreferences.numberRow = numbers
                let keyboard = KeyboardViewController()
                keyboard.isPreview = true
                keyboard.loadViewIfNeeded()
                keyboard.view.frame = CGRect(x: 0, y: 0, width: 390, height: KeyboardPreferences.typingHeight)
                keyboard.view.layoutIfNeeded()
                XCTAssertEqual((keyboard.inputView as? KeyboardInputView)?.inputViewStyle, .default,
                               "The root must not add opaque keyboard chrome over the host plate")
                let surface = keyboard.view.subviews.first { $0.accessibilityIdentifier == "keyboard.surface" }!
                let canvas = surface.subviews.first { $0.accessibilityIdentifier == "keyboard.canvasGlass" } as! UIVisualEffectView
                XCTAssertNil(canvas.effect, "Do not draw a second material inside the system keyboard plate")
                XCTAssertEqual(surface.backgroundColor?.cgColor.alpha ?? 1, 0)
                XCTAssertEqual(surface.layer.cornerRadius, 0)
                XCTAssertEqual(canvas.layer.cornerRadius, 0)
                XCTAssertEqual(surface.frame, keyboard.view.bounds)
                XCTAssertEqual(canvas.frame, surface.bounds)
                XCTAssertFalse(canvas.isUserInteractionEnabled,
                               "The decorative canvas must never participate in key hit testing")
                let interactionHost = surface.subviews.first {
                    $0.accessibilityIdentifier == "keyboard.interactionHost"
                }!
                XCTAssertTrue(interactionHost.isUserInteractionEnabled)
                XCTAssertTrue(surface.subviews.last === interactionHost,
                              "The key host must stay above every decorative layer")
                let space = buttons(in: keyboard.view).first { $0.accessibilityLabel == "Space" }!
                let center = space.convert(CGPoint(x: space.bounds.midX, y: space.bounds.midY),
                                           to: keyboard.view)
                XCTAssertTrue(keyboard.view.hitTest(center, with: nil) === space,
                              "A visible key must be the actual hit-test target in system-canvas mode")
                XCTAssertEqual(space.convert(space.bounds, to: keyboard.view).maxY,
                               keyboard.view.bounds.maxY, accuracy: 0.5)
                keyboard.toggleAppearancePanel()
                XCTAssertNil(canvas.effect, "Settings must use the same seamless background")
                keyboard.beginAppearanceTransition(true, animated: false)
                keyboard.endAppearanceTransition()
                XCTAssertNil(canvas.effect, "Reopening must not reintroduce the inner panel")
            }
        }
    }

    func testAdaptiveGlassOverBlackInResponderWindow() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native glass needs iOS 26+") }
        let defaults = AukkhorSettings.defaults
        let savedClear = defaults.object(forKey: "keyboardClearGlass")
        let savedPreset = KeyboardPreferences.preset
        let savedStyle = KeyboardPreferences.keycapStyle
        let savedNumbers = KeyboardPreferences.numberRow
        let savedSeamless = KeyboardPreferences.seamlessBackground
        defer {
            if let savedClear { defaults.set(savedClear, forKey: "keyboardClearGlass") }
            else { defaults.removeObject(forKey: "keyboardClearGlass") }
            KeyboardPreferences.preset = savedPreset
            KeyboardPreferences.keycapStyle = savedStyle
            KeyboardPreferences.numberRow = savedNumbers
            KeyboardPreferences.seamlessBackground = savedSeamless
        }
        KeyboardPreferences.seamlessBackground = false
        defaults.removeObject(forKey: "keyboardClearGlass")
        XCTAssertFalse(KeyboardPreferences.clearGlass, "Existing unset preferences must use adaptive glass")
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.keycapStyle = 2
        KeyboardPreferences.numberRow = true
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let root = try XCTUnwrap(keyboard.inputView as? KeyboardInputView)
        XCTAssertEqual(root.inputViewStyle, .default, "Let the host supply native keyboard chrome")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view.backgroundColor = .black
        host.overrideUserInterfaceStyle = .dark
        let field = KeyboardHostField(frame: CGRect(x: 20, y: 100, width: 250, height: 44))
        field.suppliedKeyboard = keyboard
        field.keyboardAppearance = .dark
        host.view.addSubview(field)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        for appearance in 0..<2 {
            XCTAssertTrue(field.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(800))
            keyboard.view.layoutIfNeeded()
            XCTAssertNotNil(root.window)
            let glass = try XCTUnwrap(root.subviews.flatMap { $0.subviews }
                .first { $0.accessibilityIdentifier == "keyboard.canvasGlass" } as? UIVisualEffectView)
            XCTAssertTrue(glass.effect is UIGlassEffect)
            XCTAssertEqual(glass.alpha, 1)
            let image = UIGraphicsImageRenderer(bounds: root.bounds).image { _ in
                root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
            }
            let cg = try XCTUnwrap(image.cgImage)
            let count = cg.width * cg.height
            var pixels = [UInt8](repeating: 0, count: count * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            let materialPixels = stride(from: 0, to: pixels.count, by: 4).filter {
                let peak = max(pixels[$0], max(pixels[$0 + 1], pixels[$0 + 2]))
                return peak > 8 && peak < 200
            }.count
            XCTAssertGreaterThan(materialPixels, count / 4,
                "Adaptive material must render a visible surface over black, not just white labels")
            let attachment = XCTAttachment(image: image)
            attachment.name = "hosted-adaptive-glass-black-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            field.resignFirstResponder()
            try await Task.sleep(for: .milliseconds(300))
        }
    }

    func testSuggestionsReuseButtonsAndRejectStaleResults() async throws {
        let oldSuggestions = KeyboardPreferences.suggestions
        KeyboardPreferences.suggestions = true
        defer { KeyboardPreferences.suggestions = oldSuggestions }
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let candidateButtons = buttons(in: keyboard.view).filter {
            $0.accessibilityIdentifier?.hasPrefix("keyboard.candidate.") == true
        }
        XCTAssertEqual(candidateButtons.count, 3)
        keyboard.requestSuggestions(prefix: "he", phonetic: false, bangla: false)
        for _ in 0..<100 {
            if candidateButtons.contains(where: { $0.title(for: .normal) == "hello" }) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(candidateButtons.contains { $0.title(for: .normal) == "hello" },
                      "A fresh completion must reach the persistent candidate buttons")
        for i in 0..<100 {
            keyboard.requestSuggestions(prefix: "h\(i)", phonetic: false, bangla: false)
        }
        keyboard.requestSuggestions(prefix: "key", phonetic: false, bangla: false)
        for _ in 0..<100 {
            if candidateButtons.contains(where: { $0.title(for: .normal) == "keyboard" && !$0.isHidden }) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(candidateButtons.contains { $0.title(for: .normal) == "keyboard" && !$0.isHidden })
        let after = buttons(in: keyboard.view).filter {
            $0.accessibilityIdentifier?.hasPrefix("keyboard.candidate.") == true
        }
        XCTAssertEqual(after.map(ObjectIdentifier.init), candidateButtons.map(ObjectIdentifier.init))
        keyboard.requestSuggestions(prefix: "", phonetic: false, bangla: false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(candidateButtons.allSatisfy(\.isHidden), "An older lookup must not repaint after clearing input")
    }

    func testReopeningUnchangedKeyboardKeepsButtons() throws {
        let oldStyle = KeyboardPreferences.keycapStyle
        let oldPreset = KeyboardPreferences.preset
        let oldSide = KeyboardPreferences.oneHandSide
        defer {
            KeyboardPreferences.keycapStyle = oldStyle
            KeyboardPreferences.preset = oldPreset
            KeyboardPreferences.oneHandSide = oldSide
        }
        KeyboardPreferences.keycapStyle = 0
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.oneHandSide = 0
        let keyboard = KeyboardViewController()
        keyboard.isPreview = true
        keyboard.loadViewIfNeeded()
        let q = try XCTUnwrap(buttons(in: keyboard.view).first { $0.title(for: .normal) == "q" })
        for _ in 0..<2 {
            keyboard.beginAppearanceTransition(true, animated: false)
            keyboard.endAppearanceTransition()
            XCTAssertTrue(q === buttons(in: keyboard.view).first { $0.title(for: .normal) == "q" })
            keyboard.beginAppearanceTransition(false, animated: false)
            keyboard.endAppearanceTransition()
        }
        KeyboardPreferences.keycapStyle = 2
        keyboard.beginAppearanceTransition(true, animated: false)
        keyboard.endAppearanceTransition()
        let updatedQ = try XCTUnwrap(buttons(in: keyboard.view).first { $0.title(for: .normal) == "q" })
        XCTAssertFalse(q === updatedQ, "Changed preferences must still refresh on the next appearance")
        XCTAssertFalse(updatedQ.subviews.contains { $0 is UIVisualEffectView })
    }

    func testCanvasGlassSurvivesKeycapRemovalAndSettingsPanel() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native glass requires the iOS 26+ runtime") }
        let oldPreset = KeyboardPreferences.preset
        let oldStyle = KeyboardPreferences.keycapStyle
        let oldGlass = KeyboardPreferences.usesGlass
        let oldClear = KeyboardPreferences.clearGlass
        let oldTint = KeyboardPreferences.glassTintStrength
        let oldInteractive = KeyboardPreferences.interactiveGlass
        let oldSide = KeyboardPreferences.oneHandSide
        let oldForeground = KeyboardPreferences.customForeground
        let oldSeamless = KeyboardPreferences.seamlessBackground
        defer {
            KeyboardPreferences.preset = oldPreset
            KeyboardPreferences.keycapStyle = oldStyle
            KeyboardPreferences.usesGlass = oldGlass
            KeyboardPreferences.clearGlass = oldClear
            KeyboardPreferences.glassTintStrength = oldTint
            KeyboardPreferences.interactiveGlass = oldInteractive
            KeyboardPreferences.oneHandSide = oldSide
            KeyboardPreferences.customForeground = oldForeground
            KeyboardPreferences.seamlessBackground = oldSeamless
        }
        KeyboardPreferences.seamlessBackground = false
        KeyboardPreferences.preset = .custom
        KeyboardPreferences.customForeground = "#FFFFFF"
        KeyboardPreferences.usesGlass = true
        KeyboardPreferences.keycapStyle = 2
        KeyboardPreferences.oneHandSide = 2
        KeyboardPreferences.glassTintStrength = 0.08
        KeyboardPreferences.interactiveGlass = true
        func canvas(in view: UIView) -> UIVisualEffectView? {
            if let effect = view as? UIVisualEffectView,
               effect.accessibilityIdentifier == "keyboard.canvasGlass" { return effect }
            return view.subviews.compactMap { canvas(in: $0) }.first
        }
        for clear in [true, false] {
            KeyboardPreferences.clearGlass = clear
            let keyboard = KeyboardViewController()
            keyboard.isPreview = true
            keyboard.loadViewIfNeeded()
            keyboard.view.frame = CGRect(x: 0, y: 0, width: 390, height: KeyboardPreferences.typingHeight)
            keyboard.view.layoutIfNeeded()
            let glass = try XCTUnwrap(canvas(in: keyboard.view))
            let native = try XCTUnwrap(glass.effect as? UIGlassEffect)
            XCTAssertFalse(native.isInteractive, "The decorative material must not animate key touches")
            XCTAssertEqual(glass.overrideUserInterfaceStyle, clear ? .unspecified : .dark,
                           "Clear inherits the host; frosted glass keeps custom white text readable")
            XCTAssertEqual(glass.alpha, 1)
            let surface = try XCTUnwrap(keyboard.view.subviews.first { $0.accessibilityIdentifier == "keyboard.surface" })
            XCTAssertEqual(surface.backgroundColor?.cgColor.alpha ?? 1, 0,
                           "An opaque canvas would hide the refracted backdrop")
            for button in buttons(in: keyboard.view) {
                XCTAssertEqual(button.backgroundColor?.cgColor.alpha ?? 0, 0)
                XCTAssertFalse(button.subviews.contains { $0 is UIVisualEffectView })
            }
            let q = try XCTUnwrap(buttons(in: keyboard.view).first { $0.title(for: .normal) == "q" })
            keyboard.tapShift()
            // UIVisualEffectView copies material values; the view is the reuse contract.
            XCTAssertTrue(glass === canvas(in: keyboard.view))
            XCTAssertTrue((glass.effect as? UIGlassEffect)?.isInteractive == native.isInteractive)
            XCTAssertTrue(q === buttons(in: keyboard.view).first { $0.title(for: .normal) == "Q" })
            capture(keyboard, name: clear ? "canvas-clear-no-keycaps" : "canvas-frosted-no-keycaps",
                    patternedBackdrop: true)
            keyboard.toggleAppearancePanel()
            keyboard.view.frame.size.height = try XCTUnwrap(keyboard.inputView as? KeyboardInputView).contentHeight
            keyboard.view.layoutIfNeeded()
            XCTAssertTrue(glass === canvas(in: keyboard.view))
            XCTAssertTrue(glass.effect is UIGlassEffect)
            capture(keyboard, name: clear ? "settings-clear-no-keycaps" : "settings-frosted-no-keycaps",
                    patternedBackdrop: true)
            KeyboardCanvasAppearance.apply(to: glass, surface: surface,
                                           palette: KeyboardPalette.selected(dark: true), reducedTransparency: true)
            XCTAssertNil(glass.effect)
            XCTAssertEqual(surface.backgroundColor?.cgColor.alpha ?? 0, 1)
        }
        KeyboardPreferences.preset = .liquidGlass
        KeyboardPreferences.setGlassEnabled(false)
        XCTAssertFalse(KeyboardPreferences.glassEnabled, "The Off control must also work from the Liquid Glass preset")
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
            XCTAssertFalse(button.subviews.contains { $0 is UIVisualEffectView },
                           "Keycaps must not allocate individual live backdrop effects")
            XCTAssertGreaterThan(button.backgroundColor?.cgColor.alpha ?? 0, 0)
            XCTAssertEqual(button.layer.cornerRadius, KeyboardPreferences.cornerRadius)
        }
        XCTAssertFalse(all.contains { button in
            button.subviews.contains { $0 is UIVisualEffectView }
        }, "Letters, Space and action keys all share the canvas instead of capturing it separately")
        capture(keyboard, name: "liquid-glass-keycaps")
    }
}
