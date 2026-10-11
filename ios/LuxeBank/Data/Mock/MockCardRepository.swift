import Foundation

/// In-memory cards with the server's rules: Face ID to reveal details, PIN to report a card lost,
/// daily limit up to the approved maximum, and a replacement card that keeps its history.
@MainActor
final class MockCardRepository: CardRepository {
    var shouldFail = false
    var delay: Duration = .milliseconds(200)
    private var store: [BankCard]
    private var history: [UUID: [Transaction]] = [:]
    private var issued = 0

    static let creditID = UUID(uuidString: "CA4D0000-0000-4000-8000-000000008821") ?? UUID()
    static let debitID = UUID(uuidString: "CA4D0000-0000-4000-8000-000000004289") ?? UUID()

    init(now: Date = Date(), calendar: Calendar = .current) {
        let due = calendar.date(byAdding: .month, value: 1, to: now).flatMap {
            calendar.date(bySetting: .day, value: 2, of: $0)
        }
        store = [
            BankCard(
                id: Self.creditID, kind: .credit, productName: "Titanium Reserve", last4: "8821", expiry: "08/30", status: .active,
                channels: CardChannels(online: true, overseas: false, contactless: true, atm: true),
                dailyLimit: 50_000, maxDailyLimit: 200_000, rewardPoints: 12_800, travelInsurance: true,
                credit: CreditSummary(limit: 500_000, used: 86_420, available: 413_580, minimumPayment: 8_642, dueDate: due),
                linkedAccount: nil, linkedBalance: nil
            ),
            BankCard(
                id: Self.debitID, kind: .debit, productName: "LuxeBank Debit Platinum", last4: "4289", expiry: "03/29", status: .active,
                channels: CardChannels(online: true, overseas: false, contactless: true, atm: true),
                dailyLimit: 50_000, maxDailyLimit: 200_000, rewardPoints: 0, travelInsurance: false, credit: nil,
                linkedAccount: MockBankData.primaryAccount().maskedNumber, linkedBalance: MockBankData.primaryAccount().balance
            ),
        ]
        struct Purchase {
            let merchant: String
            let monogram: String?
            let category: TransactionCategory
            let amount: Decimal
        }
        let purchases = [
            Purchase(merchant: "Sarnies Bangkok", monogram: "SB", category: .food, amount: 580),
            Purchase(merchant: "Central Chidlom", monogram: "CC", category: .shopping, amount: 24_500),
            Purchase(merchant: "Thai Airways", monogram: "TG", category: .travel, amount: 38_900),
            Purchase(merchant: "Gourmet Market", monogram: "GM", category: .food, amount: 4_120),
            Purchase(merchant: "Agoda", monogram: "AG", category: .travel, amount: 16_400),
            Purchase(merchant: "Apple Store", monogram: nil, category: .shopping, amount: 1_920),
        ]
        history[Self.creditID] = purchases.enumerated().map { index, item in
            Transaction(
                id: UUID(), merchant: item.merchant, monogram: item.monogram, category: item.category,
                date: calendar.date(byAdding: .day, value: -(index * 4 + 1), to: now) ?? now, amount: -item.amount, channel: .card
            )
        }
        history[Self.debitID] = MockBankData.transactions(now: now, calendar: calendar).filter { $0.channel == .card && !$0.isIncome }
    }

    func cards() async throws -> [BankCard] {
        try await pause()
        return store.filter { $0.status == .active || $0.status == .frozen }
    }

    func card(id: UUID) async throws -> BankCard {
        try await pause()
        return try find(id)
    }

    func transactions(cardID: UUID, cursor: String?) async throws -> TransactionPage {
        try await pause()
        _ = try find(cardID)
        return TransactionPage(items: history[cardID] ?? [], nextCursor: nil, totals: nil)
    }

    func setFrozen(cardID: UUID, frozen: Bool) async throws -> BankCard {
        try await pause()
        return try update(cardID) { $0.status = frozen ? .frozen : .active }
    }

    func updateControls(cardID: UUID, change: CardControlsChange) async throws -> BankCard {
        try await pause()
        let card = try find(cardID)
        if let limit = change.dailyLimit, limit <= 0 || limit > card.maxDailyLimit { throw server("VALIDATION_FAILED") }
        return try update(cardID) { card in
            if let channels = change.channels { card.channels = channels }
            if let limit = change.dailyLimit { card.dailyLimit = limit }
        }
    }

    func challenge() async throws -> String {
        try await pause()
        return UUID().uuidString
    }

    func reportLost(cardID: UUID, challenge: String, authorization: PaymentAuthorization) async throws -> BankCard {
        try await pause()
        guard authorization.method == .pin, authorization.pin?.count == 6 else { throw server("PIN_INVALID") }
        let old = try find(cardID)
        issued += 1
        let replacement = BankCard(
            id: UUID(), kind: old.kind, productName: old.productName, last4: String(format: "%04d", 7_300 + issued), expiry: "10/31",
            status: .active, channels: old.channels, dailyLimit: old.dailyLimit, maxDailyLimit: old.maxDailyLimit,
            rewardPoints: old.rewardPoints, travelInsurance: old.travelInsurance, credit: old.credit,
            linkedAccount: old.linkedAccount, linkedBalance: old.linkedBalance
        )
        _ = try update(cardID) { $0.status = .lost }
        store.append(replacement)
        history[replacement.id] = history[cardID]
        return replacement
    }

    func reveal(cardID: UUID, challenge: String, authorization: PaymentAuthorization) async throws -> CardSecrets {
        try await pause()
        guard authorization.method == .biometric else { throw server("STEP_UP_REQUIRED") }
        let card = try find(cardID)
        let prefix = card.kind == .credit ? "552133" : "453201"
        return CardSecrets(pan: prefix + "017522" + card.last4, cvv: "418", expiry: card.expiry, visibleForSeconds: 30)
    }

    private func find(_ id: UUID) throws -> BankCard {
        guard let card = store.first(where: { $0.id == id && $0.status != .lost && $0.status != .closed }) else { throw server("NOT_FOUND") }
        return card
    }

    private func update(_ id: UUID, _ change: (inout BankCard) -> Void) throws -> BankCard {
        guard let index = store.firstIndex(where: { $0.id == id }) else { throw server("NOT_FOUND") }
        change(&store[index])
        return store[index]
    }

    private func server(_ code: String) -> APIError {
        APIError.server(code: code, message: code, remainingAttempts: nil)
    }

    private func pause() async throws {
        if shouldFail { throw RepositoryError.unavailable }
        if delay > .zero { try await Task.sleep(for: delay) }
    }
}
