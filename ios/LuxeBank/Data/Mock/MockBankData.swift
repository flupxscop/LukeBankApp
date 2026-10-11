import Foundation

/// Deterministic sample data used by mock repositories, previews and tests.
enum MockBankData {
    static let primaryAccountID = UUID(uuidString: "6C1F4E0A-4289-4D7B-9C3E-1F2A3B4C4289") ?? UUID()

    static func primaryAccount(balance: Decimal = Decimal(482_545_075) / 100) -> Account {
        Account(id: primaryAccountID, name: "บัญชีหลัก พรีเมียร์", maskedNumber: "•••• 4289", balance: balance)
    }

    static func dashboard(now: Date = Date(), calendar: Calendar = .current) -> DashboardSummary {
        let balance = Decimal(482_545_075) / 100

        return DashboardSummary(
            customerFirstName: "นกน้อย",
            primaryAccount: primaryAccount(balance: balance),
            accounts: [primaryAccount(balance: balance)],
            monthChange: 307_200,
            monthChangeRate: Decimal(68) / 10,
            balanceHistory: balanceHistory(endingAt: balance, now: now, calendar: calendar),
            cashbackThisMonth: 12_400,
            cashbackTrend: [1_800, 2_700, 2_300, 3_900, 6_200],
            spending: SpendingSummary(categories: [
                SpendingCategory(kind: .lifestyle, spent: 38_200, budget: 50_000),
                SpendingCategory(kind: .travel, spent: 12_400, budget: 25_000),
            ]),
            savingsGoal: SavingsGoal(name: "ทริปญี่ปุ่น", saved: 186_000, target: 240_000),
            recentTransactions: Array(transactions(now: now, calendar: calendar).prefix(5))
        )
    }

    /// The design's sample rows plus two months of generated history, newest first. IDs are stable.
    static func transactions(now: Date = Date(), calendar: Calendar = .current) -> [Transaction] {
        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func id(_ index: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index)) ?? UUID()
        }

        var items = [
            Transaction(id: id(1), merchant: "Sarnies Bangkok", monogram: "SB", category: .food,
                        date: date(daysAgo: 0, hour: 19, minute: 10), amount: -580, channel: .card),
            Transaction(id: id(2), merchant: "คอนโด เดอะ ริเวอร์", monogram: nil, category: .housing,
                        date: date(daysAgo: 1, hour: 9, minute: 30), amount: -28_500, channel: .promptpay, memo: "ค่าเช่าเดือนตุลาคม"),
            Transaction(id: id(3), merchant: "จากบัญชีออมทรัพย์", monogram: nil, category: .transfer,
                        date: date(daysAgo: 1, hour: 8, minute: 5), amount: 20_000, channel: .transfer),
            Transaction(id: id(4), merchant: "Wealth Plus", monogram: "WP", category: .investment,
                        date: date(daysAgo: 2, hour: 14, minute: 25), amount: 12_800, channel: .transfer),
            Transaction(id: id(5), merchant: "BTS Rabbit", monogram: nil, category: .transport,
                        date: date(daysAgo: 5, hour: 8, minute: 0), amount: -1_250, channel: .card),
        ]

        struct Sample {
            let merchant: String
            let monogram: String
            let category: TransactionCategory
        }
        let generated = [
            Sample(merchant: "Roast Coffee", monogram: "RC", category: .food),
            Sample(merchant: "Gourmet Market", monogram: "GM", category: .food),
            Sample(merchant: "Central Chidlom", monogram: "CC", category: .shopping),
            Sample(merchant: "Grab", monogram: "GR", category: .travel),
            Sample(merchant: "AIS Fibre", monogram: "AIS", category: .bills),
            Sample(merchant: "LuxeBank Cashback", monogram: "LB", category: .cashback),
        ]
        var seed: UInt64 = 2026
        for index in 0..<40 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let sample = generated[Int(seed >> 33) % generated.count]
            let category = sample.category
            let baht = Decimal(Int(seed >> 40) % 2_400 + 60)
            items.append(Transaction(
                id: id(100 + index), merchant: sample.merchant, monogram: sample.monogram, category: category,
                date: date(daysAgo: 6 + index * 3 / 2, hour: 8 + index % 12, minute: (index * 7) % 60),
                amount: category == .cashback ? baht / 4 : -baht,
                channel: category == .cashback ? .cashback : (category == .bills ? .bill : .card)
            ))
        }
        return items.sorted { $0.date > $1.date }
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

/// In-memory dashboard and history with the same filtering and paging rules as the backend.
@MainActor
final class MockBankRepository: DashboardRepository, TransactionRepository {
    var shouldFail: Bool
    private let now: () -> Date
    private let calendar: Calendar
    private var store: [Transaction]

    init(shouldFail: Bool = false, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.shouldFail = shouldFail
        self.now = now
        self.calendar = calendar
        store = MockBankData.transactions(now: now(), calendar: calendar)
    }

    func fetchDashboard() async throws -> DashboardSummary {
        if shouldFail { throw RepositoryError.unavailable }
        var summary = MockBankData.dashboard(now: now(), calendar: calendar)
        summary.recentTransactions = Array(store.prefix(5))
        return summary
    }

    func transactions(accountID: UUID, query: TransactionQuery, cursor: String?) async throws -> TransactionPage {
        if shouldFail { throw RepositoryError.unavailable }
        let start = calendar.date(byAdding: .day, value: -(query.periodDays - 1), to: calendar.startOfDay(for: now())) ?? .distantPast
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = store.filter { item in
            item.date >= start
                && (query.category == nil || item.category == query.category)
                && (query.direction == nil || (query.direction == .incoming) == item.isIncome)
                && (text.isEmpty || item.merchant.localizedCaseInsensitiveContains(text) || (item.memo?.localizedCaseInsensitiveContains(text) ?? false))
        }
        let offset = cursor.flatMap(Int.init) ?? 0
        let page = Array(matches.dropFirst(offset).prefix(RemoteBankRepository.pageSize))
        let next = offset + page.count < matches.count ? String(offset + page.count) : nil
        let totals = cursor == nil
            ? MoneyTotals(
                moneyIn: matches.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                moneyOut: matches.filter { !$0.isIncome }.reduce(0) { $0 - $1.amount }
            )
            : nil
        return TransactionPage(items: page, nextCursor: next, totals: totals)
    }

    func transaction(id: UUID) async throws -> TransactionDetail {
        if shouldFail { throw RepositoryError.unavailable }
        guard let item = store.first(where: { $0.id == id }) else {
            throw APIError.server(code: "NOT_FOUND", message: "Resource not found", remainingAttempts: nil)
        }
        let suffix = String(id.uuidString.suffix(10)).replacingOccurrences(of: "-", with: "")
        return TransactionDetail(
            transaction: item,
            referenceNo: "LX261010" + suffix,
            isPosted: true,
            accountName: MockBankData.primaryAccount().name,
            accountMaskedNumber: MockBankData.primaryAccount().maskedNumber
        )
    }

    func updateTransaction(id: UUID, category: TransactionCategory?, memo: String?) async throws -> TransactionDetail {
        if shouldFail { throw RepositoryError.unavailable }
        guard let index = store.firstIndex(where: { $0.id == id }) else { return try await transaction(id: id) }
        let old = store[index]
        let trimmed = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        store[index] = Transaction(
            id: old.id, merchant: old.merchant, monogram: old.monogram, category: category ?? old.category, date: old.date,
            amount: old.amount, channel: old.channel, memo: trimmed.map { $0.isEmpty ? nil : $0 } ?? old.memo
        )
        return try await transaction(id: id)
    }
}

typealias MockDashboardRepository = MockBankRepository
