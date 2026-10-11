import SwiftUI

/// The physical card look: titanium for credit, ink for debit; grey and labelled when frozen.
struct CardFace: View {
    let card: BankCard

    var body: some View {
        let isCredit = card.kind == .credit
        VStack(alignment: .leading) {
            HStack {
                Text(verbatim: "LUXE").font(BankFont.caption(14, bold: true)).tracking(4.5)
                Spacer()
                Text(verbatim: card.productName.uppercased()).font(BankFont.caption(10, bold: true)).tracking(2)
                    .foregroundStyle(isCredit ? Color(hex: 0x3A404C) : .white.opacity(0.75))
            }
            Spacer()
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF2F4F8), Color(hex: 0x9AA2AF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 42, height: 32)
                .accessibilityHidden(true)
            Spacer()
            HStack(alignment: .bottom) {
                Text(verbatim: "•••• \(card.last4)").font(BankFont.body(17, bold: true)).tracking(2.5).monospacedDigit()
                Spacer()
                if card.isFrozen {
                    Text("cards.frozenBadge")
                        .font(BankFont.caption(11, bold: true))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BankTheme.ink, in: Capsule())
                } else {
                    Text(verbatim: card.expiry).font(BankFont.caption(12, bold: true)).monospacedDigit()
                }
            }
        }
        .foregroundStyle(isCredit ? Color(hex: 0x1E232B) : .white)
        .padding(22)
        .frame(height: 214)
        .background {
            ZStack {
                if isCredit {
                    LinearGradient(
                        colors: [Color(hex: 0xFAFBFC), Color(hex: 0xDDE1E8), Color(hex: 0xAEB5C1)], startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(colors: [Color(hex: 0x2A2F38), BankTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                LinearGradient(colors: [.clear, .white.opacity(isCredit ? 0.8 : 0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(isCredit ? 1 : 0.15), lineWidth: 1))
        .shadow(color: BankTheme.shadow.opacity(0.25), radius: 30, y: 30)
        .grayscale(card.isFrozen ? 1 : 0)
        .opacity(card.isFrozen ? 0.85 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("cards.faceLabel \(card.productName) \(card.last4)"))
    }
}

/// Screens pushed from the cards tab.
enum CardRoute: Hashable {
    case detail(UUID, reveal: Bool)
    case transactions(UUID)
}

/// S15 — cards tab. The navigation path lives in ContentView so the tab bar can hide on pushed screens.
struct CardsView: View {
    @State var viewModel: CardsViewModel
    @Binding var path: [CardRoute]
    let authorizer: PaymentAuthorizing
    let onPayCard: (BankCard) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    switch viewModel.state {
                    case .loading: LoadingStateView().padding(.top, -60)
                    case .failed: ErrorStateView { Task { await viewModel.load() } }.padding(.top, -60)
                    case .empty: EmptyStateView(title: "cards.empty.title", message: "cards.empty.message")
                    case .loaded: content
                    }
                }
                .padding(.horizontal, BankTheme.Spacing.screen)
                .padding(.top, 12)
                .padding(.bottom, BankTheme.Spacing.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .background(BankBackground())
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .navigationDestination(for: CardRoute.self) { route in
                switch route {
                case .detail(let id, let reveal):
                    if let card = viewModel.card(id: id) {
                        CardDetailView(
                            viewModel: CardDetailViewModel(
                                card: card, repository: viewModel.repository, authorizer: authorizer,
                                onChange: { updated, old in viewModel.replace(updated, replacing: old) }
                            ),
                            revealOnAppear: reveal
                        )
                    }
                case .transactions(let id):
                    CardTransactionsView(cardID: id, repository: viewModel.repository)
                }
            }
        }
        .tint(BankTheme.ink)
        .accessibilityIdentifier("cards")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("tab.cards").font(BankFont.title(32))
            Spacer()
            HStack(spacing: 6) {
                ForEach(viewModel.cards) { card in
                    Capsule()
                        .fill(card.id == viewModel.selected?.id ? BankTheme.ink : Color(hex: 0xC9CED8))
                        .frame(width: card.id == viewModel.selected?.id ? 22 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        TabView(selection: Binding(get: { viewModel.selected?.id }, set: { id in if let id { Task { await viewModel.select(id) } } })) {
            ForEach(viewModel.cards) { card in
                CardFace(card: card)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 34)
                    .tag(Optional(card.id))
                    .onTapGesture { path.append(.detail(card.id, reveal: false)) }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 250)
        .padding(.bottom, -28)

        if let card = viewModel.selected {
            actions(card)
            InlineError(message: viewModel.error)
            summary(card)
            perks(card)
            recent(card)
        }
    }

    private func actions(_ card: BankCard) -> some View {
        HStack(spacing: 8) {
            action(
                card.isFrozen ? "cards.unfreeze" : "cards.freeze", symbol: "snowflake", tint: BankTheme.accent, fill: BankTheme.accentTint,
                id: "cards.freeze"
            ) {
                Task { await viewModel.toggleFreeze() }
            }
            action("cards.showNumber", symbol: "eye", id: "cards.showNumber") { path.append(.detail(card.id, reveal: true)) }
            action("cards.settings", symbol: "slider.horizontal.3", id: "cards.settings") { path.append(.detail(card.id, reveal: false)) }
            if card.kind == .credit {
                action("cards.pay", symbol: "checkmark", tint: .white, fill: BankTheme.ink, id: "cards.pay") { onPayCard(card) }
            } else {
                action("cards.history", symbol: "list.bullet", id: "cards.history") { path.append(.transactions(card.id)) }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .cardShadow(radius: 22, y: 8, opacity: 0.07)
        .disabled(viewModel.isUpdating)
    }

    private func action(
        _ title: LocalizedStringKey, symbol: String, tint: Color = BankTheme.ink, fill: Color = BankTheme.porcelain, id: String,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(title).font(BankFont.caption(12, bold: true)).foregroundStyle(BankTheme.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func summary(_ card: BankCard) -> some View {
        if let credit = card.credit {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("cards.available").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
                    Spacer()
                    Text("cards.ofLimit \(BankFormatter.currencyParts(credit.limit).main)").font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                }
                Text(verbatim: BankFormatter.currencyParts(credit.available).main).font(BankFont.figure(34)).monospacedDigit()
                    .accessibilityIdentifier("cards.availableValue")
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BankTheme.accentTint)
                        Capsule().fill(BankTheme.accent).frame(width: proxy.size.width * credit.usage)
                    }
                }
                .frame(height: 8)
                HStack(spacing: 8) {
                    stat("cards.used", BankFormatter.currencyParts(credit.used).main)
                    stat("cards.minimum", BankFormatter.currencyParts(credit.minimumPayment).main)
                    stat("cards.due", credit.dueDate.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "—", highlight: true)
                }
            }
            .surfaceCard(radius: 26, padding: 20)
        } else if let balance = card.linkedBalance {
            VStack(alignment: .leading, spacing: 6) {
                Text("cards.linkedAccount \(card.linkedAccount ?? "")").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
                Text(verbatim: BankFormatter.currencyParts(balance).main).font(BankFont.figure(30)).monospacedDigit()
                Text("cards.dailyLimitValue \(BankFormatter.currencyParts(card.dailyLimit).main)")
                    .font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
            }
            .surfaceCard(radius: 26, padding: 20)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(BankFont.caption(11)).foregroundStyle(highlight ? BankTheme.caution : BankTheme.secondaryText)
            Text(verbatim: value).font(BankFont.body(14, bold: true)).foregroundStyle(highlight ? BankTheme.caution : BankTheme.ink)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? BankTheme.cautionTint : BankTheme.porcelain, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func perks(_ card: BankCard) -> some View {
        if card.kind == .credit {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("cards.points").font(BankFont.caption(12, bold: true)).foregroundStyle(Color(hex: 0x3A404C))
                    Text(card.rewardPoints, format: .number).font(BankFont.figure(24)).monospacedDigit()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BankTheme.silver, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 18) {
                    Text("cards.travelInsurance").font(BankFont.caption(12, bold: true)).foregroundStyle(BankTheme.secondaryText)
                    Label(card.travelInsurance ? "cards.on" : "cards.off", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(BankFont.body(15, bold: true))
                        .foregroundStyle(card.travelInsurance ? BankTheme.positive : BankTheme.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func recent(_ card: BankCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("cards.recent").font(BankFont.headline(15))
                Spacer()
                Button("transactions.seeAll") { path.append(.transactions(card.id)) }
                    .font(BankFont.caption(13, bold: true))
                    .foregroundStyle(BankTheme.accent)
                    .frame(minHeight: 44)
            }
            if viewModel.recent.isEmpty {
                Text("cards.noPurchases").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText).padding(.vertical, 12)
            }
            ForEach(viewModel.recent) { transaction in
                TransactionRow(
                    transaction: transaction,
                    subtitle: BankFormatter.transactionDate(transaction.date),
                    style: .inset
                )
                .accessibilityIdentifier("cards.transaction")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .cardShadow()
    }
}

/// All purchases of one card (CARD-09).
struct CardTransactionsView: View {
    let cardID: UUID
    let repository: CardRepository
    @State private var items: [Transaction] = []
    @State private var cursor: String?
    @State private var failed = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { transaction in
                    TransactionRow(transaction: transaction, subtitle: BankFormatter.transactionDate(transaction.date), style: .inset)
                        .task {
                            if transaction.id == items.last?.id, let cursor { await load(cursor: cursor) }
                        }
                }
                if failed { ErrorStateView { Task { await load(cursor: nil) } } }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Text("cards.recent").font(BankFont.headline(17)) } }
        .task { await load(cursor: nil) }
    }

    private func load(cursor: String?) async {
        do {
            let page = try await repository.transactions(cardID: cardID, cursor: cursor)
            items = cursor == nil ? page.items : items + page.items
            self.cursor = page.nextCursor
            failed = false
        } catch {
            failed = items.isEmpty
        }
    }
}
