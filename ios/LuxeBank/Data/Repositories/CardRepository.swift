import Foundation

/// Cards (CARD-01…09): `GET /cards`, controls, freeze, report lost and the Face ID-gated reveal.
/// Sensitive actions sign a single-use challenge from `POST /challenges` (step-up proof).
protocol CardRepository {
    func cards() async throws -> [BankCard]
    func card(id: UUID) async throws -> BankCard
    func transactions(cardID: UUID, cursor: String?) async throws -> TransactionPage
    func setFrozen(cardID: UUID, frozen: Bool) async throws -> BankCard
    func updateControls(cardID: UUID, change: CardControlsChange) async throws -> BankCard
    func challenge() async throws -> String
    /// Blocks the card and returns its replacement.
    func reportLost(cardID: UUID, challenge: String, authorization: PaymentAuthorization) async throws -> BankCard
    func reveal(cardID: UUID, challenge: String, authorization: PaymentAuthorization) async throws -> CardSecrets
}

final class RemoteCardRepository: CardRepository {
    private let api: AuthorizedAPI

    init(api: AuthorizedAPI) {
        self.api = api
    }

    func cards() async throws -> [BankCard] {
        let items: [CardDTO.Card] = try await api.send(APIRequest(method: "GET", path: "cards"))
        return try items.map { try $0.domain() }
    }

    func card(id: UUID) async throws -> BankCard {
        let dto: CardDTO.Card = try await api.send(APIRequest(method: "GET", path: "cards/\(id.uuidString)"))
        return try dto.domain()
    }

    func transactions(cardID: UUID, cursor: String?) async throws -> TransactionPage {
        var query = [URLQueryItem(name: "limit", value: "20")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let page: CardDTO.Page = try await api.send(APIRequest(method: "GET", path: "cards/\(cardID.uuidString)/transactions", query: query))
        return try page.domain()
    }

    func setFrozen(cardID: UUID, frozen: Bool) async throws -> BankCard {
        let dto: CardDTO.Card = try await api.send(
            APIRequest(method: "POST", path: "cards/\(cardID.uuidString)/\(frozen ? "freeze" : "unfreeze")")
        )
        return try dto.domain()
    }

    func updateControls(cardID: UUID, change: CardControlsChange) async throws -> BankCard {
        struct Body: Encodable {
            let online: Bool?
            let overseas: Bool?
            let contactless: Bool?
            let atm: Bool?
            let dailyLimit: String?
        }
        let body = Body(
            online: change.channels?.online, overseas: change.channels?.overseas, contactless: change.channels?.contactless,
            atm: change.channels?.atm, dailyLimit: change.dailyLimit.map(MoneyString.string)
        )
        let dto: CardDTO.Card = try await api.send(APIRequest(method: "PATCH", path: "cards/\(cardID.uuidString)/controls", body: body))
        return try dto.domain()
    }

    func challenge() async throws -> String {
        struct Response: Decodable { let challenge: String }
        let response: Response = try await api.send(APIRequest(method: "POST", path: "challenges"))
        return response.challenge
    }

    func reportLost(cardID: UUID, challenge: String, authorization: PaymentAuthorization) async throws -> BankCard {
        let dto: CardDTO.Card = try await api.send(
            APIRequest(method: "POST", path: "cards/\(cardID.uuidString)/report-lost", body: CardDTO.Proof(challenge, authorization))
        )
        return try dto.domain()
    }

    func reveal(cardID: UUID, challenge: String, authorization: PaymentAuthorization) async throws -> CardSecrets {
        let dto: CardDTO.Sensitive = try await api.send(
            APIRequest(method: "POST", path: "cards/\(cardID.uuidString)/sensitive", body: CardDTO.Proof(challenge, authorization))
        )
        return CardSecrets(pan: dto.pan, cvv: dto.cvv, expiry: dto.expiry, visibleForSeconds: dto.visibleForSeconds)
    }
}

// MARK: - Wire format

enum CardDTO {
    struct Proof: Encodable {
        let challenge: String
        let method: LoginMethod
        let signature: String
        let pin: String?

        init(_ challenge: String, _ authorization: PaymentAuthorization) {
            self.challenge = challenge
            method = authorization.method
            signature = authorization.signature.base64EncodedString()
            pin = authorization.pin
        }
    }

    struct Channels: Decodable {
        let online: Bool
        let overseas: Bool
        let contactless: Bool
        let atm: Bool
    }

    struct Credit: Decodable {
        let limit: String
        let used: String
        let available: String
        let minimumPayment: String
        let dueDate: String?
    }

    struct Card: Decodable {
        let id: UUID
        let type: String
        let productName: String
        let last4: String
        let expiry: String
        let status: String
        let channels: Channels
        let dailyLimit: String
        let maxDailyLimit: String
        let rewardPoints: Int
        let travelInsurance: Bool
        let credit: Credit?
        let linkedAccount: String?
        let linkedBalance: String?

        func domain() throws -> BankCard {
            BankCard(
                id: id,
                kind: CardKind(rawValue: type) ?? .debit,
                productName: productName,
                last4: last4,
                expiry: expiry,
                status: CardStatus(rawValue: status) ?? .closed,
                channels: CardChannels(online: channels.online, overseas: channels.overseas, contactless: channels.contactless, atm: channels.atm),
                dailyLimit: try MoneyString.decimal(dailyLimit),
                maxDailyLimit: try MoneyString.decimal(maxDailyLimit),
                rewardPoints: rewardPoints,
                travelInsurance: travelInsurance,
                credit: try credit.map {
                    CreditSummary(
                        limit: try MoneyString.decimal($0.limit), used: try MoneyString.decimal($0.used),
                        available: try MoneyString.decimal($0.available), minimumPayment: try MoneyString.decimal($0.minimumPayment),
                        dueDate: $0.dueDate.flatMap(DayFormat.date)
                    )
                },
                linkedAccount: linkedAccount,
                linkedBalance: try linkedBalance.map(MoneyString.decimal)
            )
        }
    }

    struct PageItem: Decodable {
        let id: UUID
        let merchant: String
        let monogram: String?
        let category: String
        let channel: String
        let occurredAt: String
        let amount: String
        let memo: String?
    }

    struct Page: Decodable {
        let items: [PageItem]
        let nextCursor: String?

        func domain() throws -> TransactionPage {
            TransactionPage(
                items: try items.map {
                    Transaction(
                        id: $0.id, merchant: $0.merchant, monogram: $0.monogram, category: TransactionCategory(code: $0.category),
                        date: try Timestamp.date($0.occurredAt), amount: try MoneyString.decimal($0.amount),
                        channel: TransactionChannel(rawValue: $0.channel) ?? .card, memo: $0.memo
                    )
                },
                nextCursor: nextCursor,
                totals: nil
            )
        }
    }

    struct Sensitive: Decodable {
        let pan: String
        let cvv: String
        let expiry: String
        let visibleForSeconds: Int
    }
}
