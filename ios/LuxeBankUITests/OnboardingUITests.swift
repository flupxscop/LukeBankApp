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

        app.buttons["welcome.start"].tap()

        let citizenID = app.textFields["register.citizenID"]
        XCTAssertTrue(citizenID.waitForExistence(timeout: 5))
        citizenID.tap()
        citizenID.typeText("1234567890121")
        XCTAssertEqual(citizenID.value as? String, "1-2345-67890-12-1")

        let password = app.secureTextFields["register.password"]
        password.tap()
        password.typeText("LuxeDemo#2026")
        app.buttons["register.submit"].tap()

        XCTAssertTrue(app.buttons["pinpad.0"].waitForExistence(timeout: 5))
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

        // Relaunch: the bound device opens on the lock screen.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ResetSession" }
        app.launch()
        XCTAssertTrue(app.staticTexts["lock.title"].waitForExistence(timeout: 5))
        enter("482193")
        XCTAssertTrue(app.scrollViews["dashboard"].waitForExistence(timeout: 5) || app.otherElements["dashboard"].exists)
    }

    private func enter(_ digits: String) {
        for digit in digits {
            app.buttons["pinpad.\(digit)"].tap()
        }
    }
}
