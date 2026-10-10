import Foundation

enum BankTab: String, CaseIterable, Identifiable {
    case home
    case cards
    case payments
    case profile

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .home: "tab.home"
        case .cards: "tab.cards"
        case .payments: "tab.payments"
        case .profile: "tab.profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .cards: "creditcard"
        case .payments: "arrow.left.arrow.right"
        case .profile: "person"
        }
    }
}
