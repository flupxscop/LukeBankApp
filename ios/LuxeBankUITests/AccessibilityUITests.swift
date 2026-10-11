import XCTest

/// NFR-09: Apple's accessibility audit (labels, hit regions, clipped text, Dynamic Type) on every
/// main screen with a large text size. Each screen is attached as a screenshot for the manual review.
final class AccessibilityUITests: XCTestCase {
    private let app = XCUIApplication()
    private static let auditTimedOut = -56

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DisablePushPrompt", "-ResetSession",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ]
        app.launch()
    }

    func testMainScreensPassTheAccessibilityAudit() throws {
        audit("welcome")
        OnboardingFlow(app: app).run()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        audit("home")
        // Audit only once each screen has loaded: auditing a screen that is still changing can time out.
        for (tab, loaded) in [("tab.payments", "payments.transfer"), ("tab.cards", "cards.freeze"), ("tab.profile", "profile.name")] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.descendants(matching: .any)[loaded].firstMatch.waitForExistence(timeout: 15), "\(tab) did not load")
            audit(tab)
        }
    }

    private func audit(_ screen: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        // Slow CI runners can make the audit itself time out (error -56); that is retried, findings are not.
        for attempt in 1...3 {
            do {
                // Contrast is left to ThemeContrastTests, which checks the exact colour pairs: the audit samples rendered
                // pixels and fails thin Thonburi strokes and text under the translucent tab bar that measure 4.7-18.9:1.
                try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
                    // Logged so the report lists every finding with its screen, then failed by the audit itself.
                    print("A11Y[\(screen)] \(issue.auditType) · \(issue.compactDescription) · \(issue.element?.debugDescription.prefix(160) ?? "-")")
                    return false
                }
                return
            } catch let error as NSError where error.code == Self.auditTimedOut && attempt < 3 {
                continue
            } catch {
                XCTFail("\(screen): \(error)")
                return
            }
        }
    }
}
