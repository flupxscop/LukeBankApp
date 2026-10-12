import XCTest

/// Stability, speed and resource measurements (docs/app-quality-metrics.md).
/// Simulator timings are noisy and run on the Mac's CPU, so these are not part of the normal test run:
///
///     TEST_RUNNER_LUXEBANK_MEASURE=1 xcodebuild test ... -only-testing:LuxeBankUITests/AppMetricsUITests
///
/// Run them on a physical iPhone for release numbers. `scripts/measure-app.sh` runs them and prints a summary.
final class AppMetricsUITests: XCTestCase {
    private let app = XCUIApplication()
    private let iterations = 5

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LUXEBANK_MEASURE"] == "1", "Set TEST_RUNNER_LUXEBANK_MEASURE=1 to measure")
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt"]
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private func onboard() {
        app.launchArguments += ["-ResetSession"]
        app.launch()
        OnboardingFlow(app: app).run()
        app.launchArguments.removeAll { $0 == "-ResetSession" }
    }

    private var dashboard: XCUIElement { app.buttons["dashboard.inbox"] }

    private func unlock() {
        XCTAssertTrue(app.buttons["pinpad.4"].waitForExistence(timeout: 10))
        OnboardingFlow(app: app).enter("482193")
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
    }

    // MARK: Speed and responsiveness

    /// Cold launch to the first frame (NFR-01: ≤ 2 s on iPhone 12 or later).
    func testColdLaunch() {
        let metrics: [XCTMetric] = [
            XCTApplicationLaunchMetric(waitUntilResponsive: true),
            // LuxeBank's own launch work, without the simulator and test harness around it.
            XCTOSSignpostMetric(subsystem: "com.luxebank.app", category: "Performance", name: "Startup"),
        ]
        measure(metrics: metrics, options: options) {
            app.launch()
        }
    }

    /// Calibration: the same measurement for Apple's Reminders app on the same simulator. The difference between
    /// the two is what LuxeBank itself costs; the rest is the simulator and the test harness.
    func testColdLaunchBaselineSystemApp() {
        let reminders = XCUIApplication(bundleIdentifier: "com.apple.reminders")
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            reminders.launch()
        }
    }

    /// PIN entry to the dashboard with data (NFR-01: ≤ 1.5 s after unlock).
    func testUnlockToDashboard() {
        onboard()
        let options = options
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        let metrics: [XCTMetric] = [
            XCTClockMetric(),
            XCTOSSignpostMetric(subsystem: "com.luxebank.app", category: "Performance", name: "Unlock"),
            XCTOSSignpostMetric(subsystem: "com.luxebank.app", category: "Performance", name: "DashboardLoad"),
        ]
        measure(metrics: metrics, options: options) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["pinpad.4"].waitForExistence(timeout: 10))
            startMeasuring()
            OnboardingFlow(app: app).enter("482193")
            XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
            stopMeasuring()
        }
    }

    /// Scrolling the transaction history and pushing into it: hitch time ratio (Apple's guidance:
    /// under 5 ms/s is good, over 10 ms/s is noticeable) and the history load interval.
    func testHistoryScrollingAndNavigation() {
        onboard()
        openHistory()
        let list = app.scrollViews["history"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let metrics: [XCTMetric] = [
            XCTOSSignpostMetric.scrollDecelerationMetric,
            XCTOSSignpostMetric(subsystem: "com.luxebank.app", category: "Performance", name: "HistoryLoad"),
        ]
        measure(metrics: metrics, options: options) {
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
    }

    // MARK: Resource consumption

    /// A typical session: home, history, cards, payments, profile. Peak memory, CPU time and disk writes.
    func testResourcesInTypicalSession() {
        onboard()
        let metrics: [XCTMetric] = [
            XCTMemoryMetric(application: app),
            XCTCPUMetric(application: app),
            XCTStorageMetric(application: app),
            XCTClockMetric(),
        ]
        measure(metrics: metrics, options: options) {
            visitEveryTab()
        }
    }

    // MARK: Stability

    /// Soak: 30 rounds through every tab and into history and back. The app must stay running and responsive;
    /// a leak shows as memory rising across the iterations of `testResourcesInTypicalSession`.
    func testSoakNavigationStaysAlive() {
        onboard()
        for round in 1...30 {
            visitEveryTab()
            openHistory()
            XCTAssertTrue(app.scrollViews["history"].waitForExistence(timeout: 10), "round \(round)")
            app.buttons["Back"].firstMatch.tap()
            XCTAssertEqual(app.state, .runningForeground, "App stopped in round \(round)")
            XCTAssertTrue(dashboard.waitForExistence(timeout: 10), "Dashboard missing in round \(round)")
        }
    }

    // MARK: Helpers

    private func visitEveryTab() {
        for (tab, loaded) in [
            ("tab.payments", "payments.transfer"), ("tab.cards", "cards.freeze"), ("tab.profile", "profile.name"), ("tab.home", "dashboard.inbox"),
        ] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.descendants(matching: .any)[loaded].firstMatch.waitForExistence(timeout: 10), "\(tab) did not load")
        }
    }

    private func openHistory() {
        let seeAll = app.buttons["See all"]
        for _ in 0..<6 where !seeAll.isHittable { app.swipeUp() }
        seeAll.tap()
    }
}
