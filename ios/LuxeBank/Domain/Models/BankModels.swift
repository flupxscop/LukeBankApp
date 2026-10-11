import Foundation

struct Account: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let maskedNumber: String
    let balance: Decimal
}

/// Server category codes (`/transactions`). Unknown codes from a newer server read as `.other`.
enum TransactionCategory: String, CaseIterable, Identifiable {
    case food
    case shopping
    case housing
    case bills
    case transport
    case travel
    case investment
    case transfer
    case income
    case cashback
    case other

    var id: Self { self }

    init(code: String) {
        self = TransactionCategory(rawValue: code) ?? .other
    }

    /// Categories a customer can move a transaction into (TXN-05).
    static let assignable: [TransactionCategory] = [.food, .shopping, .housing, .bills, .transport, .travel, .other]

    var title: LocalizedStringResource {
        switch self {
        case .food: "category.food"
        case .shopping: "category.shopping"
        case .housing: "category.housing"
        case .bills: "category.bills"
        case .transport: "category.transport"
        case .travel: "category.travel"
        case .investment: "category.investment"
        case .transfer: "category.transfer"
        case .income: "category.income"
        case .cashback: "category.cashback"
        case .other: "category.other"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .shopping: "bag"
        case .housing: "house"
        case .bills: "doc.text"
        case .transport: "tram"
        case .travel: "airplane"
        case .investment: "chart.line.uptrend.xyaxis"
        case .transfer: "arrow.left.arrow.right"
        case .income: "arrow.down.left"
        case .cashback: "gift"
        case .other: "circle.grid.2x2"
        }
    }
}

enum TransactionChannel: String {
    case promptpay
    case transfer
    case card
    case bill
    case deposit
    case interest
    case cashback
    case system

    var title: LocalizedStringResource {
        switch self {
        case .promptpay: "channel.promptpay"
        case .transfer: "channel.transfer"
        case .card: "channel.card"
        case .bill: "channel.bill"
        case .deposit: "channel.deposit"
        case .interest: "channel.interest"
        case .cashback: "channel.cashback"
        case .system: "channel.system"
        }
    }
}

struct Transaction: Identifiable, Equatable, Hashable {
    let id: UUID
    let merchant: String
    /// Short initials shown instead of the category icon, e.g. "SB".
    let monogram: String?
    let category: TransactionCategory
    let date: Date
    let amount: Decimal
    var channel: TransactionChannel = .card
    var memo: String?

    var isIncome: Bool { amount > 0 }
}

struct TransactionDetail: Equatable {
    var transaction: Transaction
    let referenceNo: String
    let isPosted: Bool
    let accountName: String
    let accountMaskedNumber: String
    var hasSlip = false
}

struct MoneyTotals: Equatable {
    let moneyIn: Decimal
    let moneyOut: Decimal
}

struct TransactionPage: Equatable {
    let items: [Transaction]
    let nextCursor: String?
    /// Totals over the whole filtered range; only on the first page.
    let totals: MoneyTotals?
}

enum TransactionDirection: String, CaseIterable, Identifiable {
    case incoming = "in"
    case outgoing = "out"

    var id: Self { self }
}

/// Filters for the history screen (TXN-01…03).
struct TransactionQuery: Equatable {
    var direction: TransactionDirection?
    var category: TransactionCategory?
    var periodDays: Int = 30
    var text: String = ""

    static let periods = [7, 30, 90, 365]
}

struct BalancePoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let balance: Decimal

    /// Charts cannot plot `Decimal`; only used for drawing.
    var chartValue: Double { NSDecimalNumber(decimal: balance).doubleValue }
}

enum SpendingKind: String, CaseIterable {
    case lifestyle
    case travel

    var title: LocalizedStringResource {
        switch self {
        case .lifestyle: "spending.lifestyle"
        case .travel: "spending.travel"
        }
    }
}

struct SpendingCategory: Identifiable, Equatable {
    var id: SpendingKind { kind }
    let kind: SpendingKind
    let spent: Decimal
    let budget: Decimal
}

struct SpendingSummary: Equatable {
    let categories: [SpendingCategory]

    var totalSpent: Decimal { categories.reduce(0) { $0 + $1.spent } }
    var totalBudget: Decimal { categories.reduce(0) { $0 + $1.budget } }

    /// Share of the whole budget used by one category (0...1), for the ring chart.
    func share(of kind: SpendingKind) -> Double {
        guard totalBudget > 0, let category = categories.first(where: { $0.kind == kind }) else { return 0 }
        return NSDecimalNumber(decimal: category.spent / totalBudget).doubleValue
    }

    var usage: Double {
        guard totalBudget > 0 else { return 0 }
        return NSDecimalNumber(decimal: totalSpent / totalBudget).doubleValue
    }
}

struct SavingsGoal: Equatable {
    var name: String = ""
    let saved: Decimal
    let target: Decimal

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: saved / target).doubleValue)
    }
}

struct DashboardSummary: Equatable {
    let customerFirstName: String
    let primaryAccount: Account
    var accounts: [Account] = []
    let monthChange: Decimal
    let monthChangeRate: Decimal
    let balanceHistory: [BalancePoint]
    let cashbackThisMonth: Decimal
    /// Weekly cashback, oldest first.
    let cashbackTrend: [Decimal]
    let spending: SpendingSummary
    let savingsGoal: SavingsGoal?
    var recentTransactions: [Transaction]
}

enum DayGreeting: Equatable {
    case morning
    case afternoon
    case evening

    init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        default: self = .evening
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .morning: "greeting.morning"
        case .afternoon: "greeting.afternoon"
        case .evening: "greeting.evening"
        }
    }
}

enum QuickAction: CaseIterable {
    case transfer
    case scan
    case payBill
    case topUp

    var title: LocalizedStringResource {
        switch self {
        case .transfer: "action.transfer"
        case .scan: "action.scan"
        case .payBill: "action.payBill"
        case .topUp: "action.topUp"
        }
    }

    var symbol: String {
        switch self {
        case .transfer: "arrow.up.right"
        case .scan: "qrcode.viewfinder"
        case .payBill: "doc.text"
        case .topUp: "plus"
        }
    }
}
