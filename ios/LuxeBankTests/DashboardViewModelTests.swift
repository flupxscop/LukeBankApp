import Foundation
import Testing
@testable import LuxeBank

@MainActor
struct DashboardViewModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        return calendar
    }()

    private func date(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour)) ?? Date()
    }

    @Test func loadsDashboardFromRepository() async {
        let now = date(hour: 19)
        let viewModel = DashboardViewModel(repository: MockDashboardRepository(now: { now }), now: { now }, calendar: calendar)

        await viewModel.load()

        guard case .loaded(let summary) = viewModel.state else {
            Issue.record("Expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(summary.primaryAccount.balance == Decimal(482_545_075) / 100)
        #expect(summary.recentTransactions.count == 4)
        #expect(summary.recentTransactions.first?.merchant == "Sarnies Bangkok")
    }

    @Test func showsErrorWhenRepositoryFails() async {
        let viewModel = DashboardViewModel(repository: MockDashboardRepository(shouldFail: true), calendar: calendar)

        await viewModel.load()

        #expect(viewModel.state == .failed)
    }

    @Test func retryRecoversAfterFailure() async {
        var repository = MockDashboardRepository(shouldFail: true)
        let failing = DashboardViewModel(repository: repository, calendar: calendar)
        await failing.load()
        #expect(failing.state == .failed)

        repository.shouldFail = false
        let recovering = DashboardViewModel(repository: repository, calendar: calendar)
        await recovering.retry()
        if case .loaded = recovering.state {} else { Issue.record("Expected loaded state after retry") }
    }

    @Test(arguments: [(6, DayGreeting.morning), (13, .afternoon), (19, .evening), (2, .evening)])
    func greetsByTimeOfDay(hour: Int, expected: DayGreeting) {
        let now = date(hour: hour)
        let viewModel = DashboardViewModel(repository: MockDashboardRepository(), now: { now }, calendar: calendar)
        #expect(viewModel.greeting == expected)
    }

    @Test func filtersBalanceHistoryBySelectedRange() async {
        let now = date(hour: 19)
        let viewModel = DashboardViewModel(repository: MockDashboardRepository(now: { now }), now: { now }, calendar: calendar)
        await viewModel.load()
        guard case .loaded(let summary) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        viewModel.selectedRange = .week
        #expect(viewModel.history(in: summary).count == 7)
        viewModel.selectedRange = .month
        #expect(viewModel.history(in: summary).count == 30)
        viewModel.selectedRange = .year
        #expect(viewModel.history(in: summary).count == 365)
        #expect(viewModel.history(in: summary).last?.balance == summary.primaryAccount.balance)
    }

    @Test func togglesBalanceVisibility() {
        let viewModel = DashboardViewModel(repository: MockDashboardRepository(), calendar: calendar)
        #expect(viewModel.isBalanceHidden == false)
        viewModel.toggleBalanceVisibility()
        #expect(viewModel.isBalanceHidden == true)
    }

    @Test func recordsSelectedQuickAction() {
        let viewModel = DashboardViewModel(repository: MockDashboardRepository(), calendar: calendar)
        viewModel.select(.transfer)
        #expect(viewModel.lastSelectedAction == .transfer)
    }
}

struct SpendingSummaryTests {
    private let spending = SpendingSummary(categories: [
        SpendingCategory(kind: .lifestyle, spent: 38_200, budget: 50_000),
        SpendingCategory(kind: .travel, spent: 12_400, budget: 25_000),
    ])

    @Test func totalsSpentAndBudget() {
        #expect(spending.totalSpent == 50_600)
        #expect(spending.totalBudget == 75_000)
    }

    @Test func computesUsageAndShares() {
        #expect(abs(spending.usage - 0.6747) < 0.001)
        #expect(abs(spending.share(of: .lifestyle) - 0.5093) < 0.001)
    }

    @Test func handlesEmptyBudget() {
        #expect(SpendingSummary(categories: []).usage == 0)
        #expect(SavingsGoal(saved: 10, target: 0).progress == 0)
        #expect(SavingsGoal(saved: 300, target: 240).progress == 1)
    }
}
