import Foundation
import Testing
@testable import LuxeBank

@MainActor
final class FakeAuthorizer: PaymentAuthorizing {
    var isBiometricEnabled = false
    var cancelBiometric = false
    private(set) var methods: [LoginMethod] = []
    private(set) var pinLocked = false

    func authorize(challenge: String, method: LoginMethod, pin: String?) async throws -> PaymentAuthorization {
        if method == .biometric, cancelBiometric { throw DeviceKeyError.missingKey }
        methods.append(method)
        return PaymentAuthorization(method: method, signature: Data(challenge.utf8), pin: pin)
    }

    func handlePinLocked() { pinLocked = true }
}

struct PaymentRulesTests {
    @Test(arguments: [
        ("", "1", "1"), ("0", "5", "5"), ("12", ".", "12."), ("", ".", "0."), ("12.", ".", "12."),
        ("12.3", "4", "12.34"), ("12.34", "5", "12.34"), ("99999999", "1", "99999999"), ("1", "x", "1"),
    ])
    func keypadBuildsValidAmounts(start: String, key: String, expected: String) {
        #expect(PaymentRules.append(Character(key), to: start) == expected)
    }

    @Test func proxiesAreMobileNationalIdOrWallet() {
        #expect(PaymentRules.isValidProxy("081-234-5678"))
        #expect(PaymentRules.isValidProxy("1234567890121"))
        #expect(PaymentRules.isValidProxy("123456789012345"))
        #expect(!PaymentRules.isValidProxy("1812345678"))
        #expect(!PaymentRules.isValidProxy("1234567890123"))
    }

    @Test func accountNumbersUseTheThaiLayout() {
        #expect(AccountNumberFormat.format("1234567890") == "123-4-56789-0")
        #expect(AccountNumberFormat.format("12345") == "12345")
    }

    @Test func moneyStringsAreExact() {
        #expect(MoneyString.string(Decimal(string: "75000") ?? 0) == "75000.00")
        #expect(MoneyString.string(Decimal(string: "0.5") ?? 0) == "0.50")
        #expect(MoneyString.string(Decimal(string: "1234567.89") ?? 0) == "1234567.89")
    }
}

@MainActor
struct TransferViewModelTests {
    private func makeViewModel(prefill: TransferPrefill? = nil) async -> (TransferViewModel, MockPaymentRepository) {
        let repository = MockPaymentRepository()
        repository.delay = .zero
        let viewModel = TransferViewModel(repository: repository, prefill: prefill)
        await viewModel.load()
        return (viewModel, repository)
    }

    @Test func recipientNeedsCompleteDetails() async {
        let (viewModel, _) = await makeViewModel()
        #expect(viewModel.kind == .otherBank)
        #expect(!viewModel.canContinue)
        viewModel.accountNumber = "1234567890"
        #expect(viewModel.recipient == .otherBank(bankCode: "KBANK", accountNumber: "1234567890"))

        viewModel.setKind(.promptPay)
        viewModel.proxy = "0812345678"
        #expect(viewModel.recipient == .promptPay(proxy: "0812345678"))

        viewModel.setKind(.own)
        #expect(viewModel.recipient == .own(accountID: MockPaymentRepository.savingsAccount.id))
    }

    @Test func amountIsCheckedAgainstBalanceAndLimitBeforeAskingTheServer() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.setKind(.promptPay)
        viewModel.proxy = "0812345678"
        viewModel.add(250_000)
        #expect(viewModel.amountProblem == "error.dailyLimit")
        #expect(!viewModel.canReview)

        viewModel.amountText = ""
        viewModel.add(50_000)
        #expect(viewModel.needsFaceID)
        #expect(viewModel.canReview)
    }

    @Test func reviewCreatesAnInquiryAndPushesConfirm() async throws {
        let (viewModel, _) = await makeViewModel()
        viewModel.accountNumber = "1234567890"
        viewModel.continueToAmount()
        "1500.5".forEach(viewModel.key)
        viewModel.memo = "  ค่าห้อง  "

        await viewModel.review()

        guard case .confirm(let inquiry) = viewModel.path.last else {
            Issue.record("Expected confirm step, got \(viewModel.path)")
            return
        }
        #expect(inquiry.amount == Decimal(string: "1500.5"))
        #expect(inquiry.memo == "ค่าห้อง")
        #expect(inquiry.to.name == "นาย สมชาย ใจ**")
        #expect(!inquiry.requiresBiometric)
    }

    @Test func unknownRecipientShowsAnError() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.accountNumber = "1234560000"
        viewModel.continueToAmount()
        viewModel.add(100)
        await viewModel.review()
        #expect(viewModel.error == "error.recipientNotFound")
        #expect(viewModel.path == [.amount])
    }

    @Test func prefillsFromAScannedQRAndSavedPayees() async {
        let (fromQR, _) = await makeViewModel(prefill: TransferPrefill(kind: .promptPay, proxy: "0812345678", amount: 120.5))
        #expect(fromQR.path == [.amount])
        #expect(fromQR.amount == Decimal(string: "120.5"))

        let repository = MockPaymentRepository()
        repository.delay = .zero
        let payee = try? await repository.payees().first
        let fromPayee = TransferViewModel(repository: repository, prefill: TransferPrefill(payeeID: payee?.id))
        await fromPayee.load()
        #expect(fromPayee.path == [.amount])
        #expect(fromPayee.recipient == payee.map { .payee(id: $0.id) })
    }
}

@MainActor
struct PaymentConfirmViewModelTests {
    private func inquiry(amount: Decimal = 500, expiresIn: TimeInterval = 300) -> PaymentInquiry {
        let party = PaymentParty(name: "นาย สมชาย ใจ**", bankCode: "KBANK", bankName: "กสิกรไทย", account: "x7890")
        return PaymentInquiry(
            id: UUID(), challenge: "challenge-1", expiresAt: Date().addingTimeInterval(expiresIn), kind: .otherBank, amount: amount,
            fee: 0, memo: nil, from: party, to: party, requiresBiometric: amount >= PaymentRules.stepUpAmount, bill: nil
        )
    }

    private func slip(for inquiry: PaymentInquiry) -> PaymentSlip {
        PaymentSlip(
            transactionID: UUID(), referenceNo: "LX1", kind: inquiry.kind, occurredAt: Date(), amount: inquiry.amount, fee: 0,
            memo: nil, from: inquiry.from, to: inquiry.to, slipQR: "qr", bill: nil
        )
    }

    @Test func pinConfirmationSignsTheChallengeAndReturnsTheSlip() async {
        let authorizer = FakeAuthorizer()
        let inquiry = inquiry()
        var sent: PaymentAuthorization?
        var sentKey: String?
        var saved: Bool?
        let viewModel = PaymentConfirmViewModel(inquiry: inquiry, authorizer: authorizer, saveByDefault: true) { auth, key, save in
            sent = auth
            sentKey = key
            saved = save
            return slip(for: inquiry)
        }

        await viewModel.confirm()
        #expect(viewModel.phase == .enteringPin)
        for digit in [4, 8, 2, 1, 9, 3] { await viewModel.appendPinDigit(digit) }

        #expect(viewModel.slip != nil)
        #expect(viewModel.phase == .done)
        #expect(viewModel.pin.isEmpty)
        #expect(sent?.method == .pin)
        #expect(sent?.pin == "482193")
        #expect(sent?.signature == Data("challenge-1".utf8))
        #expect(sentKey == viewModel.idempotencyKey)
        #expect(saved == true)
    }

    @Test func wrongPinStaysOnThePadAndRetriesWithTheSameKey() async {
        var keys: [String] = []
        var attempts = 0
        let inquiry = inquiry()
        let viewModel = PaymentConfirmViewModel(inquiry: inquiry, authorizer: FakeAuthorizer(), saveByDefault: false) { _, key, _ in
            keys.append(key)
            attempts += 1
            if attempts == 1 { throw APIError.server(code: "PIN_INVALID", message: "", remainingAttempts: 4) }
            return slip(for: inquiry)
        }
        await viewModel.confirm()
        for digit in [1, 1, 1, 2, 2, 2] { await viewModel.appendPinDigit(digit) }
        #expect(viewModel.phase == .enteringPin)
        #expect(viewModel.error == "error.pinInvalid \(4)")
        #expect(viewModel.pin.isEmpty)

        for digit in [4, 8, 2, 1, 9, 3] { await viewModel.appendPinDigit(digit) }
        #expect(viewModel.slip != nil)
        #expect(Set(keys).count == 1)
    }

    @Test func largeAmountsNeedFaceIdAndNeverOfferThePin() async {
        let authorizer = FakeAuthorizer()
        let big = inquiry(amount: 50_000)
        let viewModel = PaymentConfirmViewModel(inquiry: big, authorizer: authorizer, saveByDefault: false) { _, _, _ in slip(for: big) }

        await viewModel.confirm()
        #expect(viewModel.error == "error.stepUpSetup")
        #expect(!viewModel.canUsePin)
        viewModel.startPin()
        #expect(viewModel.phase == .review)

        authorizer.isBiometricEnabled = true
        await viewModel.confirm()
        #expect(authorizer.methods == [.biometric])
        #expect(viewModel.slip != nil)
    }

    @Test func cancelledFaceIdKeepsTheReview() async {
        let authorizer = FakeAuthorizer()
        authorizer.isBiometricEnabled = true
        authorizer.cancelBiometric = true
        let inquiry = inquiry()
        let viewModel = PaymentConfirmViewModel(inquiry: inquiry, authorizer: authorizer, saveByDefault: false) { _, _, _ in slip(for: inquiry) }
        await viewModel.confirm()
        #expect(viewModel.phase == .review)
        #expect(viewModel.error == "error.biometricCancelled")
    }

    @Test func serverErrorsMapToMessagesAndLockout() async {
        let authorizer = FakeAuthorizer()
        let inquiry = inquiry()
        var code = "SERVICE_UNAVAILABLE"
        let viewModel = PaymentConfirmViewModel(inquiry: inquiry, authorizer: authorizer, saveByDefault: false) { _, _, _ in
            throw APIError.server(code: code, message: "", remainingAttempts: nil)
        }
        await viewModel.confirm()
        for digit in [4, 8, 2, 1, 9, 3] { await viewModel.appendPinDigit(digit) }
        #expect(viewModel.error == "error.serviceUnavailable")
        #expect(viewModel.phase == .review)

        code = "PIN_LOCKED"
        viewModel.startPin()
        for digit in [4, 8, 2, 1, 9, 3] { await viewModel.appendPinDigit(digit) }
        #expect(authorizer.pinLocked)

        code = "INQUIRY_EXPIRED"
        viewModel.startPin()
        for digit in [4, 8, 2, 1, 9, 3] { await viewModel.appendPinDigit(digit) }
        #expect(viewModel.phase == .expired)
    }

    @Test func countdownExpiresTheReview() {
        let expired = inquiry(expiresIn: -1)
        let viewModel = PaymentConfirmViewModel(inquiry: expired, authorizer: FakeAuthorizer(), saveByDefault: false) { _, _, _ in
            throw APIError.network
        }
        #expect(viewModel.secondsLeft() == 0)
        viewModel.tick()
        #expect(viewModel.phase == .expired)
    }
}

@MainActor
struct BillPayViewModelTests {
    private let repository: MockPaymentRepository = {
        let repository = MockPaymentRepository()
        repository.delay = .zero
        return repository
    }()

    @Test func savedBillIsPricedWithoutReenteringTheReference() async throws {
        let saved = try #require(try await repository.savedBills().first)
        let viewModel = BillPayViewModel(target: BillTarget(biller: saved.biller, saved: saved), biller: nil, accounts: [], repository: repository)
        await viewModel.prepare()
        #expect(viewModel.canCheck)

        let inquiry = try #require(await viewModel.check())
        #expect(inquiry.bill?.billerCode == "MEA")
        #expect(inquiry.amount > 0)
    }

    @Test func topUpsNeedAnAmountAndUnknownReferencesFail() async {
        let topUp = MockPaymentRepository.billerList.first { $0.topUp }
        let viewModel = BillPayViewModel(target: BillTarget(biller: topUp, ref1: "0812345678"), biller: nil, accounts: [], repository: repository)
        await viewModel.prepare()
        #expect(!viewModel.canCheck)
        viewModel.amountText = "300"
        #expect(viewModel.canCheck)

        let electricity = MockPaymentRepository.billerList[0]
        let unknown = BillPayViewModel(target: BillTarget(biller: electricity, ref1: "0000000000"), biller: nil, accounts: [], repository: repository)
        await unknown.prepare()
        #expect(await unknown.check() == nil)
        #expect(unknown.error == "error.billNotFound")
    }
}

@MainActor
struct QRAndSlipTests {
    @Test func scannedPayloadIsParsedOnce() async {
        let repository = MockPaymentRepository()
        repository.delay = .zero
        let viewModel = QRScanViewModel(repository: repository)

        let first = await viewModel.handle("000201010212...A000000677010111...6304ABCD")
        let duplicate = await viewModel.handle("000201010212...A000000677010111...6304ABCD")
        #expect(first?.kind == .promptPay)
        #expect(duplicate == nil)

        #expect(await viewModel.handle("not a qr") == nil)
        #expect(viewModel.error == "error.qrInvalid")
    }

    @Test func slipQRRendersOnDevice() {
        #expect(QRCodeImage.make("004600060000010103099022LX261010K7M2Q9XA4C5102TH9104ABCD") != nil)
    }

    @Test func completedPaymentsAppearInHistoryWithASlip() async throws {
        let bank = MockBankRepository()
        let payments = MockPaymentRepository(bank: bank)
        payments.delay = .zero
        let inquiry = try await payments.transferInquiry(
            from: MockBankData.primaryAccountID, to: .promptPay(proxy: "0812345678"), amount: 100, memo: nil
        )
        let auth = PaymentAuthorization(method: .pin, signature: Data(), pin: "482193")
        let key = UUID().uuidString

        let slip = try await payments.confirmTransfer(inquiryID: inquiry.id, authorization: auth, idempotencyKey: key, saveAsFavorite: false)
        let again = try await payments.confirmTransfer(inquiryID: inquiry.id, authorization: auth, idempotencyKey: key, saveAsFavorite: false)

        #expect(again == slip)
        let detail = try await bank.transaction(id: slip.transactionID)
        #expect(detail.hasSlip)
        #expect(try await payments.slip(transactionID: slip.transactionID) == slip)
        #expect(try await payments.limits(accountID: MockBankData.primaryAccountID).usedToday == 100)
    }
}

extension APIClientTests {
    @MainActor
    struct RemotePaymentRepositoryTests {
        private let tokens = StubTokens()

        @Test func confirmSendsTheIdempotencyKeyAndSignature() async throws {
            let client = StubProtocol.client(status: 200, body: Self.slipJSON)
            let repository = RemotePaymentRepository(api: AuthorizedAPI(client: client, tokens: tokens))
            let auth = PaymentAuthorization(method: .pin, signature: Data([1, 2, 3]), pin: "482193")

            let slip = try await repository.confirmTransfer(
                inquiryID: UUID(), authorization: auth, idempotencyKey: "key-1234567890abcdef", saveAsFavorite: true
            )

            #expect(slip.amount == Decimal(string: "75000.00"))
            #expect(slip.kind == .otherBank)
            let request = try #require(StubProtocol.lastRequest)
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "key-1234567890abcdef")
            let json = try JSONSerialization.jsonObject(with: StubProtocol.body(of: request)) as? [String: Any]
            #expect(json?["signature"] as? String == Data([1, 2, 3]).base64EncodedString())
            #expect(json?["method"] as? String == "PIN")
            #expect(json?["saveAsFavorite"] as? Bool == true)
        }

        @Test func inquirySendsTheRecipientAndAnExactAmount() async throws {
            let client = StubProtocol.client(status: 200, body: Self.inquiryJSON)
            let repository = RemotePaymentRepository(api: AuthorizedAPI(client: client, tokens: tokens))

            let inquiry = try await repository.transferInquiry(
                from: UUID(), to: .otherBank(bankCode: "KBANK", accountNumber: "1234567890"), amount: Decimal(string: "75000.5") ?? 0, memo: " "
            )

            #expect(inquiry.requiresBiometric)
            let json = try JSONSerialization.jsonObject(with: StubProtocol.body(of: try #require(StubProtocol.lastRequest))) as? [String: Any]
            #expect(json?["amount"] as? String == "75000.50")
            let recipient = json?["recipient"] as? [String: Any]
            #expect(recipient?["type"] as? String == "other_bank")
            #expect(recipient?["bankCode"] as? String == "KBANK")
            #expect(json?["memo"] == nil || json?["memo"] is NSNull)
        }

        static let party = #"{"name":"นาย สมชาย ใจ**","bankCode":"KBANK","bankName":"กสิกรไทย","account":"x7890"}"#

        static let slipJSON = """
        {"transactionId":"00000000-0000-4000-8000-000000000009","referenceNo":"LX261010K7M2Q9XA4C","recipientType":"other_bank",
         "occurredAt":"2026-10-10T12:42:00.123456Z","amount":"75000.00","fee":"0.00","memo":null,"from":\(party),"to":\(party),
         "slipQr":"0046","bill":null}
        """

        static let inquiryJSON = """
        {"inquiryId":"00000000-0000-4000-8000-000000000010","challenge":"abc","expiresAt":"2026-10-10T12:47:00.5Z",
         "recipientType":"other_bank","amount":"75000.50","fee":"0.00","memo":null,"from":\(party),"to":\(party),
         "requiresBiometric":true,"bill":null}
        """
    }
}

@MainActor
struct MockEnvironmentTests {
    @Test func paymentsShowUpOnTheMockDashboard() async throws {
        let environment = AppEnvironment.makeDefault(arguments: [])
        let session = environment.makeSessionManager()
        let payments = environment.makePaymentRepository(session: session)
        let bank = environment.makeBankRepository(session: session)
        let inquiry = try await payments.transferInquiry(
            from: MockBankData.primaryAccountID, to: .promptPay(proxy: "0812345678"), amount: 10, memo: nil
        )
        let slip = try await payments.confirmTransfer(
            inquiryID: inquiry.id, authorization: PaymentAuthorization(method: .pin, signature: Data(), pin: "1"),
            idempotencyKey: UUID().uuidString, saveAsFavorite: false
        )
        let dashboard = try await bank.fetchDashboard()
        #expect(dashboard.recentTransactions.first?.id == slip.transactionID)
    }
}
