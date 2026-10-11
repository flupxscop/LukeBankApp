import XCTest

/// End-to-end onboarding and unlock with the mock backend (NFR-12).
final class OnboardingUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // TEST_RUNNER_LUXEBANK_API=http://127.0.0.1:8080 runs the same flow against the real backend.
        if let api = ProcessInfo.processInfo.environment["LUXEBANK_API"] {
            app.launchArguments += ["-LuxeBankAPI", api]
        }
    }

    func testRegisterSetPinThenUnlockAfterRelaunch() {
        app.launchArguments += ["-ResetSession"]
        app.launch()

        onboard()

        // Relaunch: the bound device opens on the lock screen.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ResetSession" }
        app.launch()
        XCTAssertTrue(app.staticTexts["lock.title"].waitForExistence(timeout: 5))
        enter("482193")
        XCTAssertTrue(app.scrollViews["dashboard"].waitForExistence(timeout: 5) || app.otherElements["dashboard"].exists)
    }

    /// Registers the demo customer, sets PIN 482193 and lands on the home screen.
    private func onboard() {
        app.buttons["welcome.start"].tap()

        let citizenID = app.textFields["register.citizenID"]
        XCTAssertTrue(citizenID.waitForExistence(timeout: 5))
        focus(citizenID)
        citizenID.typeText("1234567890121")
        XCTAssertEqual(citizenID.value as? String, "1-2345-67890-12-1")

        let password = app.secureTextFields["register.password"]
        password.tap()
        password.typeText("LuxeDemo#2026")
        let submit = app.buttons["register.submit"]
        submit.tap()
        // The first tap can land while the keyboard's Passwords bar is still animating in.
        if !app.buttons["pinpad.0"].waitForExistence(timeout: 4), submit.exists { submit.tap() }

        XCTAssertTrue(app.buttons["pinpad.0"].waitForExistence(timeout: 6))
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

    func testHistoryFiltersAndTransactionDetail() {
        app.launchArguments += ["-ResetSession"]
        app.launch()
        onboard()

        let seeAll = app.buttons["See all"]
        for _ in 0..<6 where !seeAll.isHittable { app.swipeUp() }
        seeAll.tap()

        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(identifier: "history.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))

        app.buttons["Money in"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        app.buttons["All"].tap()

        let search = app.textFields["history.search"]
        search.tap()
        search.typeText("zzzz-no-match")
        XCTAssertTrue(app.staticTexts["No transactions in this period"].waitForExistence(timeout: 5))
        app.buttons["Clear filters"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))

        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Reference"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Completed"].exists)

        let category = app.buttons["detail.category"]
        if category.exists {
            category.tap()
            app.buttons["Shopping"].firstMatch.tap()
            let recategorised = NSPredicate(format: "label CONTAINS 'Shopping'")
            XCTAssertTrue(app.buttons.matching(identifier: "detail.category").matching(recategorised).firstMatch.waitForExistence(timeout: 5))
        }

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
    }

    /// The screen also focuses the first field itself after a short delay; tap until the keyboard is really up.
    private func focus(_ field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2) { return }
        }
        XCTFail("Keyboard did not appear for \(field.identifier)")
    }

    private func enter(_ digits: String) {
        for digit in digits {
            app.buttons["pinpad.\(digit)"].tap()
        }
    }
}
