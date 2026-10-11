import XCTest

/// M3 end to end with the mock backend: PromptPay transfer and a saved bill, both confirmed with the PIN.
final class PaymentsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ResetSession"]
        if let api = ProcessInfo.processInfo.environment["LUXEBANK_API"] {
            app.launchArguments += ["-LuxeBankAPI", api]
        }
        app.launch()
        OnboardingFlow(app: app).run()
    }

    func testPromptPayTransferEndsOnTheSlipAndShowsInHistory() {
        app.buttons["tab.payments"].tap()
        app.buttons["payments.transfer"].tap()

        app.buttons["PromptPay"].tap()
        let proxy = app.textFields["transfer.proxy"]
        XCTAssertTrue(proxy.waitForExistence(timeout: 5))
        proxy.tap()
        proxy.typeText("0812345678")
        app.buttons["transfer.next"].tap()

        for key in ["1", "2", "5", "0"] { app.buttons["amount.\(key)"].tap() }
        app.buttons["transfer.review"].tap()

        XCTAssertTrue(app.buttons["confirm.submit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Verified"].exists)
        app.buttons["confirm.submit"].tap()
        enterPin()

        XCTAssertTrue(app.staticTexts["slip.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["slip.reference"].exists)
        app.buttons["slip.done"].tap()

        app.buttons["tab.home"].tap()
        // The home screen reloads after the flow closes; wait for the new transfer's row.
        let transferRow = app.buttons.matching(identifier: "dashboard.transaction").matching(NSPredicate(format: "label CONTAINS 'วิไล'")).firstMatch
        XCTAssertTrue(transferRow.waitForExistence(timeout: 10))
        transferRow.tap()
        XCTAssertTrue(app.buttons["detail.viewSlip"].waitForExistence(timeout: 5))
        app.buttons["detail.viewSlip"].tap()
        XCTAssertTrue(app.staticTexts["slip.reference"].waitForExistence(timeout: 5))
    }

    func testSavedBillIsPaidWithThePin() {
        app.buttons["tab.payments"].tap()
        app.buttons["payments.bills"].tap()

        let saved = app.buttons.matching(identifier: "bills.savedRow").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()

        XCTAssertTrue(app.staticTexts["Amount due"].waitForExistence(timeout: 10))
        app.buttons["bill.submit"].tap()

        XCTAssertTrue(app.buttons["confirm.submit"].waitForExistence(timeout: 10))
        app.buttons["confirm.submit"].tap()
        enterPin()
        XCTAssertTrue(app.staticTexts["slip.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bill paid"].exists)
    }

    private func enterPin() {
        XCTAssertTrue(app.buttons["pinpad.4"].waitForExistence(timeout: 5))
        for digit in "482193" { app.buttons["pinpad.\(digit)"].tap() }
    }
}
