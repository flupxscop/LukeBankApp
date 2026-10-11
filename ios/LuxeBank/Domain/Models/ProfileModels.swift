import Foundation

enum AppLanguage: String, CaseIterable {
    case thai = "th"
    case english = "en"

    /// The language the app is showing now.
    static var current: AppLanguage {
        Locale.current.language.languageCode?.identifier == "en" ? .english : .thai
    }
}

/// PROF-05, NOTI-01/02. Security alerts are always on and cannot be changed.
struct NotificationPreferences: Equatable {
    var language: AppLanguage
    var transactions: Bool
    var marketing: Bool
}

/// Changes to send with `PATCH /me/preferences`; nil keeps the current value.
struct PreferencesChange: Equatable {
    var language: AppLanguage?
    var transactions: Bool?
    var marketing: Bool?
}

struct RelationshipManager: Equatable {
    let name: String
    let phone: String
    let hours: String
}

/// PROF-01: who the customer is, their RM and how they want to be told about things.
struct BankProfile: Equatable {
    let firstName: String
    let lastName: String
    let tier: String
    let maskedPhone: String
    let relationshipManager: RelationshipManager?
    var preferences: NotificationPreferences
    var unreadNotifications: Int
}

/// PROF-06: the bound device and the ones it replaced.
struct RegisteredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let registeredAt: Date
    let revokedAt: Date?
    let isCurrent: Bool
    let biometricEnabled: Bool

    var isActive: Bool { revokedAt == nil }
}

enum InboxKind: String {
    case transaction
    case security
    case marketing
}

/// NOTI-03: one entry in the in-app inbox.
struct InboxItem: Identifiable, Equatable {
    let id: UUID
    let kind: InboxKind
    let title: String
    let body: String
    let createdAt: Date
    var isRead: Bool
}

struct InboxPage: Equatable {
    let items: [InboxItem]
    let nextCursor: String?
    let unreadCount: Int
}
