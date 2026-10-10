import Foundation

struct Account: Identifiable, Equatable {
    let id: UUID
    let name: String
    let maskedNumber: String
    let balance: Decimal
}

enum TransactionCategory: String, CaseIterable {
    case food
    case housing
    case investment
    case transport
    case transfer

    var title: LocalizedStringResource {
        switch self {
        case .food: "category.food"
        case .housing: "category.housing"
        case .investment: "category.investment"
        case .transport: "category.transport"
        case .transfer: "category.transfer"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .housing: "house"
        case .investment: "chart.line.uptrend.xyaxis"
        case .transport: "tram"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}

struct Transaction: Identifiable, Equatable {
    let id: UUID
    let merchant: String
    /// Short initials shown instead of the category icon, e.g. "SB".
    let monogram: String?
    let category: TransactionCategory
    let date: Date
    let amount: Decimal

    var isIncome: Bool { amount > 0 }
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
    let monthChange: Decimal
    let monthChangeRate: Decimal
    let balanceHistory: [BalancePoint]
    let cashbackThisMonth: Decimal
    /// Weekly cashback, oldest first.
    let cashbackTrend: [Decimal]
    let spending: SpendingSummary
    let savingsGoal: SavingsGoal
    let recentTransactions: [Transaction]
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
