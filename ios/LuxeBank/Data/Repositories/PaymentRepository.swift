import Foundation

/// Transfers, bills, payees and QR (spec section 9 "Transfers & Bills").
/// Confirmations carry an idempotency key; retry with the same key after a network error (TRF-14).
protocol PaymentRepository {
    func accounts() async throws -> [Account]
    func banks() async throws -> [Bank]
    func limits(accountID: UUID) async throws -> TransferLimits
    func payees() async throws -> [Payee]
    func deletePayee(id: UUID) async throws
    func transferInquiry(from accountID: UUID, to recipient: TransferRecipient, amount: Decimal, memo: String?) async throws -> PaymentInquiry
    func confirmTransfer(
        inquiryID: UUID, authorization: PaymentAuthorization, idempotencyKey: String, saveAsFavorite: Bool
    ) async throws -> PaymentSlip
    func billers(category: BillerCategory?) async throws -> [Biller]
    func savedBills() async throws -> [SavedBill]
    func billInquiry(from accountID: UUID, request: BillRequest) async throws -> PaymentInquiry
    func payBill(inquiryID: UUID, authorization: PaymentAuthorization, idempotencyKey: String, saveBill: Bool) async throws -> PaymentSlip
    func parseQR(_ payload: String) async throws -> ParsedQR
    func slip(transactionID: UUID) async throws -> PaymentSlip
}

/// A bill to price: either a saved bill or a biller with references; `amount` is required for top-ups.
struct BillRequest: Equatable {
    var billerCode: String?
    var ref1: String?
    var ref2: String?
    var savedBillID: UUID?
    var amount: Decimal?
}

final class RemotePaymentRepository: PaymentRepository {
    private let api: AuthorizedAPI

    init(api: AuthorizedAPI) {
        self.api = api
    }

    func accounts() async throws -> [Account] {
        let items: [PaymentDTO.Account] = try await api.send(APIRequest(method: "GET", path: "accounts"))
        return try items.map { try $0.domain() }
    }

    func banks() async throws -> [Bank] {
        let items: [PaymentDTO.BankItem] = try await api.send(APIRequest(method: "GET", path: "banks"))
        return items.map { Bank(code: $0.code, name: $0.name, monogram: $0.monogram) }
    }

    func limits(accountID: UUID) async throws -> TransferLimits {
        let dto: PaymentDTO.Limits = try await api.send(
            APIRequest(method: "GET", path: "transfers/limits", query: [URLQueryItem(name: "accountId", value: accountID.uuidString)])
        )
        return TransferLimits(
            dailyLimit: try MoneyString.decimal(dto.dailyLimit),
            usedToday: try MoneyString.decimal(dto.usedToday),
            remaining: try MoneyString.decimal(dto.remaining)
        )
    }

    func payees() async throws -> [Payee] {
        let items: [PaymentDTO.PayeeItem] = try await api.send(APIRequest(method: "GET", path: "payees"))
        return items.map(\.domain)
    }

    func deletePayee(id: UUID) async throws {
        try await api.sendWithoutResponse(method: "DELETE", path: "payees/\(id.uuidString)")
    }

    func transferInquiry(from accountID: UUID, to recipient: TransferRecipient, amount: Decimal, memo: String?) async throws -> PaymentInquiry {
        let body = PaymentDTO.TransferInquiryBody(
            fromAccountId: accountID, recipient: .init(recipient), amount: MoneyString.string(amount), memo: memo?.nilIfBlank
        )
        let dto: PaymentDTO.Inquiry = try await api.send(APIRequest(method: "POST", path: "transfers/inquiry", body: body))
        return try dto.domain()
    }

    func confirmTransfer(
        inquiryID: UUID, authorization: PaymentAuthorization, idempotencyKey: String, saveAsFavorite: Bool
    ) async throws -> PaymentSlip {
        let body = PaymentDTO.ConfirmBody(inquiryID: inquiryID, authorization: authorization, saveAsFavorite: saveAsFavorite, saveBill: false)
        let dto: PaymentDTO.Slip = try await api.send(
            APIRequest(method: "POST", path: "transfers", body: body, headers: ["Idempotency-Key": idempotencyKey])
        )
        return try dto.domain()
    }

    func billers(category: BillerCategory?) async throws -> [Biller] {
        let query = category.map { [URLQueryItem(name: "category", value: $0.rawValue)] } ?? []
        let items: [PaymentDTO.BillerItem] = try await api.send(APIRequest(method: "GET", path: "billers", query: query))
        return items.map(\.domain)
    }

    func savedBills() async throws -> [SavedBill] {
        let items: [PaymentDTO.SavedBillItem] = try await api.send(APIRequest(method: "GET", path: "bills/saved"))
        return try items.map { try $0.domain() }
    }

    func billInquiry(from accountID: UUID, request: BillRequest) async throws -> PaymentInquiry {
        let body = PaymentDTO.BillInquiryBody(
            fromAccountId: accountID,
            billerCode: request.billerCode,
            ref1: request.ref1,
            ref2: request.ref2?.nilIfBlank,
            savedBillId: request.savedBillID,
            amount: request.amount.map(MoneyString.string)
        )
        let dto: PaymentDTO.Inquiry = try await api.send(APIRequest(method: "POST", path: "bills/inquiry", body: body))
        return try dto.domain()
    }

    func payBill(inquiryID: UUID, authorization: PaymentAuthorization, idempotencyKey: String, saveBill: Bool) async throws -> PaymentSlip {
        let body = PaymentDTO.ConfirmBody(inquiryID: inquiryID, authorization: authorization, saveAsFavorite: false, saveBill: saveBill)
        let dto: PaymentDTO.Slip = try await api.send(
            APIRequest(method: "POST", path: "bills/payments", body: body, headers: ["Idempotency-Key": idempotencyKey])
        )
        return try dto.domain()
    }

    func parseQR(_ payload: String) async throws -> ParsedQR {
        let dto: PaymentDTO.QRResult = try await api.send(APIRequest(method: "POST", path: "qr/parse", body: ["payload": payload]))
        return try dto.domain()
    }

    func slip(transactionID: UUID) async throws -> PaymentSlip {
        let dto: PaymentDTO.Slip = try await api.send(APIRequest(method: "GET", path: "transactions/\(transactionID.uuidString)/slip"))
        return try dto.domain()
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension MoneyString {
    /// Decimal → "75000.00" for request bodies; never locale-formatted.
    static func string(_ value: Decimal) -> String {
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: rounded as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Wire format

enum PaymentDTO {
    struct Account: Decodable {
        let id: UUID
        let name: String
        let maskedNumber: String
        let balance: String

        func domain() throws -> LuxeBank.Account {
            LuxeBank.Account(id: id, name: name, maskedNumber: maskedNumber, balance: try MoneyString.decimal(balance))
        }
    }

    struct BankItem: Decodable {
        let code: String
        let name: String
        let monogram: String
    }

    struct Limits: Decodable {
        let dailyLimit: String
        let usedToday: String
        let remaining: String
    }

    struct PayeeItem: Decodable {
        let id: UUID
        let type: String
        let name: String
        let nickname: String?
        let bankCode: String?
        let bankName: String?
        let account: String
        let favorite: Bool

        var domain: Payee {
            Payee(
                id: id, kind: RecipientKind(rawValue: type) ?? .otherBank, name: name, nickname: nickname,
                bankCode: bankCode, bankName: bankName, account: account, favorite: favorite
            )
        }
    }

    struct Recipient: Encodable {
        let type: String
        var accountId: UUID?
        var bankCode: String?
        var accountNumber: String?
        var proxy: String?
        var payeeId: UUID?

        init(_ recipient: TransferRecipient) {
            switch recipient {
            case .own(let id): type = "own"; accountId = id
            case .luxeBank(let number): type = "internal"; accountNumber = number
            case .otherBank(let bank, let number): type = "other_bank"; bankCode = bank; accountNumber = number
            case .promptPay(let proxy): type = "promptpay"; self.proxy = proxy
            case .payee(let id): type = "payee"; payeeId = id
            }
        }
    }

    struct TransferInquiryBody: Encodable {
        let fromAccountId: UUID
        let recipient: Recipient
        let amount: String
        let memo: String?
    }

    struct BillInquiryBody: Encodable {
        let fromAccountId: UUID
        let billerCode: String?
        let ref1: String?
        let ref2: String?
        let savedBillId: UUID?
        let amount: String?
    }

    struct ConfirmBody: Encodable {
        let inquiryId: UUID
        let method: LoginMethod
        let signature: String
        let pin: String?
        let saveAsFavorite: Bool
        let saveBill: Bool

        init(inquiryID: UUID, authorization: PaymentAuthorization, saveAsFavorite: Bool, saveBill: Bool) {
            inquiryId = inquiryID
            method = authorization.method
            signature = authorization.signature.base64EncodedString()
            pin = authorization.pin
            self.saveAsFavorite = saveAsFavorite
            self.saveBill = saveBill
        }
    }

    struct Party: Decodable {
        let name: String
        let bankCode: String?
        let bankName: String?
        let account: String?

        var domain: PaymentParty { PaymentParty(name: name, bankCode: bankCode, bankName: bankName, account: account) }
    }

    struct Bill: Decodable {
        let billerCode: String
        let billerName: String
        let ref1: String
        let ref2: String?
        let customerName: String
        let dueDate: String?

        var domain: BillInfo {
            BillInfo(
                billerCode: billerCode, billerName: billerName, ref1: ref1, ref2: ref2,
                customerName: customerName, dueDate: dueDate.flatMap(DayFormat.date)
            )
        }
    }

    struct Inquiry: Decodable {
        let inquiryId: UUID
        let challenge: String
        let expiresAt: String
        let recipientType: String
        let amount: String
        let fee: String
        let memo: String?
        let from: Party
        let to: Party
        let requiresBiometric: Bool
        let bill: Bill?

        func domain() throws -> PaymentInquiry {
            PaymentInquiry(
                id: inquiryId,
                challenge: challenge,
                expiresAt: try Timestamp.date(expiresAt),
                kind: RecipientKind(rawValue: recipientType) ?? .otherBank,
                amount: try MoneyString.decimal(amount),
                fee: try MoneyString.decimal(fee),
                memo: memo,
                from: from.domain,
                to: to.domain,
                requiresBiometric: requiresBiometric,
                bill: bill?.domain
            )
        }
    }

    struct Slip: Decodable {
        let transactionId: UUID
        let referenceNo: String
        let recipientType: String
        let occurredAt: String
        let amount: String
        let fee: String
        let memo: String?
        let from: Party
        let to: Party
        let slipQr: String
        let bill: Bill?

        func domain() throws -> PaymentSlip {
            PaymentSlip(
                transactionID: transactionId,
                referenceNo: referenceNo,
                kind: RecipientKind(rawValue: recipientType) ?? .otherBank,
                occurredAt: try Timestamp.date(occurredAt),
                amount: try MoneyString.decimal(amount),
                fee: try MoneyString.decimal(fee),
                memo: memo,
                from: from.domain,
                to: to.domain,
                slipQR: slipQr,
                bill: bill?.domain
            )
        }
    }

    struct BillerItem: Decodable {
        let code: String
        let name: String
        let category: String
        let ref1Label: String
        let ref2Label: String?
        let topUp: Bool
        let monogram: String

        var domain: Biller {
            Biller(
                code: code, name: name, category: BillerCategory(rawValue: category), ref1Label: ref1Label,
                ref2Label: ref2Label, topUp: topUp, monogram: monogram
            )
        }
    }

    struct SavedBillItem: Decodable {
        let id: UUID
        let biller: BillerItem
        let ref1: String
        let nickname: String?
        let amountDue: String?
        let dueDate: String?
        let paid: Bool

        func domain() throws -> SavedBill {
            SavedBill(
                id: id, biller: biller.domain, ref1: ref1, nickname: nickname,
                amountDue: try amountDue.map(MoneyString.decimal), dueDate: dueDate.flatMap(DayFormat.date), paid: paid
            )
        }
    }

    struct QRResult: Decodable {
        let type: String
        let proxy: String?
        let billerCode: String?
        let billerName: String?
        let ref1: String?
        let ref2: String?
        let amount: String?
        let merchantName: String?

        func domain() throws -> ParsedQR {
            guard let kind = ParsedQR.Kind(rawValue: type) else { throw APIError.decoding }
            return ParsedQR(
                kind: kind, proxy: proxy, billerCode: billerCode, billerName: billerName, ref1: ref1, ref2: ref2,
                amount: try amount.map(MoneyString.decimal), merchantName: merchantName
            )
        }
    }
}

/// Server timestamps: ISO 8601 with or without fractional seconds.
enum Timestamp {
    static func date(_ value: String) throws -> Date {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        throw APIError.decoding
    }
}
