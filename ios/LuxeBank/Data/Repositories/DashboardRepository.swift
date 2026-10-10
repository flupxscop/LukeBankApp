import Foundation

/// Source of the home screen data. `Remote…` (M2) calls `GET /api/v1/dashboard`;
/// `Mock…` serves previews, tests and development until the backend is ready.
protocol DashboardRepository {
    func fetchDashboard() async throws -> DashboardSummary
}

enum RepositoryError: Error, Equatable {
    case unavailable
}
