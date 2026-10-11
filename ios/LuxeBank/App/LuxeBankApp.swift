import SwiftUI

@main
struct LuxeBankApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .preferredColorScheme(.light)
        }
    }
}
