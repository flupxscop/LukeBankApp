import SwiftUI

@main
struct LuxeBankApp: App {
    private let environment = AppEnvironment.makeDefault()

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
                .preferredColorScheme(.light)
        }
    }
}
