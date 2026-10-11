import Foundation

/// Source of the home screen data: `GET /api/v1/dashboard` (DASH-01…10).
protocol DashboardRepository {
    func fetchDashboard() async throws -> DashboardSummary
}

/// History and transaction details (TXN-01…05).
protocol TransactionRepository {
    func transactions(accountID: UUID, query: TransactionQuery, cursor: String?) async throws -> TransactionPage
    func transaction(id: UUID) async throws -> TransactionDetail
    /// `memo: nil` leaves the memo unchanged; `memo: ""` clears it.
    func updateTransaction(id: UUID, category: TransactionCategory?, memo: String?) async throws -> TransactionDetail
}

enum RepositoryError: Error, Equatable {
    case unavailable
}
