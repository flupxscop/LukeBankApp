import SwiftUI

struct ContentView: View {
    @State private var selectedTab: BankTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            BankTheme.background
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                DashboardView()
                    .tag(BankTab.home)

                CardsPlaceholderView()
                    .tag(BankTab.cards)

                PaymentsPlaceholderView()
                    .tag(BankTab.payments)

                ProfilePlaceholderView()
                    .tag(BankTab.profile)
            }
            .toolbar(.hidden, for: .tabBar)

            LuxeTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }
}

private struct CardsPlaceholderView: View {
    var body: some View {
        ScreenShell(title: "บัตรพรีเมียม", subtitle: "จัดการวงเงิน สิทธิพิเศษ และความปลอดภัยของบัตรได้ในที่เดียว") {
            VStack(spacing: 16) {
                FeatureRow(icon: "creditcard.fill", title: "Titanium Reserve", value: "มีบัตรใช้งาน 2 ใบ")
                FeatureRow(icon: "sparkles", title: "คะแนนสะสมพิเศษ", value: "12,800 คะแนน")
                FeatureRow(icon: "lock.shield.fill", title: "คุ้มครองการเดินทาง", value: "เปิดใช้งานอยู่")
            }
        }
    }
}

private struct PaymentsPlaceholderView: View {
    var body: some View {
        ScreenShell(title: "การชำระเงิน", subtitle: "โอนเร็ว จ่ายบิลง่าย และจัดการธุรกรรมต่างประเทศได้สะดวก") {
            VStack(spacing: 16) {
                FeatureRow(icon: "arrow.left.arrow.right.circle.fill", title: "โอนด่วน", value: "พร้อมใช้งาน")
                FeatureRow(icon: "doc.text.fill", title: "บิลที่ตั้งไว้", value: "รอชำระ 5 รายการ")
                FeatureRow(icon: "globe.asia.australia.fill", title: "กระเป๋าเงินต่างประเทศ", value: "รองรับ 8 สกุลเงิน")
            }
        }
    }
}

private struct ProfilePlaceholderView: View {
    var body: some View {
        ScreenShell(title: "บัญชีของฉัน", subtitle: "ภาพรวมการตั้งค่า ความปลอดภัย และบริการดูแลลูกค้าระดับพิเศษ") {
            VStack(spacing: 16) {
                FeatureRow(icon: "person.crop.circle.fill", title: "ผู้ดูแลบัญชี", value: "นกนางน้อย ใจดี")
                FeatureRow(icon: "bell.badge.fill", title: "การแจ้งเตือนความปลอดภัย", value: "เปิดใช้งานครบ")
                FeatureRow(icon: "gift.fill", title: "สิทธิพิเศษไลฟ์สไตล์", value: "ระดับ Gold")
            }
        }
    }
}

private struct ScreenShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(BankTheme.mutedText)
                }

                PremiumPanel {
                    content
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 140)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BankTheme.softGold.opacity(0.18))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BankTheme.softGold)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(value)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(BankTheme.mutedText)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

#Preview {
    ContentView()
}
