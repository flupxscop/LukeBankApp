import XCTest

/// M5 with the mock backend: inbox from the home bell, RM chat, preferences, change PIN and sign-out.
final class ProfileUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt", "-ResetSession"]
        app.launch()
        OnboardingFlow(app: app).run()
    }

    func testInboxChatSettingsAndSignOut() {
        // Inbox from the bell on the home screen.
        let bell = app.buttons["dashboard.inbox"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        bell.tap()
        XCTAssertTrue(app.buttons["inbox.item"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["inbox.readAll"].tap()
        XCTAssertTrue(app.buttons["inbox.readAll"].waitForNonExistence(timeout: 5))
        app.buttons["Back"].tap()

        // Profile with the relationship manager and a simulated chat.
        XCTAssertTrue(app.staticTexts["profile.name"].waitForExistence(timeout: 5))
        app.buttons["profile.rm.chat"].tap()
        let input = app.textFields["chat.input"].exists ? app.textFields["chat.input"] : app.textViews["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Hello")
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Message received'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        // Settings: news and offers on, then change the PIN.
        app.buttons["profile.settings"].tap()
        let marketing = app.switches["settings.notify.marketing"]
        XCTAssertTrue(marketing.waitForExistence(timeout: 5))
        XCTAssertEqual(marketing.value as? String, "0")
        marketing.switches.firstMatch.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: marketing)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 5), .completed)

        app.buttons["settings.changePin"].tap()
        XCTAssertTrue(app.buttons["pinpad.4"].waitForExistence(timeout: 5))
        for pin in ["482193", "703915", "703915"] {
            for digit in pin { app.buttons["pinpad.\(digit)"].tap() }
        }
        let done = app.buttons["changePin.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        // Sign out and unbind the phone.
        let logout = app.buttons["settings.logout"]
        for _ in 0..<4 where !logout.isHittable { app.swipeUp() }
        logout.tap()
        let confirm = app.buttons["Sign out"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 10))
    }
}
