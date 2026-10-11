import Foundation

/// A Thai bank reachable for other-bank transfers (`GET /banks`).
struct Bank: Identifiable, Equatable, Hashable {
    let code: String
    let name: String
    let monogram: String
    var id: String { code }
}

/// Who receives a transfer (TRF-01…04, TRF-11). Saved payees are paid by id so full numbers stay on the server.
enum TransferRecipient: Equatable, Hashable {
    case own(accountID: UUID)
    case luxeBank(accountNumber: String)
    case otherBank(bankCode: String, accountNumber: String)
    case promptPay(proxy: String)
    case payee(id: UUID)
}

enum RecipientKind: String, CaseIterable, Identifiable {
    case own
    case luxeBank = "internal"
    case otherBank = "other_bank"
    case promptPay = "promptpay"
    case bill

    var id: Self { self }

    /// Tabs on the recipient screen (S08).
    static let transferTabs: [RecipientKind] = [.own, .luxeBank, .otherBank, .promptPay]

    var title: LocalizedStringResource {
        switch self {
        case .own: "recipient.own"
        case .luxeBank: "recipient.luxeBank"
        case .otherBank: "recipient.otherBank"
        case .promptPay: "recipient.promptPay"
        case .bill: "recipient.bill"
        }
    }
}

struct Payee: Identifiable, Equatable, Hashable {
    let id: UUID
    let kind: RecipientKind
    let name: String
    let nickname: String?
    let bankCode: String?
    let bankName: String?
    let account: String
    let favorite: Bool

    var displayName: String { nickname ?? name }
    var initial: String { String(displayName.prefix(1)) }
}

struct PaymentParty: Equatable, Hashable {
    let name: String
    let bankCode: String?
    let bankName: String?
    let account: String?
}

struct BillInfo: Equatable, Hashable {
    let billerCode: String
    let billerName: String
    let ref1: String
    let ref2: String?
    let customerName: String
    let dueDate: Date?
}

/// A priced, name-checked payment waiting for confirmation; valid until `expiresAt` (TRF-05, TRF-06).
struct PaymentInquiry: Equatable, Hashable, Identifiable {
    let id: UUID
    let challenge: String
    let expiresAt: Date
    let kind: RecipientKind
    let amount: Decimal
    let fee: Decimal
    let memo: String?
    let from: PaymentParty
    let to: PaymentParty
    let requiresBiometric: Bool
    let bill: BillInfo?
}

struct PaymentSlip: Equatable, Hashable, Identifiable {
    let transactionID: UUID
    let referenceNo: String
    let kind: RecipientKind
    let occurredAt: Date
    let amount: Decimal
    let fee: Decimal
    let memo: String?
    let from: PaymentParty
    let to: PaymentParty
    /// Bank slip-verification mini QR payload (TRF-10).
    let slipQR: String
    let bill: BillInfo?

    var id: UUID { transactionID }
}

struct TransferLimits: Equatable {
    let dailyLimit: Decimal
    let usedToday: Decimal
    let remaining: Decimal
}

enum BillerCategory: String, CaseIterable, Identifiable {
    case electricity
    case water
    case internet
    case creditCard = "credit_card"
    case insurance
    case mobile
    case ewallet

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .electricity: "biller.electricity"
        case .water: "biller.water"
        case .internet: "biller.internet"
        case .creditCard: "biller.creditCard"
        case .insurance: "biller.insurance"
        case .mobile: "biller.mobile"
        case .ewallet: "biller.ewallet"
        }
    }

    var symbol: String {
        switch self {
        case .electricity: "bolt"
        case .water: "drop"
        case .internet: "wifi"
        case .creditCard: "creditcard"
        case .insurance: "shield"
        case .mobile: "iphone"
        case .ewallet: "wallet.pass"
        }
    }
}

struct Biller: Identifiable, Equatable, Hashable {
    let code: String
    let name: String
    let category: BillerCategory?
    let ref1Label: String
    let ref2Label: String?
    let topUp: Bool
    let monogram: String
    var id: String { code }
}

struct SavedBill: Identifiable, Equatable, Hashable {
    let id: UUID
    let biller: Biller
    let ref1: String
    let nickname: String?
    let amountDue: Decimal?
    let dueDate: Date?
    let paid: Bool

    var displayName: String {
        nickname.map { "\(biller.name) · \($0)" } ?? biller.name
    }
}

/// What a scanned Thai QR asks to pay (TRF-12, BILL-02).
struct ParsedQR: Equatable {
    enum Kind: String {
        case promptPay = "promptpay"
        case bill
    }

    let kind: Kind
    let proxy: String?
    let billerCode: String?
    let billerName: String?
    let ref1: String?
    let ref2: String?
    let amount: Decimal?
    let merchantName: String?
}

/// Proof for `POST /transfers` and `/bills/payments`: the device key signs the inquiry challenge (TRF-07, TRF-09).
struct PaymentAuthorization: Equatable {
    let method: LoginMethod
    let signature: Data
    let pin: String?
}

/// Rules shared by the amount keypad and the server (TRF-08, TRF-09).
enum PaymentRules {
    /// Amounts from this value need Face ID (D7).
    static let stepUpAmount: Decimal = 50_000
    static let maxAmount: Decimal = 99_999_999

    /// Appends a keypad character to an amount string: digits, at most one ".", two decimals, no leading zeros.
    static func append(_ key: Character, to text: String) -> String {
        if key == "." {
            guard !text.contains(".") else { return text }
            return (text.isEmpty ? "0" : text) + "."
        }
        guard key.isNumber else { return text }
        if let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 2 { return text }
        let next = text == "0" ? String(key) : text + String(key)
        guard let value = Decimal(string: next, locale: Locale(identifier: "en_US_POSIX")), value <= maxAmount else { return text }
        return next
    }

    static func amount(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Mobile number (0XXXXXXXXX), 13-digit national ID or 15-digit e-wallet ID.
    static func isValidProxy(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        switch digits.count {
        case 10: return digits.hasPrefix("0")
        case 13: return CitizenID.isValid(digits)
        case 15: return true
        default: return false
        }
    }
}
