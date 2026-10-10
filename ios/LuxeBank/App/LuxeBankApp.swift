import SwiftUI

@main
struct LuxeBankApp: App {
    private let environment = AppEnvironment.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .preferredColorScheme(.light)
        }
    }
}
