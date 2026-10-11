import Foundation

/// The demo customer's profile, RM, devices and inbox, with the server's rules:
/// preferences change partially, reads are per item or all at once, the inbox pages by cursor.
@MainActor
final class MockProfileRepository: ProfileRepository {
    var shouldFail = false
    var delay: Duration = .milliseconds(200)
    private(set) var pushToken: String?
    private var preferences: NotificationPreferences
    private var inbox: [InboxItem]
    private let now: Date

    static let pageSize = 20

    init(now: Date = Date(), language: AppLanguage = .current) {
        self.now = now
        preferences = NotificationPreferences(language: language, transactions: true, marketing: false)
        let hour: TimeInterval = 3_600
        inbox = [
            InboxItem(
                id: UUID(), kind: .transaction, title: String(localized: "mock.inbox.moneyIn"),
                body: "Payroll · x4521", createdAt: now.addingTimeInterval(-2 * hour), isRead: false
            ),
            InboxItem(
                id: UUID(), kind: .transaction, title: String(localized: "mock.inbox.moneyOut"),
                body: "Sarnies Bangkok · x4521", createdAt: now.addingTimeInterval(-20 * hour), isRead: false
            ),
            InboxItem(
                id: UUID(), kind: .marketing, title: String(localized: "mock.inbox.offerTitle"),
                body: String(localized: "mock.inbox.offerBody"), createdAt: now.addingTimeInterval(-48 * hour), isRead: true
            ),
            InboxItem(
                id: UUID(), kind: .security, title: String(localized: "mock.inbox.newDeviceTitle"),
                body: String(localized: "mock.inbox.newDeviceBody"), createdAt: now.addingTimeInterval(-120 * hour), isRead: true
            ),
        ]
    }

    func profile() async throws -> BankProfile {
        try await pause()
        let english = preferences.language == .english
        return BankProfile(
            firstName: english ? "Noknoi" : "นกน้อย",
            lastName: english ? "Jaingam" : "ใจงาม",
            tier: "GOLD",
            maskedPhone: "08X-XXX-4521",
            relationshipManager: RelationshipManager(
                name: english ? "Noknangnoi Jaidee" : "นกนางน้อย ใจดี",
                phone: "021234567",
                hours: english ? "Mon–Fri 09:00–18:00" : "จันทร์–ศุกร์ 09:00–18:00"
            ),
            preferences: preferences,
            unreadNotifications: inbox.filter { !$0.isRead }.count
        )
    }

    func updatePreferences(_ change: PreferencesChange) async throws -> NotificationPreferences {
        try await pause()
        if let language = change.language { preferences.language = language }
        if let transactions = change.transactions { preferences.transactions = transactions }
        if let marketing = change.marketing { preferences.marketing = marketing }
        return preferences
    }

    func devices() async throws -> [RegisteredDevice] {
        try await pause()
        return [
            RegisteredDevice(
                id: UUID(), name: "iPhone", registeredAt: now.addingTimeInterval(-86_400 * 30), revokedAt: nil,
                isCurrent: true, biometricEnabled: true
            ),
            RegisteredDevice(
                id: UUID(), name: "iPhone 12", registeredAt: now.addingTimeInterval(-86_400 * 400),
                revokedAt: now.addingTimeInterval(-86_400 * 30), isCurrent: false, biometricEnabled: false
            ),
        ]
    }

    func registerPushToken(_ token: String) async throws {
        try await pause()
        pushToken = token
    }

    func notifications(cursor: String?) async throws -> InboxPage {
        try await pause()
        let sorted = inbox.sorted { $0.createdAt > $1.createdAt }
        let start = cursor.flatMap(Int.init) ?? 0
        let page = Array(sorted.dropFirst(start).prefix(Self.pageSize))
        let next = start + page.count < sorted.count ? String(start + page.count) : nil
        return InboxPage(items: page, nextCursor: next, unreadCount: inbox.filter { !$0.isRead }.count)
    }

    func markRead(id: UUID) async throws {
        try await pause()
        guard let index = inbox.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(code: "NOT_FOUND", message: "not found", remainingAttempts: nil)
        }
        inbox[index].isRead = true
    }

    func markAllRead() async throws {
        try await pause()
        for index in inbox.indices { inbox[index].isRead = true }
    }

    /// Adds an entry as the server would after a posting or a security event (tests and previews).
    func deliver(_ item: InboxItem) {
        inbox.append(item)
    }

    private func pause() async throws {
        try await Task.sleep(for: delay)
        if shouldFail { throw APIError.server(code: "INTERNAL", message: "mock failure", remainingAttempts: nil) }
    }
}
