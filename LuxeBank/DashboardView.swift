import SwiftUI

struct DashboardView: View {
    private let account = MockBankData.account
    private let actions = MockBankData.actions
    private let transactions = MockBankData.transactions
    private let insights = MockBankData.insights

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                balanceCard
                quickActions
                insightsPanel
                transactionsPanel
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 140)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("สวัสดีตอนเย็น คุณนกน้อย")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Text("ภาพรวมการเงินของคุณ")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BankTheme.softGold.opacity(0.9), .white.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)

                Text("น")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(BankTheme.backgroundBase)
            }
        }
    }

    private var balanceCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(BankTheme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

            Circle()
                .fill(BankTheme.softGold.opacity(0.16))
                .blur(radius: 10)
                .frame(width: 180, height: 180)
                .offset(x: 170, y: -25)

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(account.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(account.maskedNumber)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(BankTheme.mutedText)
                    }

                    Spacer()

                    Label("\(account.changeRate, specifier: "%.1f")%", systemImage: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BankTheme.success.opacity(0.18))
                        .foregroundStyle(BankTheme.success)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("ยอดเงินคงเหลือ")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(BankTheme.mutedText)

                    Text(BankFormatter.currency(account.balance))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("เงินคืนเดือนนี้")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(BankTheme.mutedText)

                        Text("฿12,400")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("ผลตอบแทนการลงทุน")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(BankTheme.mutedText)

                        Text("+12.8%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(BankTheme.softGold)
                    }
                }
            }
            .padding(24)
        }
        .frame(height: 240)
        .shadow(color: BankTheme.shadowColor, radius: 24, x: 0, y: 18)
    }

    private var quickActions: some View {
        PremiumPanel(title: "เมนูลัด", trailingText: "ปรับแต่ง") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(actions) { action in
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 58)

                            Image(systemName: action.icon)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(BankTheme.softGold)
                        }

                        Text(action.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var insightsPanel: some View {
        PremiumPanel(title: "สรุปการใช้จ่าย", trailingText: "เมษายน") {
            VStack(spacing: 18) {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(insight.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()

                            Text(insight.amountText)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(BankTheme.mutedText)
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 10)

                                Capsule()
                                    .fill(BankTheme.goldGradient)
                                    .frame(width: proxy.size.width * insight.progress, height: 10)
                            }
                        }
                        .frame(height: 10)
                    }
                }
            }
        }
    }

    private var transactionsPanel: some View {
        PremiumPanel(title: "รายการล่าสุด", trailingText: "ดูทั้งหมด") {
            VStack(spacing: 14) {
                ForEach(transactions) { item in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(item.tint.opacity(0.18))
                                .frame(width: 52, height: 52)

                            Image(systemName: item.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(item.tint)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.merchant)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("\(item.category) • \(item.dateText)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(BankTheme.mutedText)
                        }

                        Spacer()

                        Text(BankFormatter.currency(item.amount))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(item.amount >= 0 ? BankTheme.success : .white)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
