import Observation
import UIKit
import UserNotifications

/// Notification permission and the APNs token (NOTI-01…03).
/// The token goes to `PUT /me/devices/current/push-token`; in the simulation the server's push adapter only logs,
/// and the in-app inbox is the source of truth. On the simulator, drop a file from `ios/PushSamples` onto the
/// device (or `xcrun simctl push`) to see a banner.
@MainActor
@Observable
final class PushRegistrar: NSObject {
    static let shared = PushRegistrar()

    /// Hex APNs token once iOS issues one (needs the aps-environment entitlement on a real device).
    private(set) var token: String?
    /// Bumped whenever a notification arrives while the app is open, so screens can refresh.
    private(set) var arrivals = 0

    /// Asks once; iOS remembers the answer. Registration happens either way so a later "Allow" works.
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    fileprivate func didReceive() {
        arrivals += 1
    }
}

extension PushRegistrar: UNUserNotificationCenterDelegate {
    /// Shows the banner while the app is open as well, and refreshes the unread count.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { PushRegistrar.shared.didReceive() }
        return [.banner, .list, .sound]
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PushRegistrar.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushRegistrar.shared.didRegister(deviceToken: deviceToken) }
    }

    /// Expected without a push entitlement (simulation, ad-hoc signing); the inbox still works.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}
