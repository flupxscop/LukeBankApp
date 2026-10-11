import Foundation
import Observation

/// What the pay screen starts from: a biller, a saved bill, or a scanned bill QR.
struct BillTarget: Equatable, Hashable {
    var biller: Biller?
    var saved: SavedBill?
    var billerCode: String?
    var ref1: String = ""
    var ref2: String = ""
    var amount: Decimal?
    /// From a dynamic QR: the biller fixed the amount.
    var amountLocked = false
}

/// S13 + S14 — choose a biller or saved bill, check the reference, pay (BILL-01…05).
@MainActor
@Observable
final class BillsViewModel {
    enum Step: Hashable {
        case pay(BillTarget)
        case confirm(PaymentInquiry)
        case slip(PaymentSlip)
    }

    var path: [Step] = []
    var search = ""
    var category: BillerCategory?
    private(set) var billers: [Biller] = []
    private(set) var saved: [SavedBill] = []
    private(set) var accounts: [Account] = []
    private(set) var state: State = .loading

    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    let repository: PaymentRepository

    init(repository: PaymentRepository, category: BillerCategory? = nil, target: BillTarget? = nil) {
        self.repository = repository
        self.category = category
        if let target { path = [.pay(target)] }
    }

    func load() async {
        do {
            async let billers = repository.billers(category: nil)
            async let saved = repository.savedBills()
            async let accounts = repository.accounts()
            self.billers = try await billers
            self.saved = try await saved
            self.accounts = try await accounts
            state = .loaded
        } catch {
            state = .failed
        }
    }

    var filteredBillers: [Biller] {
        let text = search.trimmingCharacters(in: .whitespaces)
        return billers.filter { biller in
            (category == nil || biller.category == category) && (text.isEmpty || biller.name.localizedCaseInsensitiveContains(text))
        }
    }

    func pay(_ biller: Biller) { path.append(.pay(BillTarget(biller: biller))) }
    func pay(_ saved: SavedBill) { path.append(.pay(BillTarget(biller: saved.biller, saved: saved))) }

    func biller(code: String?) -> Biller? { billers.first { $0.code == code } }

    func showConfirm(_ inquiry: PaymentInquiry) { path.append(.confirm(inquiry)) }
    func showSlip(_ slip: PaymentSlip) { path.append(.slip(slip)) }

    func backToPay() {
        if let index = path.lastIndex(where: { if case .pay = $0 { true } else { false } }) {
            path = Array(path.prefix(index + 1))
        }
    }

    func confirmInquiry(_ inquiry: PaymentInquiry, authorization: PaymentAuthorization, key: String, save: Bool) async throws -> PaymentSlip {
        try await repository.payBill(inquiryID: inquiry.id, authorization: authorization, idempotencyKey: key, saveBill: save)
    }
}

/// S14 — references, amount due and the pay button.
@MainActor
@Observable
final class BillPayViewModel {
    var ref1: String
    var ref2: String
    var amountText = ""
    private(set) var inquiry: PaymentInquiry?
    private(set) var isLoading = false
    private(set) var error: LocalizedStringResource?
    private(set) var fromAccount: Account?
    private(set) var accounts: [Account]

    let target: BillTarget
    let biller: Biller?
    private let repository: PaymentRepository

    init(target: BillTarget, biller: Biller?, accounts: [Account], repository: PaymentRepository) {
        self.target = target
        self.biller = biller ?? target.biller ?? target.saved?.biller
        self.repository = repository
        ref1 = target.saved == nil ? target.ref1 : ""
        ref2 = target.ref2
        self.accounts = accounts
        fromAccount = accounts.first
        if let amount = target.amount { amountText = MoneyString.string(amount) }
    }

    var isTopUp: Bool { biller?.topUp ?? false }
    /// Top-ups take any amount; cards and insurance accept less than is due; a QR may fix the amount.
    var showsAmount: Bool { isTopUp || (biller?.partialPayment ?? false) || target.amountLocked }
    var isAmountLocked: Bool { target.amountLocked && target.amount != nil }
    var isSaved: Bool { target.saved != nil }
    var title: String { target.saved?.displayName ?? biller?.name ?? "" }

    var amount: Decimal? {
        let value = PaymentRules.amount(amountText)
        return value > 0 ? value : nil
    }

    var canCheck: Bool {
        guard !isLoading, fromAccount != nil else { return false }
        if isTopUp, amount == nil { return false }
        return isSaved || (!ref1.isEmpty && ref1.allSatisfy(\.isNumber))
    }

    func editedReference() {
        inquiry = nil
        error = nil
    }

    func setFromAccount(_ account: Account) {
        fromAccount = account
        inquiry = nil
    }

    /// Opened straight from a QR scan, before the biller list finished loading.
    func prepare() async {
        guard accounts.isEmpty else { return }
        accounts = (try? await repository.accounts()) ?? []
        fromAccount = fromAccount ?? accounts.first
    }

    /// Prices the bill (`POST /bills/inquiry`); for top-ups this is the last step before confirming.
    func check() async -> PaymentInquiry? {
        guard canCheck, let fromAccount else { return nil }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let request = BillRequest(
                billerCode: isSaved ? nil : biller?.code ?? target.billerCode,
                ref1: isSaved ? nil : ref1,
                ref2: isSaved ? nil : ref2.nilIfBlank,
                savedBillID: target.saved?.id,
                amount: amount
            )
            let priced = try await repository.billInquiry(from: fromAccount.id, request: request)
            inquiry = priced
            return priced
        } catch {
            self.error = PaymentErrors.message(for: error)
            return nil
        }
    }
}
