import SwiftUI

/// Full-screen transfer flow: S08 → S09 → S10 → S11 (spec 10.2).
struct TransferFlowView: View {
    @State var viewModel: TransferViewModel
    let authorizer: PaymentAuthorizing
    let onClose: (_ completed: Bool) -> Void
    var onScan: (() -> Void)?

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            TransferRecipientView(viewModel: viewModel, onClose: { onClose(false) }, onScan: onScan)
                .navigationDestination(for: TransferViewModel.Step.self) { step in
                    switch step {
                    case .amount:
                        TransferAmountView(viewModel: viewModel)
                    case .confirm(let inquiry):
                        PaymentConfirmView(
                            viewModel: PaymentConfirmViewModel(inquiry: inquiry, authorizer: authorizer, saveByDefault: false) { [viewModel] in
                                try await viewModel.confirmInquiry(inquiry, authorization: $0, key: $1, save: $2)
                            },
                            onSlip: viewModel.showSlip,
                            onExpired: viewModel.restartFromAmount
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

/// S08 — choose who to pay.
struct TransferRecipientView: View {
    @Bindable var viewModel: TransferViewModel
    let onClose: () -> Void
    var onScan: (() -> Void)?
    @State private var isInputFocused = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SourceAccountCard(accounts: viewModel.accounts, selected: viewModel.fromAccount) { account in
                    Task { await viewModel.selectFrom(account) }
                }
                SegmentedTabs(items: RecipientKind.transferTabs, selection: viewModel.kind, title: \.title, onSelect: viewModel.setKind)
                    .accessibilityIdentifier("transfer.kind")
                form
                InlineError(message: viewModel.error)
                recents
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("common.close"))
                    .accessibilityIdentifier("transfer.close")
            }
            ToolbarItem(placement: .principal) {
                Text("action.transfer").font(BankFont.headline(17))
            }
            if let onScan {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onScan) { Image(systemName: "qrcode.viewfinder") }
                        .tint(BankTheme.accent)
                        .accessibilityLabel(Text("action.scan"))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction(title: "common.next", isEnabled: viewModel.canContinue, identifier: "transfer.next", action: viewModel.continueToAmount)
        }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch viewModel.kind {
            case .own:
                ownAccounts
            case .luxeBank:
                LabeledInput(title: "transfer.luxeAccount") { accountField(placeholder: "XXX-X-XXXXX-X", maxDigits: 10) }
            case .otherBank:
                LabeledInput(title: "transfer.bank", isActive: false) { bankPicker }
                LabeledInput(title: "transfer.accountNumber") { accountField(placeholder: "XXX-X-XXXXX-X", maxDigits: 12) }
            case .promptPay:
                LabeledInput(title: "transfer.promptPayProxy") {
                    FormattedDigitsField(
                        digits: $viewModel.proxy, maxDigits: 15, placeholder: "08X-XXX-XXXX", format: { $0 },
                        isFocused: $isInputFocused, accessibilityIdentifier: "transfer.proxy"
                    )
                }
                Text("transfer.nameCheckHint")
                    .font(BankFont.caption(12))
                    .foregroundStyle(BankTheme.secondaryText)
            case .bill:
                EmptyView()
            }
        }
        .surfaceCard(radius: 24, padding: 18)
    }

    private func accountField(placeholder: String, maxDigits: Int) -> some View {
        FormattedDigitsField(
            digits: $viewModel.accountNumber, maxDigits: maxDigits, placeholder: placeholder, format: AccountNumberFormat.format,
            isFocused: $isInputFocused, accessibilityIdentifier: "transfer.accountNumber"
        )
    }

    private var bankPicker: some View {
        Menu {
            ForEach(viewModel.banks) { bank in
                Button(bank.name) { viewModel.selectedBank = bank }
            }
        } label: {
            HStack(spacing: 12) {
                if let bank = viewModel.selectedBank {
                    IconTile(content: .monogram(bank.monogram), size: 30, fill: BankTheme.surfaceSunken)
                    Text(verbatim: bank.name).font(BankFont.body(16, bold: true)).foregroundStyle(BankTheme.ink)
                }
                Spacer()
                Image(systemName: "chevron.down").foregroundStyle(BankTheme.secondaryText)
            }
        }
        .accessibilityIdentifier("transfer.bank")
    }

    private var ownAccounts: some View {
        VStack(spacing: 10) {
            if viewModel.otherOwnAccounts.isEmpty {
                Text("transfer.noOtherAccount").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
            }
            ForEach(viewModel.otherOwnAccounts) { account in
                let isSelected = viewModel.ownTarget?.id == account.id
                Button { viewModel.ownTarget = account } label: {
                    HStack(spacing: 12) {
                        IconTile(content: .monogram(String(account.maskedNumber.suffix(4))), size: 40, tint: BankTheme.accent, fill: BankTheme.accentTint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: account.name).font(BankFont.body(15, bold: true))
                            Text(verbatim: BankFormatter.currency(account.balance)).font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? BankTheme.accent : BankTheme.line, lineWidth: isSelected ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var recents: some View {
        if !viewModel.payees.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("transfer.recent")
                    .font(BankFont.caption(13, bold: true))
                    .foregroundStyle(BankTheme.secondaryText)
                    .padding(.horizontal, 4)
                ForEach(viewModel.payees) { payee in
                    Button { viewModel.choose(payee) } label: {
                        HStack(spacing: 12) {
                            PayeeAvatar(payee: payee, size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: payee.displayName).font(BankFont.body(14, bold: true)).foregroundStyle(BankTheme.ink)
                                Text(verbatim: [payee.bankName ?? String(localized: "recipient.promptPay"), payee.account].joined(separator: " · "))
                                    .font(BankFont.caption(11))
                                    .foregroundStyle(BankTheme.secondaryText)
                            }
                            Spacer()
                            if payee.favorite {
                                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(BankTheme.caution)
                            }
                        }
                        .padding(12)
                        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .cardShadow(radius: 14, y: 6, opacity: 0.06)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("transfer.payee")
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await viewModel.removePayee(payee) }
                        } label: {
                            Label("transfer.removePayee", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

/// S09 — amount and note.
struct TransferAmountView: View {
    @Bindable var viewModel: TransferViewModel

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("transfer.amount").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "฿").font(BankFont.headline(28)).foregroundStyle(BankTheme.fractionText)
                    Text(verbatim: displayAmount)
                        .font(BankFont.figure(54))
                        .monospacedDigit()
                        .foregroundStyle(viewModel.amountText.isEmpty ? BankTheme.fractionText : BankTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityIdentifier("transfer.amountValue")
                }
                if let problem = viewModel.amountProblem ?? viewModel.error {
                    Text(problem).font(BankFont.caption(13, bold: true)).foregroundStyle(BankTheme.negative)
                } else if let limits = viewModel.limits {
                    Text("transfer.feeAndLimit \(BankFormatter.currencyParts(limits.remaining).main)")
                        .font(BankFont.caption(13))
                        .foregroundStyle(BankTheme.secondaryText)
                }
            }
            .padding(.top, 20)

            HStack(spacing: 8) {
                ForEach([1_000, 5_000, 10_000], id: \.self) { value in
                    Button { viewModel.add(Decimal(value)) } label: {
                        Text(verbatim: "+" + BankFormatter.currencyParts(Decimal(value)).main.dropFirst())
                            .font(BankFont.caption(13, bold: true))
                            .monospacedDigit()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(BankTheme.surface, in: Capsule())
                            .cardShadow(radius: 12, y: 4, opacity: 0.06)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.needsFaceID {
                Label("transfer.faceIdNote", systemImage: "faceid")
                    .font(BankFont.caption(13, bold: true))
                    .foregroundStyle(Color(hex: 0x24427F))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(BankTheme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                Image(systemName: "pencil").foregroundStyle(BankTheme.secondaryText)
                TextField("transfer.memo", text: $viewModel.memo)
                    .font(BankFont.body(15))
                    .onChange(of: viewModel.memo) { _, memo in
                        if memo.count > 100 { viewModel.memo = String(memo.prefix(100)) }
                    }
                    .accessibilityIdentifier("transfer.memo")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)
            AmountKeypad(onKey: viewModel.key, onDelete: viewModel.deleteKey)
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: viewModel.recipientSummary)
                    .font(BankFont.caption(14, bold: true))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(BankTheme.surface, in: Capsule())
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction(
                title: "transfer.review", isEnabled: viewModel.canReview, isLoading: viewModel.isLoading, identifier: "transfer.review"
            ) {
                Task { await viewModel.review() }
            }
        }
    }

    private var displayAmount: String {
        guard !viewModel.amountText.isEmpty else { return "0" }
        let parts = viewModel.amountText.split(separator: ".", omittingEmptySubsequences: false)
        let whole = BankFormatter.currencyParts(PaymentRules.amount(String(parts[0]))).main.dropFirst()
        return parts.count > 1 ? "\(whole).\(parts[1])" : String(whole)
    }
}
