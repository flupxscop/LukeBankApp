import XCTest

/// M4 with the mock backend: freeze, channel controls and replacing a lost card with the PIN.
final class CardsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt", "-ResetSession"]
        app.launch()
        OnboardingFlow(app: app).run()
    }

    func testFreezeControlsAndReportLost() {
        app.buttons["tab.cards"].tap()
        XCTAssertTrue(app.staticTexts["cards.availableValue"].waitForExistence(timeout: 10))

        app.buttons["cards.freeze"].tap()
        XCTAssertTrue(app.staticTexts["Frozen"].waitForExistence(timeout: 5))
        app.buttons["cards.freeze"].tap()
        XCTAssertTrue(app.buttons["Freeze"].waitForExistence(timeout: 5))

        app.buttons["cards.settings"].tap()
        XCTAssertTrue(app.staticTexts["Manage card"].waitForExistence(timeout: 5))
        let overseas = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Spending abroad'")).firstMatch
        XCTAssertTrue(overseas.waitForExistence(timeout: 5))
        let before = overseas.value as? String
        overseas.switches.firstMatch.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: overseas)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)

        let reportLost = app.buttons["cards.reportLost"]
        for _ in 0..<4 where !reportLost.isHittable { app.swipeUp() }
        reportLost.tap()
        let confirm = app.buttons["Block and replace"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["pinpad.4"].waitForExistence(timeout: 5))
        for digit in "482193" { app.buttons["pinpad.\(digit)"].tap() }

        let pan = app.staticTexts["cards.pan"]
        XCTAssertTrue(pan.waitForExistence(timeout: 10))
        let replaced = NSPredicate(format: "label ENDSWITH '7301'")
        XCTAssertTrue(app.staticTexts.matching(identifier: "cards.pan").matching(replaced).firstMatch.waitForExistence(timeout: 10))
    }
}

/// AUTH-11 with the mock backend: a phone flagged as compromised is warned and cannot start a payment.
final class DeviceIntegrityUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt", "-ResetSession", "-SimulateCompromisedDevice",
        ]
        app.launch()
    }

    func testCompromisedPhoneIsWarnedAndCannotPay() {
        OnboardingFlow(app: app).run()
        let warning = app.alerts["This phone may not be secure"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        warning.buttons["OK"].tap()

        app.buttons["tab.payments"].tap()
        app.buttons["payments.transfer"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["PromptPay"].exists)
    }
}

/// NFR-08 with the mock backend: offline shows the badge over the last data and turns payments off.
final class OfflineUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt", "-ResetSession", "-SimulateOffline"]
        app.launch()
    }

    func testOfflineBadgeAndNoPayments() {
        OnboardingFlow(app: app).run()
        XCTAssertTrue(app.otherElements["offline.banner"].waitForExistence(timeout: 10) || app.staticTexts["Offline"].exists)

        app.buttons["tab.payments"].tap()
        app.buttons["payments.transfer"].tap()
        let notice = app.alerts["No connection"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["PromptPay"].exists)
    }
}
