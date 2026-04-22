import SwiftUI

enum BankTheme {
    static let backgroundBase = Color(red: 0.05, green: 0.07, blue: 0.13)
    static let surface = Color(red: 0.10, green: 0.12, blue: 0.20)
    static let surfaceSecondary = Color(red: 0.16, green: 0.18, blue: 0.28)
    static let mutedText = Color.white.opacity(0.68)
    static let softGold = Color(red: 0.93, green: 0.78, blue: 0.48)
    static let success = Color(red: 0.45, green: 0.92, blue: 0.72)
    static let shadowColor = Color.black.opacity(0.32)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.06, blue: 0.12),
            Color(red: 0.08, green: 0.10, blue: 0.18),
            Color(red: 0.13, green: 0.16, blue: 0.25)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [
            Color(red: 0.13, green: 0.16, blue: 0.27),
            Color(red: 0.10, green: 0.12, blue: 0.22),
            Color(red: 0.22, green: 0.18, blue: 0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let goldGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.88, blue: 0.62),
            Color(red: 0.87, green: 0.67, blue: 0.34)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

enum BankFormatter {
    static let thaiLocale = Locale(identifier: "th_TH")

    static func currency(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "THB")
                .locale(thaiLocale)
        )
    }
}

struct PremiumPanel<Content: View>: View {
    var title: String?
    var trailingText: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, trailingText: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailingText = trailingText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    if let trailingText {
                        Text(trailingText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(BankTheme.softGold)
                    }
                }
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            BankTheme.surface.opacity(0.96),
                            BankTheme.surfaceSecondary.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct LuxeTabBar: View {
    @Binding var selectedTab: BankTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(BankTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))

                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? BankTheme.backgroundBase : .white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(selectedTab == tab ? BankTheme.goldGradient : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(BankTheme.surface.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: BankTheme.shadowColor, radius: 18, x: 0, y: 14)
    }
}
