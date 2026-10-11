import Foundation
import Testing
@testable import LuxeBank

@MainActor
struct HistoryViewModelTests {
    private let now = Date()

    private func makeViewModel(repository: MockBankRepository? = nil) -> HistoryViewModel {
        HistoryViewModel(account: MockBankData.primaryAccount(), repository: repository ?? MockBankRepository(), calendar: .current, debounce: .zero)
    }

    @Test func loadsFirstPageWithTotalsGroupedByDay() async {
        let viewModel = makeViewModel(repository: MockBankRepository(now: { now }))

        await viewModel.reload()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.items.count == RemoteBankRepository.pageSize)
        #expect(viewModel.canLoadMore)
        #expect(viewModel.items == viewModel.items.sorted { $0.date > $1.date })
        #expect(viewModel.sections.flatMap(\.items) == viewModel.items)
        #expect(Set(viewModel.sections.map(\.day)).count == viewModel.sections.count)
        let totals = try? #require(viewModel.totals)
        #expect((totals?.moneyIn ?? 0) > 0)
        #expect((totals?.moneyOut ?? 0) > 0)
    }

    @Test func pagesUntilTheEndWithoutDuplicates() async {
        let viewModel = makeViewModel()
        await viewModel.reload()

        while viewModel.canLoadMore {
            guard let last = viewModel.items.last else { break }
            await viewModel.loadMoreIfNeeded(after: last)
        }

        #expect(Set(viewModel.items.map(\.id)).count == viewModel.items.count)
        #expect(viewModel.items.count > RemoteBankRepository.pageSize)
    }

    @Test func loadMoreOnlyTriggersOnTheLastRow() async {
        let viewModel = makeViewModel()
        await viewModel.reload()
        let count = viewModel.items.count

        if let first = viewModel.items.first { await viewModel.loadMoreIfNeeded(after: first) }

        #expect(viewModel.items.count == count)
    }

    @Test func filtersByDirectionCategoryAndText() async {
        let viewModel = makeViewModel()

        viewModel.query.direction = .incoming
        await viewModel.reload()
        #expect(!viewModel.items.isEmpty)
        let allIncoming = viewModel.items.allSatisfy(\.isIncome)
        #expect(allIncoming)

        viewModel.query = TransactionQuery(category: .housing)
        await viewModel.reload()
        #expect(viewModel.items.map(\.merchant) == ["คอนโด เดอะ ริเวอร์"])

        viewModel.query = TransactionQuery(text: "ตุลาคม")
        await viewModel.reload()
        #expect(viewModel.items.map(\.merchant) == ["คอนโด เดอะ ริเวอร์"])
    }

    @Test func emptyResultOffersToClearFilters() async {
        let viewModel = makeViewModel()
        viewModel.query.text = "no such merchant"

        await viewModel.reload()

        #expect(viewModel.state == .empty)
        #expect(viewModel.hasActiveFilters)
        viewModel.clearFilters()
        #expect(!viewModel.hasActiveFilters)
    }

    @Test func failureShowsErrorState() async {
        let viewModel = makeViewModel(repository: MockBankRepository(shouldFail: true))

        await viewModel.reload()

        #expect(viewModel.state == .failed)
        #expect(viewModel.items.isEmpty)
    }

    @Test func replaceUpdatesAnEditedRow() async throws {
        let viewModel = makeViewModel()
        await viewModel.reload()
        let original = try #require(viewModel.items.first)
        let edited = Transaction(
            id: original.id, merchant: original.merchant, monogram: original.monogram, category: .shopping,
            date: original.date, amount: original.amount, channel: original.channel, memo: "gift"
        )

        viewModel.replace(edited)

        #expect(viewModel.items.first == edited)
    }
}

@MainActor
struct TransactionDetailViewModelTests {
    private let rentID = MockBankData.transactions()[1].id

    @Test func loadsDetailAndRecategorises() async throws {
        let repository = MockBankRepository()
        var changed: Transaction?
        let viewModel = TransactionDetailViewModel(transactionID: rentID, repository: repository) { changed = $0 }

        await viewModel.load()
        let detail = try #require(viewModel.detail)
        #expect(detail.transaction.category == .housing)
        #expect(detail.referenceNo.hasPrefix("LX"))
        #expect(viewModel.canChangeCategory)

        await viewModel.changeCategory(.bills)

        #expect(viewModel.detail?.transaction.category == .bills)
        #expect(changed?.category == .bills)
        let reloaded = try await repository.transaction(id: rentID)
        #expect(reloaded.transaction.category == .bills)
    }

    @Test func savesAndClearsMemo() async {
        let viewModel = TransactionDetailViewModel(transactionID: rentID, repository: MockBankRepository())
        await viewModel.load()

        await viewModel.saveMemo("  ค่าเช่า  ")
        #expect(viewModel.detail?.transaction.memo == "ค่าเช่า")

        await viewModel.saveMemo("")
        #expect(viewModel.detail?.transaction.memo == nil)
    }

    @Test func incomeCannotBeRecategorised() async throws {
        let income = try #require(MockBankData.transactions().first { $0.category == .investment })
        let viewModel = TransactionDetailViewModel(transactionID: income.id, repository: MockBankRepository())
        await viewModel.load()

        #expect(!viewModel.canChangeCategory)
        await viewModel.changeCategory(.food)
        #expect(viewModel.detail?.transaction.category == .investment)
    }

    @Test func failedSaveKeepsTheLoadedDetail() async {
        let repository = MockBankRepository()
        let viewModel = TransactionDetailViewModel(transactionID: rentID, repository: repository)
        await viewModel.load()

        repository.shouldFail = true
        await viewModel.changeCategory(.food)

        #expect(viewModel.saveFailed)
        #expect(viewModel.detail?.transaction.category == .housing)
    }

    @Test func unknownTransactionFails() async {
        let viewModel = TransactionDetailViewModel(transactionID: UUID(), repository: MockBankRepository())
        await viewModel.load()
        #expect(viewModel.state == .failed)
    }
}

@MainActor
final class StubTokens: AccessTokenProviding {
    var token = "access-1"
    private(set) var refreshes = 0

    func validAccessToken() async throws -> String { token }

    func refreshAccessToken() async throws -> String {
        refreshes += 1
        token = "access-\(refreshes + 1)"
        return token
    }
}

// Nested in the serialized APIClientTests suite: both use StubProtocol's shared static state.
extension APIClientTests {
@MainActor
struct RemoteBankRepositoryTests {
    private let tokens = StubTokens()

    private func repository(status: Int = 200, body: String) -> RemoteBankRepository {
        RemoteBankRepository(api: AuthorizedAPI(client: StubProtocol.client(status: status, body: body), tokens: tokens))
    }

    @Test func decodesDashboardMoneyAsExactDecimals() async throws {
        let summary = try await repository(body: Self.dashboardJSON).fetchDashboard()

        #expect(summary.customerFirstName == "Noknoi")
        #expect(summary.primaryAccount.balance == Decimal(string: "4825450.75"))
        #expect(summary.monthChangeRate == Decimal(string: "5.1"))
        #expect(summary.balanceHistory.map(\.balance) == [Decimal(string: "4800000.10"), Decimal(string: "4825450.75")])
        #expect(summary.spending.categories.map(\.kind) == [.lifestyle])
        #expect(summary.savingsGoal == nil)
        #expect(summary.recentTransactions.first?.amount == Decimal(string: "-580.00"))
        #expect(summary.recentTransactions.first?.category == .food)
        #expect(summary.recentTransactions.first?.channel == .promptpay)
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }

    @Test func rejectsMalformedMoney() async {
        let body = Self.dashboardJSON.replacingOccurrences(of: "\"4825450.75\"", with: "\"4,825,450.75\"")
        await #expect(throws: APIError.decoding) { try await repository(body: body).fetchDashboard() }
    }

    @Test func unknownCategoryReadsAsOther() async throws {
        let body = Self.dashboardJSON.replacingOccurrences(of: "\"food\"", with: "\"crypto\"")
        let summary = try await repository(body: body).fetchDashboard()
        #expect(summary.recentTransactions.first?.category == .other)
    }

    @Test func sendsHistoryFiltersAsQueryItems() async throws {
        let body = #"{"items":[],"nextCursor":null,"summary":{"moneyIn":"0.00","moneyOut":"12.50"}}"#
        let accountID = UUID()
        let query = TransactionQuery(direction: .outgoing, category: .food, periodDays: 7, text: "  Sarnies ")

        let page = try await repository(body: body).transactions(accountID: accountID, query: query, cursor: "abc")

        #expect(page.totals?.moneyOut == Decimal(string: "12.5"))
        let url = try #require(StubProtocol.lastRequest?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path.hasSuffix("/accounts/\(accountID.uuidString)/transactions"))
        #expect(values["direction"] == "out")
        #expect(values["category"] == "food")
        #expect(values["q"] == "Sarnies")
        #expect(values["cursor"] == "abc")
        #expect(values["limit"] == "20")
        #expect(values["from"]?.count == 10)
    }

    @Test func clearingTheMemoSendsAnExplicitFlag() async throws {
        let repository = repository(body: Self.detailJSON)

        let detail = try await repository.updateTransaction(id: UUID(), category: nil, memo: "   ")

        #expect(detail.referenceNo == "LX261010K7M2Q9XA4C")
        let request = try #require(StubProtocol.lastRequest)
        #expect(request.httpMethod == "PATCH")
        let json = try JSONSerialization.jsonObject(with: StubProtocol.body(of: request)) as? [String: Any]
        #expect(json?["clearMemo"] as? Bool == true)
        #expect(json?["memo"] == nil || json?["memo"] is NSNull)
    }

    @Test func refreshesTheTokenOnceAfterA401() async throws {
        let repository = repository(body: Self.detailJSON)
        StubProtocol.queue = [(401, #"{"error":{"code":"UNAUTHORIZED","message":"Authentication required"}}"#)]

        _ = try await repository.transaction(id: UUID())

        #expect(tokens.refreshes == 1)
        #expect(StubProtocol.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access-1", "Bearer access-2"])
    }

    static let dashboardJSON = """
    {"customerFirstName":"Noknoi",
     "primaryAccount":{"id":"6C1F4E0A-4289-4D7B-9C3E-1F2A3B4C4289","name":"Main","maskedNumber":"•••• 4289",
       "type":"current","primary":true,"balance":"4825450.75"},
     "accounts":[],
     "monthChange":"25450.65","monthChangeRate":"5.1",
     "balanceHistory":[{"date":"2026-10-09","balance":"4800000.10"},{"date":"2026-10-10","balance":"4825450.75"}],
     "cashbackThisMonth":"1200.00","cashbackTrend":["0.00","1200.00"],
     "spending":{"categories":[{"kind":"lifestyle","spent":"380.00","budget":"50000.00"},{"kind":"space","spent":"1.00","budget":"1.00"}]},
     "savingsGoal":null,
     "recentTransactions":[{"id":"00000000-0000-4000-8000-000000000001","accountId":"6C1F4E0A-4289-4D7B-9C3E-1F2A3B4C4289",
       "merchant":"Sarnies Bangkok","monogram":"SB","category":"food","channel":"promptpay",
       "occurredAt":"2026-10-10T12:10:00Z","amount":"-580.00","memo":null}]}
    """

    static let detailJSON = """
    {"transaction":{"id":"00000000-0000-4000-8000-000000000002","accountId":"6C1F4E0A-4289-4D7B-9C3E-1F2A3B4C4289",
       "merchant":"Condo","monogram":null,"category":"housing","channel":"promptpay",
       "occurredAt":"2026-10-09T02:30:00Z","amount":"-28500.00","memo":null},
     "referenceNo":"LX261010K7M2Q9XA4C","status":"posted",
     "account":{"id":"6C1F4E0A-4289-4D7B-9C3E-1F2A3B4C4289","name":"Main","maskedNumber":"•••• 4289"}}
    """
}
}

@MainActor
struct AccessTokenRefreshTests {
    let storage = InMemorySecureStorage()
    let keys = FakeKeyManager()
    let clock = Clock()
    let repository: MockAuthRepository = {
        let repository = MockAuthRepository()
        repository.delay = .zero
        return repository
    }()

    private func unlockedSession() async throws -> SessionManager {
        let session = SessionManager(repository: repository, storage: storage, keys: keys, now: { [clock] in clock.now })
        _ = try keys.createKey(.device)
        let auth = try await repository.registerDevice(registrationToken: "t", pin: "482193", deviceName: "iPhone", publicKey: Data())
        try await session.storeRegistration(auth)
        session.finishOnboarding()
        return session
    }

    @Test func reusesAFreshTokenAndRenewsAnExpiringOne() async throws {
        let session = try await unlockedSession()

        #expect(try await session.validAccessToken() == "mock-access")
        #expect(repository.refreshCount == 0)

        clock.advance(900 - 10)
        let renewed = try await session.validAccessToken()

        #expect(renewed == "mock-access-1")
        #expect(repository.refreshCount == 1)
        #expect(storage.string(for: "session.refreshToken") == "mock-refresh-1")
    }

    @Test func rejectedRefreshLocksTheApp() async throws {
        let session = try await unlockedSession()
        repository.refreshShouldFail = true

        await #expect(throws: APIError.unauthorized) { try await session.refreshAccessToken() }

        #expect(session.state == .locked)
        #expect(session.accessToken == nil)
    }

    @Test func lockedSessionHandsOutNoTokens() async throws {
        let session = try await unlockedSession()
        session.lock()
        await #expect(throws: APIError.unauthorized) { try await session.validAccessToken() }
    }
}
