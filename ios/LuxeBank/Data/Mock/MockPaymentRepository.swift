import Foundation

/// In-memory payments with the backend stub rules (spec 7.0): account numbers ending in 0000 do not exist,
/// numbers ending in 9999 are rejected by the other bank, Face ID is required from ฿50,000,
/// and a repeated idempotency key returns the first slip. Completed payments appear in the mock history.
@MainActor
final class MockPaymentRepository: PaymentRepository {
    var shouldFail = false
    /// Mirrors the server's AUTH-11 rule for a phone that reports itself compromised.
    var deviceCompromised = false
    var delay: Duration = .milliseconds(250)
    private let bank: MockBankRepository?
    private var inquiries: [UUID: PaymentInquiry] = [:]
    private var slipsByKey: [String: PaymentSlip] = [:]
    private var slips: [UUID: PaymentSlip] = [:]
    private var usedToday: Decimal = 0
    private var storedPayees: [Payee]
    private var paidBills: Set<String> = []

    static let banks = [
        Bank(code: "KBANK", name: "กสิกรไทย", monogram: "K"),
        Bank(code: "SCB", name: "ไทยพาณิชย์", monogram: "SCB"),
        Bank(code: "BBL", name: "กรุงเทพ", monogram: "BBL"),
        Bank(code: "KTB", name: "กรุงไทย", monogram: "KTB"),
        Bank(code: "BAY", name: "กรุงศรีอยุธยา", monogram: "BAY"),
    ]

    static let savingsAccount = Account(
        id: UUID(uuidString: "6C1F4E0A-7731-4D7B-9C3E-1F2A3B4C7731") ?? UUID(),
        name: "ออมทรัพย์ เป้าหมาย", maskedNumber: "•••• 7731", balance: 1_240_000
    )

    static let billerList = [
        Biller(code: "MEA", name: "การไฟฟ้านครหลวง", category: .electricity, ref1Label: "หมายเลขผู้ใช้ไฟฟ้า", ref2Label: nil, topUp: false, monogram: "MEA"),
        Biller(code: "MWA", name: "การประปานครหลวง", category: .water, ref1Label: "เลขที่ผู้ใช้น้ำ", ref2Label: nil, topUp: false, monogram: "MWA"),
        Biller(code: "AISFIB", name: "AIS Fibre", category: .internet, ref1Label: "หมายเลขบริการ", ref2Label: nil, topUp: false, monogram: "AIS"),
        Biller(
            code: "LXCARD", name: "บัตรเครดิต LuxeBank", category: .creditCard, ref1Label: "เลขบัตร 16 หลัก", ref2Label: nil, topUp: false,
            monogram: "LX", partialPayment: true
        ),
        Biller(code: "AISTOP", name: "เติมเงิน AIS", category: .mobile, ref1Label: "เบอร์โทรศัพท์", ref2Label: nil, topUp: true, monogram: "AIS"),
        Biller(code: "TMNW", name: "TrueMoney Wallet", category: .ewallet, ref1Label: "เบอร์โทรศัพท์", ref2Label: nil, topUp: true, monogram: "TMN"),
    ]

    private let savedBillID = UUID(uuidString: "5A7E0000-0000-4000-8000-000000000001") ?? UUID()

    init(bank: MockBankRepository? = nil) {
        self.bank = bank
        storedPayees = [
            Payee(
                id: UUID(), kind: .luxeBank, name: "สมศรี มี**", nickname: nil, bankCode: "LUXE", bankName: "ลักซ์แบงก์",
                account: "x4445", favorite: true
            ),
            Payee(id: UUID(), kind: .promptPay, name: "นาง วิไล ใจ**", nickname: "แม่", bankCode: nil, bankName: nil, account: "x5432", favorite: true),
            Payee(
                id: UUID(), kind: .otherBank, name: "นาย สมชาย ใจ**", nickname: nil, bankCode: "KBANK", bankName: "กสิกรไทย",
                account: "x7890", favorite: false
            ),
        ]
    }

    func accounts() async throws -> [Account] {
        try await pause()
        return [MockBankData.primaryAccount(), Self.savingsAccount]
    }

    func banks() async throws -> [Bank] {
        try await pause()
        return Self.banks
    }

    func limits(accountID: UUID) async throws -> TransferLimits {
        try await pause()
        return TransferLimits(dailyLimit: 200_000, usedToday: usedToday, remaining: max(0, 200_000 - usedToday))
    }

    func payees() async throws -> [Payee] {
        try await pause()
        return storedPayees
    }

    func deletePayee(id: UUID) async throws {
        try await pause()
        storedPayees.removeAll { $0.id == id }
    }

    func transferInquiry(from accountID: UUID, to recipient: TransferRecipient, amount: Decimal, memo: String?) async throws -> PaymentInquiry {
        try await pause()
        guard amount > 0 else { throw server("VALIDATION_FAILED") }
        guard amount <= MockBankData.primaryAccount().balance else { throw server("INSUFFICIENT_FUNDS") }
        let target = try resolve(recipient)
        if target.kind != .own, usedToday + amount > 200_000 { throw server("DAILY_LIMIT_EXCEEDED") }
        return store(kind: target.kind, amount: amount, memo: memo, to: target.party, bill: nil)
    }

    func confirmTransfer(
        inquiryID: UUID, authorization: PaymentAuthorization, idempotencyKey: String, saveAsFavorite: Bool
    ) async throws -> PaymentSlip {
        let isReplay = slipsByKey[idempotencyKey] != nil
        let slip = try await confirm(inquiryID: inquiryID, authorization: authorization, idempotencyKey: idempotencyKey)
        if slip.kind != .own, !isReplay { usedToday += slip.amount }
        return slip
    }

    func billers(category: BillerCategory?) async throws -> [Biller] {
        try await pause()
        return Self.billerList.filter { category == nil || $0.category == category }
    }

    func savedBills() async throws -> [SavedBill] {
        try await pause()
        let paid = paidBills.contains("MEA0123456789")
        return [
            SavedBill(
                id: savedBillID, biller: Self.billerList[0], ref1: "x6789", nickname: "บ้าน",
                amountDue: paid ? nil : 2_340, dueDate: dueDate(), paid: paid
            ),
        ]
    }

    func billInquiry(from accountID: UUID, request: BillRequest) async throws -> PaymentInquiry {
        try await pause()
        if request.cardID != nil {
            let owed: Decimal = 86_420
            let amount = request.amount ?? owed
            guard amount > 0, amount <= owed else { throw server("VALIDATION_FAILED") }
            let card = Self.billerList.first { $0.code == "LXCARD" }
            let bill = BillInfo(
                billerCode: "LXCARD", billerName: card?.name ?? "LuxeBank", ref1: "8821", ref2: nil, customerName: "นกน้อย ใจ**", dueDate: nil
            )
            let party = PaymentParty(name: card?.name ?? "", bankCode: nil, bankName: nil, account: "x8821")
            return store(kind: .bill, amount: amount, memo: nil, to: party, bill: bill)
        }
        let isSaved = request.savedBillID == savedBillID
        let code = isSaved ? "MEA" : (request.billerCode ?? "")
        let ref1 = isSaved ? "0123456789" : (request.ref1 ?? "")
        guard let biller = Self.billerList.first(where: { $0.code == code }) else { throw server("NOT_FOUND") }
        guard !ref1.isEmpty, ref1.allSatisfy(\.isNumber) else { throw server("VALIDATION_FAILED") }
        guard !ref1.allSatisfy({ $0 == "0" }) else { throw server("BILL_NOT_FOUND") }
        let due: Decimal? = biller.topUp ? nil : Decimal((code + ref1).unicodeScalars.reduce(0) { $0 + Int($1.value) } * 37 % 4_700 + 300)
        guard let amount = request.amount ?? due, amount > 0 else { throw server("VALIDATION_FAILED") }
        // Same rule as the server: full amount for utilities, up to the amount due for cards and insurance.
        if let due, amount != due, !(biller.partialPayment && amount < due) { throw server("VALIDATION_FAILED") }
        let bill = BillInfo(
            billerCode: code, billerName: biller.name, ref1: ref1, ref2: request.ref2, customerName: "นกน้อย ใจ**",
            dueDate: biller.topUp ? nil : dueDate()
        )
        let party = PaymentParty(name: biller.name, bankCode: nil, bankName: nil, account: "x" + ref1.suffix(4))
        return store(kind: .bill, amount: amount, memo: nil, to: party, bill: bill)
    }

    func payBill(inquiryID: UUID, authorization: PaymentAuthorization, idempotencyKey: String, saveBill: Bool) async throws -> PaymentSlip {
        let slip = try await confirm(inquiryID: inquiryID, authorization: authorization, idempotencyKey: idempotencyKey)
        if let bill = slip.bill { paidBills.insert(bill.billerCode + bill.ref1) }
        return slip
    }

    func parseQR(_ payload: String) async throws -> ParsedQR {
        try await pause()
        if payload.contains("A000000677010111") {
            return ParsedQR(
                kind: .promptPay, proxy: "0812345678", billerCode: nil, billerName: nil, ref1: nil, ref2: nil, amount: 120.5,
                merchantName: "Roast Coffee", amountLocked: true
            )
        }
        if payload.contains("A000000677010112") {
            return ParsedQR(
                kind: .bill, proxy: nil, billerCode: "MEA", billerName: "การไฟฟ้านครหลวง", ref1: "0123456789", ref2: nil, amount: nil, merchantName: nil
            )
        }
        throw server("QR_INVALID")
    }

    func slip(transactionID: UUID) async throws -> PaymentSlip {
        try await pause()
        guard let slip = slips[transactionID] else { throw server("NOT_FOUND") }
        return slip
    }

    // MARK: Helpers

    private struct Target {
        let kind: RecipientKind
        let party: PaymentParty
    }

    private func resolve(_ recipient: TransferRecipient) throws -> Target {
        switch recipient {
        case .own(let id):
            guard id == Self.savingsAccount.id else { throw server("VALIDATION_FAILED") }
            return Target(kind: .own, party: PaymentParty(name: Self.savingsAccount.name, bankCode: "LUXE", bankName: "ลักซ์แบงก์", account: "x7731"))
        case .luxeBank(let number):
            guard number.count == 10, !number.hasSuffix("0000") else { throw server("RECIPIENT_NOT_FOUND") }
            return Target(kind: .luxeBank, party: PaymentParty(name: "สมศรี มี**", bankCode: "LUXE", bankName: "ลักซ์แบงก์", account: "x" + number.suffix(4)))
        case .otherBank(let code, let number):
            guard !number.hasSuffix("0000") else { throw server("RECIPIENT_NOT_FOUND") }
            let bank = Self.banks.first { $0.code == code }
            return Target(kind: .otherBank, party: PaymentParty(name: "นาย สมชาย ใจ**", bankCode: code, bankName: bank?.name, account: "x" + number.suffix(4)))
        case .promptPay(let proxy):
            return try promptPay(proxy)
        case .payee(let id):
            guard let payee = storedPayees.first(where: { $0.id == id }) else { throw server("NOT_FOUND") }
            return Target(kind: payee.kind, party: PaymentParty(name: payee.name, bankCode: payee.bankCode, bankName: payee.bankName, account: payee.account))
        }
    }

    private func promptPay(_ proxy: String) throws -> Target {
        guard PaymentRules.isValidProxy(proxy) else { throw server("VALIDATION_FAILED") }
        guard !proxy.hasSuffix("0000") else { throw server("RECIPIENT_NOT_FOUND") }
        return Target(kind: .promptPay, party: PaymentParty(name: "นาง วิไล ใจ**", bankCode: "KBANK", bankName: "กสิกรไทย", account: "x" + proxy.suffix(4)))
    }

    private func store(kind: RecipientKind, amount: Decimal, memo: String?, to party: PaymentParty, bill: BillInfo?) -> PaymentInquiry {
        let inquiry = PaymentInquiry(
            id: UUID(), challenge: UUID().uuidString, expiresAt: Date().addingTimeInterval(300), kind: kind, amount: amount, fee: 0,
            memo: memo?.nilIfBlank,
            from: PaymentParty(name: MockBankData.primaryAccount().name, bankCode: "LUXE", bankName: "ลักซ์แบงก์", account: "x4289"),
            to: party, requiresBiometric: amount >= PaymentRules.stepUpAmount, bill: bill
        )
        inquiries[inquiry.id] = inquiry
        return inquiry
    }

    private func confirm(inquiryID: UUID, authorization: PaymentAuthorization, idempotencyKey: String) async throws -> PaymentSlip {
        try await pause()
        if deviceCompromised { throw server("DEVICE_COMPROMISED") }
        if let previous = slipsByKey[idempotencyKey] { return previous }
        guard let inquiry = inquiries[inquiryID] else { throw server("DUPLICATE_REQUEST") }
        guard inquiry.expiresAt > Date() else { throw server("INQUIRY_EXPIRED") }
        if inquiry.requiresBiometric, authorization.method != .biometric { throw server("STEP_UP_REQUIRED") }
        if inquiry.to.account?.hasSuffix("9999") == true { throw server("SERVICE_UNAVAILABLE") }
        inquiries[inquiryID] = nil

        let reference = "LX261010" + String(UUID().uuidString.filter(\.isLetter).prefix(10)).uppercased()
        let slip = PaymentSlip(
            transactionID: UUID(), referenceNo: reference, kind: inquiry.kind, occurredAt: Date(), amount: inquiry.amount, fee: 0,
            memo: inquiry.memo, from: PaymentParty(name: "นกน้อย ใจ**", bankCode: "LUXE", bankName: "ลักซ์แบงก์", account: "x4289"),
            to: inquiry.to, slipQR: "004600060000010103099022\(reference)5102TH9104ABCD", bill: inquiry.bill
        )
        slipsByKey[idempotencyKey] = slip
        slips[slip.transactionID] = slip
        bank?.record(Transaction(
            id: slip.transactionID, merchant: inquiry.bill?.billerName ?? inquiry.to.name, monogram: nil,
            category: inquiry.kind == .bill ? .bills : .transfer, date: slip.occurredAt, amount: -inquiry.amount,
            channel: inquiry.kind == .promptPay ? .promptpay : (inquiry.kind == .bill ? .bill : .transfer), memo: inquiry.memo
        ))
        return slip
    }

    private func dueDate() -> Date {
        let calendar = Calendar.bank
        let today = Date()
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = 25
        let due = calendar.date(from: components) ?? today
        return due < calendar.startOfDay(for: today) ? (calendar.date(byAdding: .month, value: 1, to: due) ?? due) : due
    }

    private func server(_ code: String) -> APIError {
        APIError.server(code: code, message: code, remainingAttempts: nil)
    }

    private func pause() async throws {
        if shouldFail { throw RepositoryError.unavailable }
        if delay > .zero { try await Task.sleep(for: delay) }
    }
}
