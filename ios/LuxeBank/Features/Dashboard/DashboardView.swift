import Charts
import SwiftUI

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    private let onShowHistory: (Account) -> Void
    private let onSelectTransaction: (Transaction) -> Void
    private let onQuickAction: (QuickAction) -> Void
    private let unreadCount: Int
    private let onOpenInbox: () -> Void

    init(
        viewModel: DashboardViewModel,
        onShowHistory: @escaping (Account) -> Void = { _ in },
        onSelectTransaction: @escaping (Transaction) -> Void = { _ in },
        onQuickAction: @escaping (QuickAction) -> Void = { _ in },
        unreadCount: Int = 0,
        onOpenInbox: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onShowHistory = onShowHistory
        self.onSelectTransaction = onSelectTransaction
        self.onQuickAction = onQuickAction
        self.unreadCount = unreadCount
        self.onOpenInbox = onOpenInbox
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, BankTheme.Spacing.screen)
                .padding(.top, 12)
                .padding(.bottom, BankTheme.Spacing.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(BankBackground())
        .accessibilityIdentifier("dashboard")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView { Task { await viewModel.retry() } }
        case .loaded(let summary):
            loaded(summary)
        }
    }

    private func loaded(_ summary: DashboardSummary) -> some View {
        VStack(spacing: BankTheme.Spacing.section) {
            header(summary)
            BalanceCard(
                summary: summary,
                history: viewModel.history(in: summary),
                range: $viewModel.selectedRange,
                isHidden: viewModel.isBalanceHidden,
                onToggleHidden: viewModel.toggleBalanceVisibility
            )
            QuickActionBar { action in
                viewModel.select(action)
                onQuickAction(action)
            }
            SpendingRingCard(spending: summary.spending)
            HStack(alignment: .top, spacing: 12) {
                CashbackCard(amount: summary.cashbackThisMonth, trend: summary.cashbackTrend, isHidden: viewModel.isBalanceHidden)
                if let goal = summary.savingsGoal { SavingsGoalCard(goal: goal) }
            }
            RecentTransactionsSection(
                transactions: summary.recentTransactions,
                now: viewModel.today,
                onShowAll: { onShowHistory(summary.primaryAccount) },
                onSelect: onSelectTransaction
            )
        }
    }

    private func header(_ summary: DashboardSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.today, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(BankFont.caption(13))
                    .foregroundStyle(BankTheme.secondaryText)
                (Text(viewModel.greeting.title) + Text(verbatim: ", \(summary.customerFirstName)"))
                    .font(BankFont.title(20))
                    .foregroundStyle(BankTheme.ink)
            }
            Spacer()
            Button(action: onOpenInbox) {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(BankTheme.ink)
                    .frame(width: 46, height: 46)
                    .background(BankTheme.surface, in: Circle())
                    .cardShadow(radius: 14, y: 4, opacity: 0.08)
                    .overlay(alignment: .topTrailing) { UnreadBadge(count: unreadCount).offset(x: 4, y: -4) }
            }
            .accessibilityLabel(Text("inbox.title"))
            .accessibilityValue(unreadCount > 0 ? Text("inbox.unread \(unreadCount)") : Text(verbatim: ""))
            .accessibilityIdentifier("dashboard.inbox")
            AvatarBadge(initial: String(summary.customerFirstName.prefix(1)))
        }
        .padding(.horizontal, 4)
    }
}

private struct AvatarBadge: View {
    let initial: String

    var body: some View {
        Circle()
            .fill(AngularGradient(colors: [BankTheme.glow, .white, Color(hex: 0xB7BDC9), BankTheme.glow], center: .center))
            .frame(width: 46, height: 46)
            .overlay {
                Circle().fill(.white).padding(2)
                Text(initial).font(BankFont.headline(16)).foregroundStyle(BankTheme.ink)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("profile.avatar"))
    }
}

private struct BalanceCard: View {
    let summary: DashboardSummary
    let history: [BalancePoint]
    @Binding var range: DashboardViewModel.HistoryRange
    let isHidden: Bool
    let onToggleHidden: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("dashboard.wealth")
                    .font(BankFont.caption(13))
                    .foregroundStyle(BankTheme.secondaryText)
                Button(action: onToggleHidden) {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BankTheme.secondaryText)
                        .frame(width: 44, height: 32)
                }
                .accessibilityLabel(Text("balance.toggle"))
                Spacer()
                RangePicker(selection: $range)
            }

            MoneyText(amount: summary.primaryAccount.balance, size: 40, hidden: isHidden)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Text(isHidden ? "+฿ •••" : "+" + BankFormatter.currencyParts(summary.monthChange).main)
                    .font(BankFont.caption(13, bold: true))
                    .foregroundStyle(BankTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(BankTheme.accentTint, in: Capsule())
                Text("dashboard.changeRate \(BankFormatter.percent(summary.monthChangeRate))")
                    .font(BankFont.caption(13))
                    .foregroundStyle(BankTheme.secondaryText)
            }
            .padding(.top, 6)

            BalanceChart(points: history)
                .frame(height: 110)
                .padding(.top, 10)
                .padding(.horizontal, -22)
        }
        .padding([.top, .horizontal], 22)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: BankTheme.Radius.hero, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BankTheme.Radius.hero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BankTheme.Radius.hero, style: .continuous).stroke(.white, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: BankTheme.Radius.hero, style: .continuous))
        .cardShadow(radius: 60, y: 30, opacity: 0.12)
    }
}

private struct RangePicker: View {
    @Binding var selection: DashboardViewModel.HistoryRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardViewModel.HistoryRange.allCases) { range in
                let isSelected = range == selection
                Button { selection = range } label: {
                    Text(range.title)
                        .font(BankFont.caption(11, bold: true))
                        .foregroundStyle(isSelected ? Color.white : BankTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(isSelected ? BankTheme.ink : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(hex: 0xECEEF3), in: Capsule())
    }
}

private struct BalanceChart: View {
    let points: [BalancePoint]

    var body: some View {
        let values = points.map(\.chartValue)
        let lower = (values.min() ?? 0) * 0.995
        let upper = (values.max() ?? 1) * 1.002

        Chart(points) { point in
            AreaMark(x: .value("date", point.date), yStart: .value("min", lower), yEnd: .value("balance", point.chartValue))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [BankTheme.accentSoft.opacity(0.32), BankTheme.accentSoft.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LineMark(x: .value("date", point.date), y: .value("balance", point.chartValue))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(BankTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: lower...upper)
        .accessibilityLabel(Text("chart.balance.label"))
    }
}

private struct QuickActionBar: View {
    let onSelect: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { onSelect(.transfer) } label: {
                Label { Text(QuickAction.transfer.title) } icon: { Image(systemName: QuickAction.transfer.symbol) }
                    .font(BankFont.body(14, bold: true))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(BankTheme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)

            ForEach([QuickAction.scan, .payBill, .topUp], id: \.self) { action in
                Button { onSelect(action) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(BankTheme.ink)
                        .frame(width: 62, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(action.title))
            }
        }
        .padding(6)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .cardShadow(radius: 30, y: 10, opacity: 0.08)
    }
}

private struct SpendingRingCard: View {
    let spending: SpendingSummary

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(BankTheme.line, lineWidth: 10)
                let lifestyle = spending.share(of: .lifestyle)
                let travel = spending.share(of: .travel)
                Circle()
                    .trim(from: 0, to: lifestyle)
                    .stroke(BankTheme.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: lifestyle + 0.02, to: min(1, lifestyle + travel))
                    .stroke(BankTheme.accentSoft, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(BankFormatter.percent(Decimal(Int((spending.usage * 100).rounded()))))
                        .font(BankFont.headline(20))
                    Text("spending.ofBudget")
                        .font(BankFont.caption(10))
                        .foregroundStyle(BankTheme.secondaryText)
                }
            }
            .frame(width: 104, height: 104)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                Text("spending.title")
                    .font(BankFont.caption(13))
                    .foregroundStyle(BankTheme.secondaryText)
                Text(BankFormatter.currencyParts(spending.totalSpent).main)
                    .font(BankFont.figure(26))
                    .monospacedDigit()
                ForEach(spending.categories) { category in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(category.kind == .lifestyle ? BankTheme.ink : BankTheme.accentSoft)
                            .frame(width: 8, height: 8)
                        Text(category.kind.title)
                        Text(BankFormatter.currencyParts(category.spent).main)
                            .monospacedDigit()
                            .foregroundStyle(BankTheme.secondaryText)
                    }
                    .font(BankFont.caption(12))
                }
            }
            Spacer(minLength: 0)
        }
        .surfaceCard(padding: 20)
    }
}

private struct CashbackCard: View {
    let amount: Decimal
    let trend: [Decimal]
    let isHidden: Bool

    private static let highlight = AnyShapeStyle(
        LinearGradient(colors: [BankTheme.accentSoft, BankTheme.accent], startPoint: .top, endPoint: .bottom)
    )

    var body: some View {
        let maxValue = trend.max() ?? 1
        VStack(alignment: .leading, spacing: 14) {
            Text("cashback.title")
                .font(BankFont.caption(13))
                .foregroundStyle(BankTheme.secondaryText)
            Text(isHidden ? "฿ •••" : BankFormatter.currencyParts(amount).main)
                .font(BankFont.figure(22))
                .monospacedDigit()
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(trend.enumerated()), id: \.offset) { index, value in
                    let ratio = maxValue > 0 ? NSDecimalNumber(decimal: value / maxValue).doubleValue : 0
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == trend.count - 1 ? Self.highlight : AnyShapeStyle(Color(hex: 0xE6E9F0)))
                        .frame(height: max(6, 44 * ratio))
                }
            }
            .frame(height: 44, alignment: .bottom)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 150, alignment: .top)
        .surfaceCard(padding: 18)
    }
}

private struct SavingsGoalCard: View {
    let goal: SavingsGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("savings.title")
                .font(BankFont.caption(13))
                .foregroundStyle(Color(hex: 0x3A404C))
            Spacer(minLength: 0)
            Text(BankFormatter.percent(Decimal(Int((goal.progress * 100).rounded()))))
                .font(BankFont.figure(22))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(BankTheme.ink.opacity(0.1))
                    Capsule().fill(BankTheme.ink).frame(width: proxy.size.width * goal.progress)
                }
            }
            .frame(height: 6)
            Text(verbatim: "\(BankFormatter.currencyParts(goal.saved).main) / \(BankFormatter.currencyParts(goal.target).main)")
                .font(BankFont.caption(11))
                .foregroundStyle(Color(hex: 0x3A404C))
                .monospacedDigit()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(BankTheme.silver, in: RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous).stroke(.white, lineWidth: 1))
        .cardShadow(radius: 30, y: 10, opacity: 0.1)
        .accessibilityElement(children: .combine)
    }
}

private struct RecentTransactionsSection: View {
    let transactions: [Transaction]
    let now: Date
    let onShowAll: () -> Void
    let onSelect: (Transaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "transactions.title", actionTitle: "transactions.seeAll", action: onShowAll)
                .padding(.bottom, 4)
            ForEach(transactions) { transaction in
                Button { onSelect(transaction) } label: {
                    TransactionRow(transaction: transaction, subtitle: BankFormatter.transactionDate(transaction.date, now: now))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.transaction")
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview("Loaded") {
    DashboardView(viewModel: DashboardViewModel(repository: MockDashboardRepository()))
}

#Preview("Error") {
    DashboardView(viewModel: DashboardViewModel(repository: MockDashboardRepository(shouldFail: true)))
}
