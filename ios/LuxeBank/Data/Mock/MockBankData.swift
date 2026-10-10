import Foundation

/// Deterministic sample data used by mock repositories, previews and tests.
enum MockBankData {
    static let primaryAccountID = UUID(uuidString: "6C1F4E0A-4289-4D7B-9C3E-1F2A3B4C4289") ?? UUID()

    static func dashboard(now: Date = Date(), calendar: Calendar = .current) -> DashboardSummary {
        let balance = Decimal(482_545_075) / 100

        return DashboardSummary(
            customerFirstName: "นกน้อย",
            primaryAccount: Account(
                id: primaryAccountID,
                name: "บัญชีหลัก พรีเมียร์",
                maskedNumber: "•••• 4289",
                balance: balance
            ),
            monthChange: 307_200,
            monthChangeRate: Decimal(68) / 10,
            balanceHistory: balanceHistory(endingAt: balance, now: now, calendar: calendar),
            cashbackThisMonth: 12_400,
            cashbackTrend: [1_800, 2_700, 2_300, 3_900, 6_200],
            spending: SpendingSummary(categories: [
                SpendingCategory(kind: .lifestyle, spent: 38_200, budget: 50_000),
                SpendingCategory(kind: .travel, spent: 12_400, budget: 25_000),
            ]),
            savingsGoal: SavingsGoal(saved: 186_000, target: 240_000),
            recentTransactions: transactions(now: now, calendar: calendar)
        )
    }

    static func transactions(now: Date = Date(), calendar: Calendar = .current) -> [Transaction] {
        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        return [
            Transaction(id: UUID(), merchant: "Sarnies Bangkok", monogram: "SB", category: .food,
                        date: date(daysAgo: 0, hour: 19, minute: 10), amount: -580),
            Transaction(id: UUID(), merchant: "Wealth Plus", monogram: "WP", category: .investment,
                        date: date(daysAgo: 2, hour: 14, minute: 25), amount: 12_800),
            Transaction(id: UUID(), merchant: "คอนโด เดอะ ริเวอร์", monogram: nil, category: .housing,
                        date: date(daysAgo: 1, hour: 9, minute: 30), amount: -28_500),
            Transaction(id: UUID(), merchant: "BTS Rabbit", monogram: nil, category: .transport,
                        date: date(daysAgo: 5, hour: 8, minute: 0), amount: -1_250),
        ]
        .sorted { $0.date > $1.date }
    }

    /// One point per day for a year, trending up with a gentle wave.
    static func balanceHistory(endingAt balance: Decimal, now: Date, calendar: Calendar, days: Int = 365) -> [BalancePoint] {
        let end = NSDecimalNumber(decimal: balance).doubleValue
        return (0..<days).map { index in
            let daysAgo = days - 1 - index
            let trend = Double(daysAgo) * 10_240
            let wave = sin(Double(index) / 4) * 18_000 * (daysAgo == 0 ? 0 : 1)
            let value = (end - trend + wave).rounded()
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return BalancePoint(date: day, balance: daysAgo == 0 ? balance : Decimal(value))
        }
    }
}

struct MockDashboardRepository: DashboardRepository {
    var shouldFail = false
    var now: () -> Date = Date.init

    func fetchDashboard() async throws -> DashboardSummary {
        if shouldFail { throw RepositoryError.unavailable }
        return MockBankData.dashboard(now: now())
    }
}
