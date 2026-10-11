import XCTest

/// M4 with the mock backend: freeze, channel controls and replacing a lost card with the PIN.
final class CardsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ResetSession"]
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
