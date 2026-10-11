import XCTest

/// Shared onboarding steps for UI tests (mock backend or `LUXEBANK_API`).
struct OnboardingFlow {
    let app: XCUIApplication

    /// Registers the demo customer, sets PIN 482193 and lands on the home screen.
    func run() {
        app.buttons["welcome.start"].tap()

        let citizenID = app.textFields["register.citizenID"]
        XCTAssertTrue(citizenID.waitForExistence(timeout: 5))
        focus(citizenID)
        // XCUITest types faster than any person; retype if the formatter dropped a keystroke.
        for _ in 0..<3 where citizenID.value as? String != "1-2345-67890-12-1" {
            citizenID.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            citizenID.typeText("1234567890121")
        }
        XCTAssertEqual(citizenID.value as? String, "1-2345-67890-12-1")

        let password = app.secureTextFields["register.password"]
        password.tap()
        password.typeText("LuxeDemo#2026")
        let submit = app.buttons["register.submit"]
        submit.tap()
        // The first tap can land while the keyboard's Passwords bar is still animating in.
        if !app.buttons["pinpad.0"].waitForExistence(timeout: 4), submit.exists { submit.tap() }

        XCTAssertTrue(app.buttons["pinpad.0"].waitForExistence(timeout: 12))
        enter("000000")

        XCTAssertTrue(app.staticTexts["Create a PIN"].waitForExistence(timeout: 5))
        enter("123456")
        XCTAssertTrue(app.staticTexts["Avoid sequences and repeated digits"].waitForExistence(timeout: 2))
        enter("482193")
        XCTAssertTrue(app.staticTexts["Confirm your PIN"].waitForExistence(timeout: 2))
        enter("482193")

        let later = app.buttons["faceid.later"]
        if later.waitForExistence(timeout: 4) { later.tap() }
        XCTAssertTrue(app.otherElements["dashboard"].waitForExistence(timeout: 5) || app.scrollViews["dashboard"].exists)
    }

    /// The screen focuses the first field itself shortly after it appears; let that happen instead of
    /// racing it with a tap, which drops keystrokes. Tap only if the keyboard never shows.
    /// Waits for the field itself to hold focus: the keyboard can already be up during the screen transition.
    func focus(_ field: XCUIElement) {
        if hasFocus(field, timeout: 3) { return }
        for _ in 0..<3 {
            field.tap()
            if hasFocus(field, timeout: 2) { return }
        }
        XCTFail("Keyboard focus did not reach \(field.identifier)")
    }

    private func hasFocus(_ field: XCUIElement, timeout: TimeInterval) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
        return XCTWaiter.wait(for: [focused], timeout: timeout) == .completed
    }

    func enter(_ digits: String) {
        for digit in digits {
            app.buttons["pinpad.\(digit)"].tap()
        }
    }
}
