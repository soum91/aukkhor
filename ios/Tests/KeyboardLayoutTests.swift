import XCTest
import UIKit
@testable import Aukkhor

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
                                   keyboard.view.bounds.maxY - 4, accuracy: 0.5,
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
        XCTAssertEqual(KeyboardPreferences.typingHeight, 228)
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
        XCTAssertEqual(KeyboardPreferences.typingHeight, 277)
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
