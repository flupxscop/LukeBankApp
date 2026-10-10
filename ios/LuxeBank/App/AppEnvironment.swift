import Foundation

/// Dependency container. Remote repositories replace the mocks from M2 onward (spec 6.2).
struct AppEnvironment {
    let dashboardRepository: DashboardRepository

    static let mock = AppEnvironment(dashboardRepository: MockDashboardRepository())

    static func makeDefault() -> AppEnvironment {
        mock
    }
}
