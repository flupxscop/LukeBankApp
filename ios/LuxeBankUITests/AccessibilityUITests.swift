import XCTest

/// NFR-09: Apple's accessibility audit (labels, hit regions, clipped text, Dynamic Type) on every
/// main screen with a large text size. Each screen is attached as a screenshot for the manual review.
final class AccessibilityUITests: XCTestCase {
    private let app = XCUIApplication()

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
        for tab in ["tab.payments", "tab.cards", "tab.profile"] {
            app.buttons[tab].tap()
            sleep(2)
            audit(tab)
        }
    }

    private func audit(_ screen: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        do {
            // Contrast is left to ThemeContrastTests, which checks the exact colour pairs: the audit samples rendered
            // pixels and fails thin Thonburi strokes and text under the translucent tab bar that measure 4.7-18.9:1.
            try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
                // Logged so the report lists every finding with its screen, then failed by the audit itself.
                print("A11Y[\(screen)] \(issue.auditType) · \(issue.compactDescription) · \(issue.element?.debugDescription.prefix(160) ?? "-")")
                return false
            }
        } catch {
            XCTFail("\(screen): \(error)")
        }
    }
}
