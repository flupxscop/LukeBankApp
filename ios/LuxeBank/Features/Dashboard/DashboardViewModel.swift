import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    enum State: Equatable {
        case loading
        case loaded(DashboardSummary)
        case failed
    }

    enum HistoryRange: CaseIterable, Identifiable {
        case week
        case month
        case year

        var id: Self { self }

        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .year: 365
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .week: "range.week"
            case .month: "range.month"
            case .year: "range.year"
            }
        }
    }

    private(set) var state: State = .loading
    var selectedRange: HistoryRange = .month
    private(set) var isBalanceHidden = false
    /// Recorded for routing; the destinations arrive in M3.
    private(set) var lastSelectedAction: QuickAction?

    private let repository: DashboardRepository
    private let now: () -> Date
    private let calendar: Calendar

    init(repository: DashboardRepository, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.repository = repository
        self.now = now
        self.calendar = calendar
    }

    var greeting: DayGreeting {
        DayGreeting(hour: calendar.component(.hour, from: now()))
    }

    var today: Date { now() }

    func load() async {
        do {
            state = .loaded(try await repository.fetchDashboard())
        } catch {
            state = .failed
        }
    }

    func retry() async {
        state = .loading
        await load()
    }

    /// Balance points inside the selected range, oldest first.
    func history(in summary: DashboardSummary) -> [BalancePoint] {
        guard let start = calendar.date(byAdding: .day, value: -(selectedRange.days - 1), to: calendar.startOfDay(for: now())) else {
            return summary.balanceHistory
        }
        return summary.balanceHistory.filter { $0.date >= start }
    }

    /// Keeps the recent list in sync after the detail screen edits a transaction.
    func replace(_ transaction: Transaction) {
        guard case .loaded(var summary) = state,
              let index = summary.recentTransactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        summary.recentTransactions[index] = transaction
        state = .loaded(summary)
    }

    func toggleBalanceVisibility() {
        isBalanceHidden.toggle()
    }

    func select(_ action: QuickAction) {
        lastSelectedAction = action
    }
}
