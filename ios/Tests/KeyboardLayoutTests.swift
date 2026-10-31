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
        let savedStyle = KeyboardPreferences.keycapStyle
        let savedSide = KeyboardPreferences.oneHandSide
        let savedPreset = KeyboardPreferences.preset
        defer {
            KeyboardPreferences.keycapStyle = savedStyle
            KeyboardPreferences.oneHandSide = savedSide
            KeyboardPreferences.preset = savedPreset
        }
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
                    for button in all {
                        XCTAssertEqual(button.backgroundColor?.cgColor.alpha ?? 0, 0)
                        XCTAssertEqual(button.layer.borderWidth, 0)
                        XCTAssertEqual(button.layer.shadowOpacity, 0)
                        XCTAssertFalse(button.subviews.contains { $0 is UIVisualEffectView })
                    }
                    if width == 390 && preset == .liquidGlass {
                        capture(keyboard, name: "background-free-side-\(side)")
                    }
                }
            }
        }
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
        capture(keyboard, name: "liquid-glass-keycaps")
    }
}
