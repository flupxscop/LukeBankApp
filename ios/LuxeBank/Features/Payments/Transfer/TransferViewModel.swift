import Foundation
import Observation

/// Values a transfer starts with, e.g. from a scanned PromptPay QR or a saved payee.
struct TransferPrefill: Equatable, Hashable {
    var kind: RecipientKind = .otherBank
    var proxy: String?
    var payeeID: UUID?
    var amount: Decimal?
}

/// S08 recipient → S09 amount → inquiry (TRF-01…06, TRF-08, TRF-11).
@MainActor
@Observable
final class TransferViewModel {
    enum Step: Hashable {
        case amount
        case confirm(PaymentInquiry)
        case slip(PaymentSlip)
    }

    var path: [Step] = []
    var kind: RecipientKind
    var accountNumber = ""
    var proxy = ""
    var selectedBank: Bank?
    var ownTarget: Account?
    var amountText = ""
    var memo = ""

    private(set) var accounts: [Account] = []
    private(set) var fromAccount: Account?
    private(set) var banks: [Bank] = []
    private(set) var payees: [Payee] = []
    private(set) var limits: TransferLimits?
    private(set) var selectedPayee: Payee?
    private(set) var isLoading = false
    private(set) var error: LocalizedStringResource?

    let repository: PaymentRepository

    init(repository: PaymentRepository, prefill: TransferPrefill? = nil) {
        self.repository = repository
        kind = prefill?.kind ?? .otherBank
        proxy = prefill?.proxy ?? ""
        if let amount = prefill?.amount { amountText = MoneyString.string(amount).replacingOccurrences(of: ".00", with: "") }
        pendingPayeeID = prefill?.payeeID
    }

    private var pendingPayeeID: UUID?

    func load() async {
        do {
            async let accounts = repository.accounts()
            async let banks = repository.banks()
            async let payees = repository.payees()
            self.accounts = try await accounts
            self.banks = try await banks
            self.payees = try await payees
            fromAccount = fromAccount ?? self.accounts.first
            selectedBank = selectedBank ?? self.banks.first
            ownTarget = ownTarget ?? otherOwnAccounts.first
            if let from = fromAccount { limits = try? await repository.limits(accountID: from.id) }
            if let id = pendingPayeeID, let payee = self.payees.first(where: { $0.id == id }) {
                pendingPayeeID = nil
                choose(payee)
            } else if !proxy.isEmpty, kind == .promptPay, path.isEmpty {
                path = [.amount]
            }
        } catch {
            self.error = PaymentErrors.message(for: error)
        }
    }

    func selectFrom(_ account: Account) async {
        fromAccount = account
        if ownTarget?.id == account.id { ownTarget = otherOwnAccounts.first }
        limits = try? await repository.limits(accountID: account.id)
    }

    var otherOwnAccounts: [Account] { accounts.filter { $0.id != fromAccount?.id } }

    // MARK: Recipient (S08)

    var recipient: TransferRecipient? {
        if let selectedPayee { return .payee(id: selectedPayee.id) }
        switch kind {
        case .own: return ownTarget.map { .own(accountID: $0.id) }
        case .luxeBank: return accountNumber.count == 10 ? .luxeBank(accountNumber: accountNumber) : nil
        case .otherBank:
            guard let selectedBank, (10...12).contains(accountNumber.count) else { return nil }
            return .otherBank(bankCode: selectedBank.code, accountNumber: accountNumber)
        case .promptPay: return PaymentRules.isValidProxy(proxy) ? .promptPay(proxy: proxy.filter(\.isNumber)) : nil
        case .bill: return nil
        }
    }

    var canContinue: Bool { recipient != nil && fromAccount != nil }

    /// Header chip on the amount screen, e.g. "กสิกรไทย · 123-4-56789-0".
    var recipientSummary: String {
        if let selectedPayee {
            return [selectedPayee.displayName, selectedPayee.bankName].compactMap { $0 }.joined(separator: " · ")
        }
        switch kind {
        case .own: return ownTarget.map { "\($0.name) · \($0.maskedNumber.suffix(4))" } ?? ""
        case .luxeBank: return "LuxeBank · " + AccountNumberFormat.format(accountNumber)
        case .otherBank: return "\(selectedBank?.name ?? "") · " + AccountNumberFormat.format(accountNumber)
        case .promptPay: return proxy
        case .bill: return ""
        }
    }

    func setKind(_ newKind: RecipientKind) {
        kind = newKind
        selectedPayee = nil
        error = nil
    }

    func choose(_ payee: Payee) {
        selectedPayee = payee
        error = nil
        path = [.amount]
    }

    func continueToAmount() {
        guard canContinue else { return }
        selectedPayee = nil
        error = nil
        path.append(.amount)
    }

    func removePayee(_ payee: Payee) async {
        do {
            try await repository.deletePayee(id: payee.id)
            payees.removeAll { $0.id == payee.id }
        } catch {
            self.error = PaymentErrors.message(for: error)
        }
    }

    // MARK: Amount (S09)

    var amount: Decimal { PaymentRules.amount(amountText) }

    func key(_ character: Character) {
        amountText = PaymentRules.append(character, to: amountText)
        error = nil
    }

    func deleteKey() {
        guard !amountText.isEmpty else { return }
        amountText.removeLast()
    }

    func add(_ value: Decimal) {
        let next = amount + value
        guard next <= PaymentRules.maxAmount else { return }
        amountText = MoneyString.string(next).replacingOccurrences(of: ".00", with: "")
    }

    var needsFaceID: Bool { amount >= PaymentRules.stepUpAmount }

    /// Checked on the device first; the server checks again (TRF-08).
    var amountProblem: LocalizedStringResource? {
        guard amount > 0 else { return nil }
        if let balance = fromAccount?.balance, amount > balance { return "error.insufficientFunds" }
        if kind != .own || selectedPayee != nil, let remaining = limits?.remaining, amount > remaining { return "error.dailyLimit" }
        return nil
    }

    var canReview: Bool { amount > 0 && amountProblem == nil && !isLoading }

    func review() async {
        guard canReview, let fromAccount, let recipient else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let inquiry = try await repository.transferInquiry(from: fromAccount.id, to: recipient, amount: amount, memo: memo.nilIfBlank)
            path.append(.confirm(inquiry))
        } catch {
            self.error = PaymentErrors.message(for: error)
        }
    }

    func confirmInquiry(_ inquiry: PaymentInquiry, authorization: PaymentAuthorization, key: String, save: Bool) async throws -> PaymentSlip {
        try await repository.confirmTransfer(inquiryID: inquiry.id, authorization: authorization, idempotencyKey: key, saveAsFavorite: save)
    }

    func showSlip(_ slip: PaymentSlip) {
        path.append(.slip(slip))
    }

    /// After an expired confirmation: back to the amount screen to price it again.
    func restartFromAmount() {
        path = [.amount]
    }
}

/// "1234567890" → "123-4-56789-0", the Thai bank account display format.
enum AccountNumberFormat {
    static func format(_ digits: String) -> String {
        let value = Array(digits.filter(\.isNumber).prefix(12))
        guard value.count == 10 else { return String(value) }
        return "\(String(value[0..<3]))-\(value[3])-\(String(value[4..<9]))-\(value[9])"
    }
}
