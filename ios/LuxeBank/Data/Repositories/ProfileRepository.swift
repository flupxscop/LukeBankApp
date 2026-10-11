import Foundation

/// Profile, preferences, devices and the notification inbox (PROF-01…07, NOTI-01…03).
protocol ProfileRepository {
    func profile() async throws -> BankProfile
    func updatePreferences(_ change: PreferencesChange) async throws -> NotificationPreferences
    func devices() async throws -> [RegisteredDevice]
    /// The APNs token of this phone; the server pushes to it (a log-only stub in the simulation).
    func registerPushToken(_ token: String) async throws
    func notifications(cursor: String?) async throws -> InboxPage
    func markRead(id: UUID) async throws
    func markAllRead() async throws
}

final class RemoteProfileRepository: ProfileRepository {
    private let api: AuthorizedAPI

    init(api: AuthorizedAPI) {
        self.api = api
    }

    func profile() async throws -> BankProfile {
        let dto: ProfileDTO.Profile = try await api.send(APIRequest(method: "GET", path: "me"))
        return try dto.domain()
    }

    func updatePreferences(_ change: PreferencesChange) async throws -> NotificationPreferences {
        struct Body: Encodable {
            let language: String?
            let notifyTransactions: Bool?
            let notifyMarketing: Bool?
        }
        let body = Body(language: change.language?.rawValue, notifyTransactions: change.transactions, notifyMarketing: change.marketing)
        let dto: ProfileDTO.Preferences = try await api.send(APIRequest(method: "PATCH", path: "me/preferences", body: body))
        return try dto.domain()
    }

    func devices() async throws -> [RegisteredDevice] {
        let items: [ProfileDTO.Device] = try await api.send(APIRequest(method: "GET", path: "me/devices"))
        return try items.map { try $0.domain() }
    }

    func registerPushToken(_ token: String) async throws {
        try await api.sendWithoutResponse(method: "PUT", path: "me/devices/current/push-token", body: ["token": token])
    }

    func notifications(cursor: String?) async throws -> InboxPage {
        var query = [URLQueryItem(name: "limit", value: "20")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let page: ProfileDTO.Page = try await api.send(APIRequest(method: "GET", path: "notifications", query: query))
        return try InboxPage(items: page.items.map { try $0.domain() }, nextCursor: page.nextCursor, unreadCount: page.unreadCount)
    }

    func markRead(id: UUID) async throws {
        try await api.sendWithoutResponse(method: "POST", path: "notifications/\(id.uuidString)/read")
    }

    func markAllRead() async throws {
        try await api.sendWithoutResponse(method: "POST", path: "notifications/read-all")
    }
}

/// Wire format of `/me` and `/notifications` (see api/openapi.yaml).
enum ProfileDTO {
    struct Profile: Decodable {
        let firstName: String
        let lastName: String
        let tier: String
        let maskedPhone: String
        let relationshipManager: Manager?
        let preferences: Preferences
        let unreadNotifications: Int

        func domain() throws -> BankProfile {
            BankProfile(
                firstName: firstName, lastName: lastName, tier: tier, maskedPhone: maskedPhone,
                relationshipManager: relationshipManager.map { RelationshipManager(name: $0.name, phone: $0.phone, hours: $0.hours) },
                preferences: try preferences.domain(), unreadNotifications: unreadNotifications
            )
        }
    }

    struct Manager: Decodable {
        let name: String
        let phone: String
        let hours: String
    }

    struct Preferences: Decodable {
        let language: String
        let notifyTransactions: Bool
        let notifyMarketing: Bool

        func domain() throws -> NotificationPreferences {
            guard let language = AppLanguage(rawValue: language) else { throw APIError.decoding }
            return NotificationPreferences(language: language, transactions: notifyTransactions, marketing: notifyMarketing)
        }
    }

    struct Device: Decodable {
        let id: UUID
        let name: String
        let registeredAt: String
        let revokedAt: String?
        let current: Bool
        let biometricEnabled: Bool

        func domain() throws -> RegisteredDevice {
            RegisteredDevice(
                id: id, name: name, registeredAt: try Timestamp.date(registeredAt), revokedAt: try revokedAt.map(Timestamp.date),
                isCurrent: current, biometricEnabled: biometricEnabled
            )
        }
    }

    struct Notification: Decodable {
        let id: UUID
        let kind: String
        let title: String
        let body: String
        let createdAt: String
        let read: Bool

        func domain() throws -> InboxItem {
            InboxItem(
                id: id, kind: InboxKind(rawValue: kind) ?? .marketing, title: title, body: body,
                createdAt: try Timestamp.date(createdAt), isRead: read
            )
        }
    }

    struct Page: Decodable {
        let items: [Notification]
        let nextCursor: String?
        let unreadCount: Int
    }
}
