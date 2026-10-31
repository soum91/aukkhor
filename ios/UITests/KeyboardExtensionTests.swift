import XCTest

@MainActor final class KeyboardExtensionTests: XCTestCase {
    private func tap(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let query = app.descendants(matching: .any).matching(predicate)
        for attempt in 0..<5 {
            if query.firstMatch.waitForExistence(timeout: attempt == 0 ? timeout : 1),
               let element = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                element.tap()
                return true
            }
            if attempt < 4 { app.swipeUp() }
        }
        return false
    }

    private func evidence(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInstalledExtensionAcrossAppSwitchAndReopening() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.soum91.aukkhor")
        app.launchArguments = ["-keyboard-system-test"]
        app.launch()
        XCTAssertTrue(app.textFields["system-test-field"].waitForExistence(timeout: 10))

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        // The public app-settings URL goes straight to our keyboard switches,
        // without depending on Settings' changing General-page navigation.
        app.buttons["system-test-settings"].tap()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(tap("Keyboards", in: settings), "Open Aukkhor's keyboard switches")
        let enabled = settings.switches.matching(NSPredicate(format: "label CONTAINS[c] 'Aukkhor'")).firstMatch
        XCTAssertTrue(enabled.waitForExistence(timeout: 10), "Installed extension must be offered by iOS Settings")
        if enabled.value as? String != "1" {
            enabled.tap()
            if settings.alerts.buttons["Allow"].waitForExistence(timeout: 1) {
                settings.alerts.buttons["Allow"].tap()
            }
        }
        XCTAssertEqual(enabled.value as? String, "1")
        evidence("extension-enabled-in-system-settings")

        app.activate()
        let field = app.textFields["system-test-field"]
        field.tap()
        let space = app.buttons["Space"]
        for _ in 0..<5 where !space.waitForExistence(timeout: 2) {
            let next = app.buttons.matching(NSPredicate(format:
                "label CONTAINS[c] 'keyboard' AND label != 'Dismiss keyboard'")).firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5), "System keyboard switcher must be available")
            next.tap()
        }
        XCTAssertTrue(space.waitForExistence(timeout: 10), "Use the installed Aukkhor extension, not Apple's keyboard")
        // Configure in the extension itself, including when a simulator or signer
        // cannot share preferences with the host app.
        app.buttons["⚙"].firstMatch.tap()
        let theme = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Theme: '")).firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        for _ in 0..<9 where theme.label != "Theme: Liquid Glass" { theme.tap() }
        XCTAssertEqual(theme.label, "Theme: Liquid Glass")
        if app.buttons["Numbers: Off"].exists { app.buttons["Numbers: Off"].tap() }
        if app.buttons["Background: Custom"].exists { app.buttons["Background: Custom"].tap() }
        XCTAssertTrue(app.buttons["Background: iOS"].exists)
        app.buttons["Done"].tap()
        let letter = app.buttons["q"].exists ? app.buttons["q"] : app.buttons["Q"]
        XCTAssertTrue(letter.exists)
        letter.tap()
        XCTAssertTrue((field.value as? String ?? "").lowercased().contains("q"), "Typing must cross the extension process")
        evidence("extension-full-screen-first-presentation")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(space.waitForExistence(timeout: 10))
        evidence("extension-full-screen-after-app-switch")

        app.buttons["system-test-dismiss"].tap()
        XCTAssertTrue(space.waitForNonExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(space.waitForExistence(timeout: 10))
        evidence("extension-full-screen-after-reopening")

        app.buttons["⚙"].firstMatch.tap()
        let caps = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Keycaps: '")).firstMatch
        for _ in 0..<3 where caps.label != "Keycaps: None" { caps.tap() }
        XCTAssertEqual(caps.label, "Keycaps: None")
        app.buttons["Done"].tap()
        evidence("extension-full-screen-native-background-no-keycaps")
    }
}
