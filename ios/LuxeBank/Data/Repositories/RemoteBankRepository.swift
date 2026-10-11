import Foundation

/// `/dashboard`, `/accounts/{id}/transactions` and `/transactions/{id}` (spec section 9).
/// Money arrives as decimal strings and becomes `Decimal` here; a malformed amount fails the whole response.
final class RemoteBankRepository: DashboardRepository, TransactionRepository {
    private let api: AuthorizedAPI

    init(api: AuthorizedAPI) {
        self.api = api
    }

    func fetchDashboard() async throws -> DashboardSummary {
        let dto: DashboardDTO = try await api.send(APIRequest(method: "GET", path: "dashboard"))
        return try dto.domain()
    }

    func transactions(accountID: UUID, query: TransactionQuery, cursor: String?) async throws -> TransactionPage {
        var items = [URLQueryItem(name: "limit", value: String(Self.pageSize))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction = query.direction { items.append(URLQueryItem(name: "direction", value: direction.rawValue)) }
        if let category = query.category { items.append(URLQueryItem(name: "category", value: category.rawValue)) }
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(URLQueryItem(name: "q", value: String(text.prefix(Self.maxQueryLength)))) }
        let from = Calendar.bank.date(byAdding: .day, value: -(query.periodDays - 1), to: Date()) ?? Date()
        items.append(URLQueryItem(name: "from", value: DayFormat.string(from)))

        let dto: TransactionPageDTO = try await api.send(
            APIRequest(method: "GET", path: "accounts/\(accountID.uuidString)/transactions", query: items)
        )
        return try dto.domain()
    }

    func transaction(id: UUID) async throws -> TransactionDetail {
        let dto: TransactionDetailDTO = try await api.send(APIRequest(method: "GET", path: "transactions/\(id.uuidString)"))
        return try dto.domain()
    }

    func updateTransaction(id: UUID, category: TransactionCategory?, memo: String?) async throws -> TransactionDetail {
        struct Body: Encodable {
            let category: String?
            let memo: String?
            let clearMemo: Bool
        }
        let trimmed = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Body(category: category?.rawValue, memo: trimmed?.isEmpty == false ? trimmed : nil, clearMemo: trimmed?.isEmpty == true)
        let dto: TransactionDetailDTO = try await api.send(APIRequest(method: "PATCH", path: "transactions/\(id.uuidString)", body: body))
        return try dto.domain()
    }

    static let pageSize = 20
    static let maxQueryLength = 50
}

// MARK: - Wire format

private struct AccountDTO: Decodable {
    let id: UUID
    let name: String
    let maskedNumber: String
    let balance: String

    func domain() throws -> Account {
        Account(id: id, name: name, maskedNumber: maskedNumber, balance: try MoneyString.decimal(balance))
    }
}

private struct TransactionDTO: Decodable {
    let id: UUID
    let merchant: String
    let monogram: String?
    let category: String
    let channel: String
    let occurredAt: String
    let amount: String
    let memo: String?

    func domain() throws -> Transaction {
        guard let date = ISO8601DateFormatter().date(from: occurredAt) else { throw APIError.decoding }
        return Transaction(
            id: id,
            merchant: merchant,
            monogram: monogram,
            category: TransactionCategory(code: category),
            date: date,
            amount: try MoneyString.decimal(amount),
            channel: TransactionChannel(rawValue: channel) ?? .system,
            memo: memo
        )
    }
}

private struct TransactionPageDTO: Decodable {
    struct Totals: Decodable {
        let moneyIn: String
        let moneyOut: String
    }

    let items: [TransactionDTO]
    let nextCursor: String?
    let summary: Totals?

    func domain() throws -> TransactionPage {
        TransactionPage(
            items: try items.map { try $0.domain() },
            nextCursor: nextCursor,
            totals: try summary.map { MoneyTotals(moneyIn: try MoneyString.decimal($0.moneyIn), moneyOut: try MoneyString.decimal($0.moneyOut)) }
        )
    }
}

private struct TransactionDetailDTO: Decodable {
    struct AccountRef: Decodable {
        let name: String
        let maskedNumber: String
    }

    let transaction: TransactionDTO
    let referenceNo: String
    let status: String
    let account: AccountRef

    func domain() throws -> TransactionDetail {
        TransactionDetail(
            transaction: try transaction.domain(),
            referenceNo: referenceNo,
            isPosted: status == "posted",
            accountName: account.name,
            accountMaskedNumber: account.maskedNumber
        )
    }
}

private struct DashboardDTO: Decodable {
    struct Point: Decodable {
        let date: String
        let balance: String
    }

    struct SpendingKindDTO: Decodable {
        let kind: String
        let spent: String
        let budget: String
    }

    struct Spending: Decodable {
        let categories: [SpendingKindDTO]
    }

    struct Goal: Decodable {
        let name: String
        let saved: String
        let target: String
    }

    let customerFirstName: String
    let primaryAccount: AccountDTO
    let accounts: [AccountDTO]
    let monthChange: String
    let monthChangeRate: String
    let balanceHistory: [Point]
    let cashbackThisMonth: String
    let cashbackTrend: [String]
    let spending: Spending
    let savingsGoal: Goal?
    let recentTransactions: [TransactionDTO]

    func domain() throws -> DashboardSummary {
        DashboardSummary(
            customerFirstName: customerFirstName,
            primaryAccount: try primaryAccount.domain(),
            accounts: try accounts.map { try $0.domain() },
            monthChange: try MoneyString.decimal(monthChange),
            monthChangeRate: try MoneyString.decimal(monthChangeRate),
            balanceHistory: try balanceHistory.map { point in
                guard let date = DayFormat.date(point.date) else { throw APIError.decoding }
                return BalancePoint(date: date, balance: try MoneyString.decimal(point.balance))
            },
            cashbackThisMonth: try MoneyString.decimal(cashbackThisMonth),
            cashbackTrend: try cashbackTrend.map(MoneyString.decimal),
            spending: SpendingSummary(categories: try spending.categories.compactMap { item in
                guard let kind = SpendingKind(rawValue: item.kind) else { return nil }
                return SpendingCategory(kind: kind, spent: try MoneyString.decimal(item.spent), budget: try MoneyString.decimal(item.budget))
            }),
            savingsGoal: try savingsGoal.map {
                SavingsGoal(name: $0.name, saved: try MoneyString.decimal($0.saved), target: try MoneyString.decimal($0.target))
            },
            recentTransactions: try recentTransactions.map { try $0.domain() }
        )
    }
}

/// "-580.00" → Decimal, parsed with a fixed POSIX locale so device settings cannot change the value.
enum MoneyString {
    static func decimal(_ value: String) throws -> Decimal {
        guard value.wholeMatch(of: /-?\d+(\.\d{1,2})?/) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw APIError.decoding
        }
        return decimal
    }
}

/// Business days are Thai calendar days (spec 6.5).
enum DayFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.bank.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(_ value: String) -> Date? { formatter.date(from: value) }
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}

extension Calendar {
    /// Gregorian calendar in Thai time, for grouping and API dates.
    static let bank: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        return calendar
    }()
}
