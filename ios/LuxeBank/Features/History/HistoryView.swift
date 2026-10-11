import SwiftUI

/// S17 — history with totals, search, filters and day groups (TXN-01…03).
struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel
    let onSelect: (Transaction) -> Void
    var now: () -> Date = Date.init

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                totals
                searchField
                filters
                content
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("history.title").font(BankFont.headline(17))
            }
        }
        .accessibilityIdentifier("history")
        .task(id: viewModel.query) { await viewModel.reload() }
        .refreshable { await viewModel.reload() }
    }

    // MARK: Sections

    private var totals: some View {
        HStack(spacing: 10) {
            totalCard(title: "history.moneyIn \(viewModel.query.periodDays)", value: viewModel.totals?.moneyIn, sign: "+", color: BankTheme.positive)
            totalCard(title: "history.moneyOut \(viewModel.query.periodDays)", value: viewModel.totals?.moneyOut, sign: "−", color: BankTheme.ink)
        }
    }

    private func totalCard(title: LocalizedStringKey, value: Decimal?, sign: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BankFont.caption(12))
                .foregroundStyle(BankTheme.secondaryText)
            Text(verbatim: value.map { sign + BankFormatter.currencyParts($0).main } ?? "—")
                .font(BankFont.figure(18))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .cardShadow(radius: 16, y: 6, opacity: 0.06)
        .accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BankTheme.secondaryText)
                .accessibilityHidden(true)
            TextField("history.search", text: $viewModel.query.text)
                .font(BankFont.body(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("history.search")
            if !viewModel.query.text.isEmpty {
                Button {
                    viewModel.query.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BankTheme.fractionText)
                }
                .accessibilityLabel(Text("history.search.clear"))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.field, style: .continuous))
        .cardShadow(radius: 12, y: 4, opacity: 0.05)
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                directionChip(nil, title: "history.filter.all")
                directionChip(.incoming, title: "history.filter.in")
                directionChip(.outgoing, title: "history.filter.out")
                categoryMenu
                periodMenu
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func directionChip(_ direction: TransactionDirection?, title: LocalizedStringKey) -> some View {
        Button {
            viewModel.query.direction = direction
        } label: {
            FilterChip(isSelected: viewModel.query.direction == direction) { Text(title) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(viewModel.query.direction == direction ? .isSelected : [])
    }

    private var categoryMenu: some View {
        Menu {
            Picker(selection: $viewModel.query.category) {
                Text("history.filter.anyCategory").tag(TransactionCategory?.none)
                ForEach(TransactionCategory.allCases) { category in
                    Label { Text(category.title) } icon: { Image(systemName: category.symbol) }
                        .tag(TransactionCategory?.some(category))
                }
            } label: {
                EmptyView()
            }
        } label: {
            FilterChip(isSelected: viewModel.query.category != nil) {
                HStack(spacing: 4) {
                    if let category = viewModel.query.category { Text(category.title) } else { Text("history.filter.category") }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
            }
        }
        .accessibilityIdentifier("history.filter.category")
    }

    private var periodMenu: some View {
        Menu {
            Picker(selection: $viewModel.query.periodDays) {
                ForEach(TransactionQuery.periods, id: \.self) { days in
                    Text("history.period \(days)").tag(days)
                }
            } label: {
                EmptyView()
            }
        } label: {
            FilterChip(isSelected: false) {
                HStack(spacing: 4) {
                    Text("history.period \(viewModel.query.periodDays)")
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
            }
        }
        .accessibilityIdentifier("history.filter.period")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView().padding(.top, -60)
        case .failed:
            ErrorStateView { Task { await viewModel.reload() } }.padding(.top, -60)
        case .empty:
            if viewModel.hasActiveFilters {
                EmptyStateView(title: "history.empty.title", message: "history.empty.filtered", actionTitle: "history.clearFilters") {
                    viewModel.clearFilters()
                }
            } else {
                EmptyStateView(title: "history.empty.title", message: "history.empty.message")
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.sections.enumerated()), id: \.element.id) { index, section in
                Text(verbatim: BankFormatter.dayHeader(section.day, now: now()))
                    .font(BankFont.caption(12, bold: true))
                    .foregroundStyle(BankTheme.secondaryText)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(BankTheme.line).frame(height: 1) }
                    }
                    .accessibilityAddTraits(.isHeader)
                ForEach(section.items) { transaction in
                    Button { onSelect(transaction) } label: {
                        TransactionRow(transaction: transaction, subtitle: BankFormatter.time(transaction.date), style: .inset)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history.row")
                    .task { await viewModel.loadMoreIfNeeded(after: transaction) }
                }
            }
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .cardShadow()
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.isLoadingMore {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
        } else if viewModel.loadMoreFailed {
            Button("state.retry") { Task { await viewModel.loadMore() } }
                .font(BankFont.body(14, bold: true))
                .foregroundStyle(BankTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(
            viewModel: HistoryViewModel(account: MockBankData.primaryAccount(), repository: MockBankRepository()),
            onSelect: { _ in }
        )
    }
}
