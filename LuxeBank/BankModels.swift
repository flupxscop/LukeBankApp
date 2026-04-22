import Foundation
import SwiftUI

struct AccountSummary: Identifiable {
    let id = UUID()
    let name: String
    let maskedNumber: String
    let balance: Double
    let changeRate: Double
    let accent: Color
}

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

struct TransactionItem: Identifiable {
    let id = UUID()
    let merchant: String
    let category: String
    let dateText: String
    let amount: Double
    let icon: String
    let tint: Color
}

struct SpendingInsight: Identifiable {
    let id = UUID()
    let title: String
    let amountText: String
    let progress: Double
}

enum BankTab: String, CaseIterable {
    case home
    case cards
    case payments
    case profile

    var icon: String {
        switch self {
        case .home:
            return "house.fill"
        case .cards:
            return "creditcard.fill"
        case .payments:
            return "arrow.left.arrow.right"
        case .profile:
            return "person.fill"
        }
    }

    var title: String {
        switch self {
        case .home:
            return "หน้าแรก"
        case .cards:
            return "บัตร"
        case .payments:
            return "จ่ายเงิน"
        case .profile:
            return "บัญชี"
        }
    }
}
