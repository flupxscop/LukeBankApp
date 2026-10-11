import Foundation

enum CardKind: String {
    case debit
    case credit
}

enum CardStatus: String {
    case active
    case frozen
    case lost
    case closed
}

/// Where a card may be used (CARD-05).
struct CardChannels: Equatable, Hashable {
    var online: Bool
    var overseas: Bool
    var contactless: Bool
    var atm: Bool
}

/// The simulated statement of a credit card (CARD-02).
struct CreditSummary: Equatable, Hashable {
    let limit: Decimal
    let used: Decimal
    let available: Decimal
    let minimumPayment: Decimal
    let dueDate: Date?

    /// Share of the limit in use (0...1), for the progress bar.
    var usage: Double {
        guard limit > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: used / limit).doubleValue)
    }
}

struct BankCard: Identifiable, Equatable, Hashable {
    let id: UUID
    let kind: CardKind
    let productName: String
    let last4: String
    /// "08/30"
    let expiry: String
    var status: CardStatus
    var channels: CardChannels
    var dailyLimit: Decimal
    let maxDailyLimit: Decimal
    let rewardPoints: Int
    let travelInsurance: Bool
    let credit: CreditSummary?
    /// Debit cards: the account they spend from, masked.
    let linkedAccount: String?
    let linkedBalance: Decimal?

    var isFrozen: Bool { status == .frozen }
}

/// Full number and CVV after Face ID (CARD-07). Held in memory only while shown.
struct CardSecrets: Equatable {
    let pan: String
    let cvv: String
    let expiry: String
    let visibleForSeconds: Int

    /// "4532 0175 2286 8821"
    var formattedPAN: String {
        stride(from: 0, to: pan.count, by: 4).map { offset -> String in
            let start = pan.index(pan.startIndex, offsetBy: offset)
            let end = pan.index(start, offsetBy: min(4, pan.count - offset))
            return String(pan[start..<end])
        }.joined(separator: " ")
    }
}

/// Changes to send with `PATCH /cards/{id}/controls`; nil keeps the current value.
struct CardControlsChange: Equatable {
    var channels: CardChannels?
    var dailyLimit: Decimal?
}
