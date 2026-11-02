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

    private func openKeyboardSettings(_ settings: XCUIApplication) -> Bool {
        // The app-settings page stopped exposing the "Keyboards" shortcut on
        // some iOS 27 simulators. First use it when present, then navigate the
        // public General > Keyboard > Keyboards route as a fallback.
        let shortcut = settings.cells.matching(NSPredicate(
            format: "label == 'Keyboards' OR label BEGINSWITH 'Keyboards,'"
        )).firstMatch
        if shortcut.waitForExistence(timeout: 2), shortcut.isHittable {
            shortcut.tap()
            return true
        }
        settings.terminate()
        settings.launch()
        // Settings may restore its last app-specific page after relaunch.
        // Walk back to the root before looking for General.
        for _ in 0..<6 {
            if settings.staticTexts["General"].exists { break }
            let back = settings.navigationBars.buttons.matching(NSPredicate(
                format: "label == 'Settings' OR label == 'Apps' OR label == 'Back'"
            )).firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
        }
        guard tap("General", in: settings, timeout: 5),
              tap("Keyboard", in: settings, timeout: 5) else { return false }
        // Do not use a generic label query here: the navigation title also
        // says "Keyboards" and the real row has label "Keyboards, 2".
        let listRow = settings.cells.matching(NSPredicate(
            format: "identifier == 'KEYBOARDS' OR label BEGINSWITH 'Keyboards,'"
        )).firstMatch
        guard listRow.waitForExistence(timeout: 10), listRow.isHittable else { return false }
        listRow.tap()
        return true
    }

    func testInstalledExtensionAcrossAppSwitchAndReopening() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.soum91.aukkhor")
        app.launchArguments = ["-keyboard-system-test"]
        app.launch()
        XCTAssertTrue(app.textFields["system-test-field"].waitForExistence(timeout: 10))

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        // The public app-settings URL is useful, but it does not consistently
        // expose keyboard management on every iOS Settings version.
        app.buttons["system-test-settings"].tap()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 20))
        evidence("settings-initial-keyboard-install")
        XCTAssertTrue(openKeyboardSettings(settings), "Open iOS General > Keyboard > Keyboards")
        evidence("settings-keyboards-list")
        let enabled = settings.switches.matching(NSPredicate(format: "label CONTAINS[c] 'Aukkhor'")).firstMatch
        if enabled.waitForExistence(timeout: 2) {
            if enabled.value as? String != "1" { enabled.tap() }
            XCTAssertEqual(enabled.value as? String, "1")
        } else {
            // On newer Settings layouts keyboards are rows, not switches.
            // Install once if needed, then open its Full Access details.
            var row = settings.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Aukkhor'")).firstMatch
            if !row.exists {
                let add = settings.cells.matching(NSPredicate(format:
                    "label CONTAINS[c] 'Add New Keyboard'")).firstMatch
                XCTAssertTrue(add.waitForExistence(timeout: 10), "Add New Keyboard must be available")
                add.tap()
                let option = settings.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Aukkhor'")).firstMatch
                XCTAssertTrue(option.waitForExistence(timeout: 10), "Aukkhor must be listed as an installed keyboard")
                option.tap()
                row = settings.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Aukkhor'")).firstMatch
            }
            XCTAssertTrue(row.waitForExistence(timeout: 10), "Aukkhor keyboard row must appear")
            row.tap()
            let fullAccess = settings.switches.matching(NSPredicate(format: "label CONTAINS[c] 'Full Access'")).firstMatch
            XCTAssertTrue(fullAccess.waitForExistence(timeout: 10), "iOS must expose Allow Full Access")
            if fullAccess.value as? String != "1" { fullAccess.tap() }
            // iOS 27 can present the confirmation in SpringBoard instead of
            // Settings. The unsigned CI app also cannot prove a provisioned
            // keyboard's Full Access grant on a user's physical device.
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for owner in [settings, springboard] {
                let allow = owner.alerts.buttons.matching(NSPredicate(
                    format: "label == 'Allow' OR label == 'Allow Full Access'"
                )).firstMatch
                if allow.waitForExistence(timeout: 2) { allow.tap(); break }
            }
            let granted = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == '1'"), object: fullAccess)
            if XCTWaiter.wait(for: [granted], timeout: 3) != .completed {
                evidence("unsigned-simulator-full-access-not-granted")
                print("WARNING: iOS Simulator did not persist Full Access. Continue testing normal typing; signed-device permission remains unverified.")
            }
        }
        evidence("extension-enabled-in-system-settings")

        // iOS 27 sometimes leaves the host app in a background-only state
        // after Settings changes keyboard extension permissions. Relaunch the
        // test host cleanly; the installed keyboard persists across launches.
        settings.terminate()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["system-test-field"].waitForExistence(timeout: 10),
                      "Host app must reopen after installing the keyboard")
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
