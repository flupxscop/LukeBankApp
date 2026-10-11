import XCTest

/// End-to-end onboarding and unlock with the mock backend (NFR-12).
final class OnboardingUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt"]
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

    private func onboard() {
        OnboardingFlow(app: app).run()
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

    private func enter(_ digits: String) {
        for digit in digits {
            app.buttons["pinpad.\(digit)"].tap()
        }
    }
}
