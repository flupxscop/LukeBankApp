import SwiftUI

/// Full-screen bill and top-up flow: S13 → S14 → S10 → S11.
struct BillFlowView: View {
    @State var viewModel: BillsViewModel
    let authorizer: PaymentAuthorizing
    let onClose: (_ completed: Bool) -> Void
    var onScan: (() -> Void)?

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            BillersView(viewModel: viewModel, onClose: { onClose(false) }, onScan: onScan)
                .navigationDestination(for: BillsViewModel.Step.self) { step in
                    switch step {
                    case .pay(let target):
                        BillPayView(
                            viewModel: BillPayViewModel(
                                target: target,
                                biller: target.biller ?? viewModel.biller(code: target.billerCode),
                                accounts: viewModel.accounts,
                                repository: viewModel.repository
                            ),
                            onPriced: viewModel.showConfirm
                        )
                    case .confirm(let inquiry):
                        PaymentConfirmView(
                            viewModel: PaymentConfirmViewModel(inquiry: inquiry, authorizer: authorizer, saveByDefault: true) { [viewModel] in
                                try await viewModel.confirmInquiry(inquiry, authorization: $0, key: $1, save: $2)
                            },
                            onSlip: viewModel.showSlip,
                            onExpired: viewModel.backToPay
                        )
                    case .slip(let slip):
                        SlipView(slip: slip) { onClose(true) }
                    }
                }
        }
        .tint(BankTheme.ink)
        .task { await viewModel.load() }
    }
}

/// S13 — saved bills, categories and billers.
struct BillersView: View {
    @Bindable var viewModel: BillsViewModel
    let onClose: () -> Void
    var onScan: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BankTheme.secondaryText)
                    TextField("bills.search", text: $viewModel.search).font(BankFont.body(15))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                switch viewModel.state {
                case .loading: LoadingStateView().padding(.top, -60)
                case .failed: ErrorStateView { Task { await viewModel.load() } }.padding(.top, -60)
                case .loaded: content
                }
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) { Image(systemName: "xmark") }.accessibilityLabel(Text("common.close"))
            }
            ToolbarItem(placement: .principal) { Text("bills.title").font(BankFont.headline(17)) }
            if let onScan {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onScan) { Image(systemName: "barcode.viewfinder") }
                        .tint(BankTheme.accent)
                        .accessibilityLabel(Text("bills.scan"))
                }
            }
        }
        .accessibilityIdentifier("billers")
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.saved.isEmpty, viewModel.search.isEmpty {
            Text("bills.saved").font(BankFont.headline(15))
            VStack(spacing: 0) {
                ForEach(viewModel.saved) { bill in
                    Button { viewModel.pay(bill) } label: { SavedBillRow(bill: bill) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bills.savedRow")
                }
            }
            .padding(.horizontal, 16)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .cardShadow()
        }

        Text("bills.categories").font(BankFont.headline(15))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(BillerCategory.allCases) { category in
                let isSelected = viewModel.category == category
                Button {
                    viewModel.category = isSelected ? nil : category
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: category.symbol).font(.system(size: 18))
                            .foregroundStyle(isSelected ? .white : BankTheme.ink)
                            .frame(width: 48, height: 48)
                            .background(isSelected ? BankTheme.ink : BankTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .cardShadow(radius: 12, y: 4, opacity: 0.06)
                        Text(category.title).font(BankFont.caption(11, bold: true)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }

        VStack(spacing: 0) {
            ForEach(viewModel.filteredBillers) { biller in
                Button { viewModel.pay(biller) } label: {
                    HStack(spacing: 12) {
                        IconTile(content: .monogram(biller.monogram), size: 40, fill: BankTheme.porcelain)
                        Text(verbatim: biller.name).font(BankFont.body(15, bold: true)).foregroundStyle(BankTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(BankTheme.secondaryText)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bills.biller.\(biller.code)")
            }
        }
        .padding(.horizontal, 16)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .cardShadow()
    }
}

struct SavedBillRow: View {
    let bill: SavedBill

    var body: some View {
        HStack(spacing: 12) {
            IconTile(
                content: .symbol(bill.biller.category?.symbol ?? "doc.text"),
                size: 40,
                tint: bill.paid ? BankTheme.secondaryText : BankTheme.caution,
                fill: bill.paid ? BankTheme.porcelain : BankTheme.cautionTint
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: bill.displayName).font(BankFont.body(15, bold: true)).foregroundStyle(BankTheme.ink)
                Group {
                    if bill.paid {
                        Text("bills.paid")
                    } else if let due = bill.dueDate {
                        Text("bills.dueOn \(due.formatted(.dateTime.day().month(.abbreviated)))")
                    }
                }
                .font(BankFont.caption(12, bold: !bill.paid))
                .foregroundStyle(bill.paid ? BankTheme.secondaryText : BankTheme.caution)
            }
            Spacer()
            Text(verbatim: bill.amountDue.map { BankFormatter.currencyParts($0).main } ?? "—")
                .font(BankFont.body(15, bold: true))
                .monospacedDigit()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// S14 — reference, amount due and pay.
struct BillPayView: View {
    @State var viewModel: BillPayViewModel
    let onPriced: (PaymentInquiry) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                dueCard
                VStack(alignment: .leading, spacing: 14) {
                    if !viewModel.isSaved {
                        LabeledInput(title: LocalizedStringKey(viewModel.biller?.ref1Label ?? "")) {
                            TextField("", text: $viewModel.ref1)
                                .keyboardType(.numberPad)
                                .font(BankFont.body(17, bold: true))
                                .onChange(of: viewModel.ref1) { _, value in
                                    let digits = String(value.filter(\.isNumber).prefix(20))
                                    if digits != value { viewModel.ref1 = digits }
                                    viewModel.editedReference()
                                }
                                .accessibilityIdentifier("bill.ref1")
                        }
                        if let ref2Label = viewModel.biller?.ref2Label {
                            LabeledInput(title: LocalizedStringKey(ref2Label), isActive: false) {
                                TextField("", text: $viewModel.ref2).keyboardType(.numberPad).font(BankFont.body(17))
                            }
                        }
                    }
                    if viewModel.isTopUp {
                        LabeledInput(title: "bill.amount") {
                            TextField("0.00", text: $viewModel.amountText)
                                .keyboardType(.decimalPad)
                                .font(BankFont.body(17, bold: true))
                                .onChange(of: viewModel.amountText) { _, new in
                                    let filtered = new.reduce("") { PaymentRules.append($1, to: $0) }
                                    if filtered != new { viewModel.amountText = filtered }
                                }
                                .accessibilityIdentifier("bill.amount")
                        }
                    }
                    if let customer = viewModel.inquiry?.bill?.customerName {
                        row("bill.customer") { Text(verbatim: customer) }
                    }
                    row("bill.payFrom") {
                        Menu {
                            ForEach(viewModel.accounts) { account in
                                Button(account.name) { viewModel.setFromAccount(account) }
                            }
                        } label: {
                            Text(verbatim: viewModel.fromAccount.map { "\($0.name) · \($0.maskedNumber.suffix(4))" } ?? "")
                                .font(BankFont.caption(13, bold: true))
                                .foregroundStyle(BankTheme.accent)
                        }
                    }
                    InlineError(message: viewModel.error)
                }
                .surfaceCard(radius: 24, padding: 18)
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(verbatim: viewModel.title).font(BankFont.headline(16)).lineLimit(1)
                    if viewModel.isSaved, let name = viewModel.biller?.name {
                        Text(verbatim: name).font(BankFont.caption(11)).foregroundStyle(BankTheme.secondaryText)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction(
                title: buttonTitle, isEnabled: viewModel.inquiry != nil || viewModel.canCheck, isLoading: viewModel.isLoading, identifier: "bill.submit"
            ) {
                Task {
                    if let inquiry = viewModel.inquiry {
                        onPriced(inquiry)
                    } else if let priced = await viewModel.check(), viewModel.isTopUp {
                        onPriced(priced)
                    }
                }
            }
        }
        .task {
            await viewModel.prepare()
            if viewModel.isSaved || (!viewModel.ref1.isEmpty && !viewModel.isTopUp) { _ = await viewModel.check() }
        }
    }

    private var buttonTitle: LocalizedStringKey {
        if let inquiry = viewModel.inquiry { return "bill.pay \(BankFormatter.currency(inquiry.amount))" }
        return viewModel.isTopUp ? "common.next" : "bill.check"
    }

    @ViewBuilder
    private var dueCard: some View {
        if let inquiry = viewModel.inquiry, !viewModel.isTopUp {
            VStack(spacing: 6) {
                IconTile(content: .monogram(viewModel.biller?.monogram ?? ""), size: 48, fill: BankTheme.cautionTint)
                Text("bill.amountDue").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
                MoneyText(amount: inquiry.amount, size: 40).accessibilityIdentifier("bill.due")
                if let due = inquiry.bill?.dueDate {
                    Text("bills.dueOn \(due.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(BankFont.caption(12, bold: true))
                        .foregroundStyle(BankTheme.caution)
                }
            }
            .frame(maxWidth: .infinity)
            .surfaceCard(radius: 26, padding: 20)
        }
    }

    private func row<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(title).font(BankFont.body(14)).foregroundStyle(BankTheme.secondaryText)
            Spacer()
            value().font(BankFont.body(14, bold: true))
        }
        .frame(minHeight: 40)
    }
}
