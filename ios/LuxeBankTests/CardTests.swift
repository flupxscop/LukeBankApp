import Foundation
import Testing
@testable import LuxeBank

@MainActor
struct CardsViewModelTests {
    private func repository() -> MockCardRepository {
        let repository = MockCardRepository()
        repository.delay = .zero
        return repository
    }

    @Test func loadsCardsSelectsTheFirstAndItsPurchases() async throws {
        let viewModel = CardsViewModel(repository: repository())
        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.cards.count == 2)
        let credit = try #require(viewModel.selected?.credit)
        #expect(credit.available == credit.limit - credit.used)
        #expect(viewModel.recent.count == 5)

        await viewModel.select(MockCardRepository.debitID)
        #expect(viewModel.selected?.kind == .debit)
        #expect(viewModel.selected?.credit == nil)
    }

    @Test func freezeTogglesTheSelectedCard() async {
        let viewModel = CardsViewModel(repository: repository())
        await viewModel.load()

        await viewModel.toggleFreeze()
        #expect(viewModel.selected?.isFrozen == true)
        await viewModel.toggleFreeze()
        #expect(viewModel.selected?.isFrozen == false)
    }

    @Test func replacedCardsStayReachableByTheirOldId() async throws {
        let viewModel = CardsViewModel(repository: repository())
        await viewModel.load()
        let old = try #require(viewModel.selected)
        let replacement = BankCard(
            id: UUID(), kind: old.kind, productName: old.productName, last4: "7301", expiry: "10/31", status: .active,
            channels: old.channels, dailyLimit: old.dailyLimit, maxDailyLimit: old.maxDailyLimit, rewardPoints: old.rewardPoints,
            travelInsurance: old.travelInsurance, credit: old.credit, linkedAccount: nil, linkedBalance: nil
        )

        viewModel.replace(replacement, replacing: old.id)

        #expect(viewModel.card(id: old.id)?.id == replacement.id)
        #expect(viewModel.selected?.last4 == "7301")
    }

    @Test func failureShowsTheErrorState() async {
        let repository = repository()
        repository.shouldFail = true
        let viewModel = CardsViewModel(repository: repository)
        await viewModel.load()
        #expect(viewModel.state == .failed)
    }
}

@MainActor
struct CardDetailViewModelTests {
    private let repository: MockCardRepository = {
        let repository = MockCardRepository()
        repository.delay = .zero
        return repository
    }()

    private func makeViewModel(
        authorizer: FakeAuthorizer? = nil, onChange: @escaping (BankCard, UUID?) -> Void = { _, _ in }
    ) async throws -> CardDetailViewModel {
        let card = try await repository.card(id: MockCardRepository.creditID)
        return CardDetailViewModel(
            card: card, repository: repository, authorizer: authorizer ?? FakeAuthorizer(), sleep: { _ in await Task.yield() }, onChange: onChange
        )
    }

    @Test func revealNeedsFaceIdThenHidesItself() async throws {
        let authorizer = FakeAuthorizer()
        let viewModel = try await makeViewModel(authorizer: authorizer)

        await viewModel.reveal()
        #expect(viewModel.secrets == nil)
        #expect(viewModel.error == "cards.revealNeedsFaceID")

        authorizer.isBiometricEnabled = true
        await viewModel.reveal()
        let secrets = try #require(viewModel.secrets)
        #expect(authorizer.methods == [.biometric])
        #expect(secrets.pan.hasSuffix("8821"))
        #expect(secrets.formattedPAN.split(separator: " ").count == 4)

        for _ in 0..<200 where viewModel.secrets != nil { await Task.yield() }
        #expect(viewModel.secrets == nil)
        #expect(viewModel.secondsLeft == 0)
    }

    @Test func hideClearsDetailsAtOnce() async throws {
        let authorizer = FakeAuthorizer()
        authorizer.isBiometricEnabled = true
        let card = try await repository.card(id: MockCardRepository.creditID)
        let viewModel = CardDetailViewModel(
            card: card, repository: repository, authorizer: authorizer, sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        await viewModel.reveal()
        #expect(viewModel.secrets != nil)
        viewModel.hide()
        #expect(viewModel.secrets == nil)
    }

    @Test func channelsAndDailyLimitStayWithinTheApprovedMaximum() async throws {
        var changes = 0
        let viewModel = try await makeViewModel { _, _ in changes += 1 }

        await viewModel.setChannel(\.overseas, true)
        #expect(viewModel.card.channels.overseas)

        viewModel.dailyLimitDraft = 999_999
        await viewModel.commitDailyLimit()
        #expect(viewModel.card.dailyLimit == viewModel.card.maxDailyLimit)

        viewModel.dailyLimitDraft = 72_600
        await viewModel.commitDailyLimit()
        #expect(viewModel.card.dailyLimit == 75_000)
        #expect(changes == 3)
    }

    @Test func reportingLostNeedsThePinAndReturnsAReplacement() async throws {
        var replaced: (BankCard, UUID?)?
        let viewModel = try await makeViewModel { replaced = ($0, $1) }
        let old = viewModel.card

        viewModel.startReportLost()
        #expect(viewModel.isEnteringPin)
        for digit in [4, 8, 2, 1, 9, 3] { await viewModel.appendPinDigit(digit) }

        #expect(!viewModel.isEnteringPin)
        #expect(viewModel.card.id != old.id)
        #expect(viewModel.card.last4 != old.last4)
        #expect(viewModel.card.rewardPoints == old.rewardPoints)
        #expect(replaced?.1 == old.id)
        await #expect(throws: APIError.self) { _ = try await repository.card(id: old.id) }
    }
}

extension APIClientTests {
    @MainActor
    struct RemoteCardRepositoryTests {
        private let tokens = StubTokens()

        @Test func decodesCardsAndSendsTheStepUpProof() async throws {
            let client = StubProtocol.client(status: 200, body: Self.cardJSON)
            let repository = RemoteCardRepository(api: AuthorizedAPI(client: client, tokens: tokens))

            let card = try await repository.card(id: UUID())
            #expect(card.kind == .credit)
            #expect(card.credit?.used == Decimal(string: "86420.00"))
            #expect(card.channels.overseas == false)

            StubProtocol.body = Data(Self.cardJSON.utf8)
            let auth = PaymentAuthorization(method: .pin, signature: Data([9]), pin: "482193")
            _ = try await repository.reportLost(cardID: UUID(), challenge: "chal", authorization: auth)
            let request = try #require(StubProtocol.lastRequest)
            #expect(request.url?.path.hasSuffix("/report-lost") == true)
            let json = try JSONSerialization.jsonObject(with: StubProtocol.body(of: request)) as? [String: Any]
            #expect(json?["challenge"] as? String == "chal")
            #expect(json?["method"] as? String == "PIN")
            #expect(json?["signature"] as? String == Data([9]).base64EncodedString())
        }

        static let cardJSON = """
        {"id":"CA4D0000-0000-4000-8000-000000008821","type":"credit","productName":"Titanium Reserve","last4":"8821","expiry":"08/30",
         "status":"active","channels":{"online":true,"overseas":false,"contactless":true,"atm":true},"dailyLimit":"50000.00",
         "maxDailyLimit":"200000.00","rewardPoints":12800,"travelInsurance":true,
         "credit":{"limit":"500000.00","used":"86420.00","available":"413580.00","minimumPayment":"8642.00","dueDate":"2026-11-02"},
         "linkedAccount":null,"linkedBalance":null}
        """
    }
}
