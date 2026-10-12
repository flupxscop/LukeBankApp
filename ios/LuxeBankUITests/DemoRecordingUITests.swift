import XCTest

/// The README demo, recorded by `scripts/record-demo.sh` (skipped unless `TEST_RUNNER_LUXEBANK_DEMO=1`):
/// `testA_Prepare` registers the demo customer off camera, then `testB_Tour` is recorded: PIN unlock, home,
/// a PromptPay transfer to its slip, cards and profile.
final class DemoRecordingUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LUXEBANK_DEMO"] == "1", "Set TEST_RUNNER_LUXEBANK_DEMO=1 to record the demo")
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt"]
    }

    /// Taps the PIN at a natural pace (the CI helper's per-digit checks are too slow to film).
    private func tapPin() {
        for digit in "482193" { app.buttons["pinpad.\(digit)"].tap() }
    }

    /// Lets the viewer take in a screen.
    private func pause(_ seconds: UInt32 = 2) {
        sleep(seconds)
    }

    func testA_Prepare() {
        app.launchArguments += ["-ResetSession"]
        app.launch()
        OnboardingFlow(app: app).run()
        app.terminate()
    }

    func testB_Tour() {
        // record-demo.sh has already opened the app on the lock screen of the device registered by testA_Prepare;
        // activating (not relaunching) keeps the recording free of launch screens.
        app.activate()
        XCTAssertTrue(app.buttons["pinpad.4"].waitForExistence(timeout: 15))
        pause(1)
        tapPin()

        // Home: balance, chart, spending and recent transactions.
        XCTAssertTrue(app.buttons["dashboard.inbox"].waitForExistence(timeout: 10))
        pause(3)
        app.swipeUp()
        pause(2)
        app.swipeDown()
        pause(1)

        // PromptPay transfer to the slip.
        app.buttons["tab.payments"].tap()
        pause(2)
        app.buttons["payments.transfer"].tap()
        app.buttons["PromptPay"].tap()
        let proxy = app.textFields["transfer.proxy"]
        XCTAssertTrue(proxy.waitForExistence(timeout: 5))
        proxy.tap()
        proxy.typeText("0812345678")
        app.buttons["transfer.next"].tap()
        XCTAssertTrue(app.buttons["amount.1"].waitForExistence(timeout: 10))
        pause(1)
        for key in ["1", "2", "5", "0"] { app.buttons["amount.\(key)"].tap() }
        pause(1)
        app.buttons["transfer.review"].tap()
        XCTAssertTrue(app.buttons["confirm.submit"].waitForExistence(timeout: 10))
        pause(2)
        app.buttons["confirm.submit"].tap()
        XCTAssertTrue(app.buttons["pinpad.4"].waitForExistence(timeout: 5))
        tapPin()
        XCTAssertTrue(app.staticTexts["slip.title"].waitForExistence(timeout: 10))
        pause(3)
        app.buttons["slip.done"].tap()

        // Cards and profile.
        app.buttons["tab.cards"].tap()
        XCTAssertTrue(app.buttons["cards.freeze"].waitForExistence(timeout: 10))
        pause(3)
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.staticTexts["profile.name"].waitForExistence(timeout: 10))
        pause(3)
        app.buttons["tab.home"].tap()
        pause(2)
    }
}
