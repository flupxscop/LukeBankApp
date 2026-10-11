import SwiftUI
import UniformTypeIdentifiers

/// S18 — transaction detail with editable category and memo (TXN-04, TXN-05).
struct TransactionDetailView: View {
    @State var viewModel: TransactionDetailViewModel
    @State private var isEditingMemo = false
    @State private var memoDraft = ""
    @State private var copied = false

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, BankTheme.Spacing.screen)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("detail.title").font(BankFont.headline(17))
            }
        }
        .accessibilityIdentifier("transactionDetail")
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .alert("detail.memo.edit", isPresented: $isEditingMemo) {
            TextField("detail.memo.placeholder", text: $memoDraft)
            Button("common.cancel", role: .cancel) {}
            Button("common.save") { Task { await viewModel.saveMemo(memoDraft) } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView().padding(.top, -40)
        case .failed:
            ErrorStateView { Task { await viewModel.retry() } }.padding(.top, -40)
        case .loaded(let detail):
            loaded(detail)
        }
    }

    private func loaded(_ detail: TransactionDetail) -> some View {
        let transaction = detail.transaction
        return VStack(spacing: 24) {
            VStack(spacing: 10) {
                IconTile(
                    content: transaction.monogram.map(IconTile.Content.monogram) ?? .symbol(transaction.category.symbol),
                    size: 64
                )
                .cardShadow(radius: 24, y: 10, opacity: 0.12)
                Text(transaction.merchant)
                    .font(BankFont.body(15))
                    .foregroundStyle(BankTheme.secondaryText)
                    .multilineTextAlignment(.center)
                amount(transaction.amount)
                statusPill(isPosted: detail.isPosted)
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                row("detail.date") { Text(verbatim: BankFormatter.dateTime(transaction.date)).monospacedDigit() }
                divider
                row("detail.channel") { Text(transaction.channel.title) }
                divider
                row(transaction.isIncome ? "detail.toAccount" : "detail.fromAccount") {
                    Text(verbatim: detail.accountName + " · " + detail.accountMaskedNumber.suffix(4))
                }
                divider
                row("detail.category") { categoryControl(transaction.category) }
                divider
                row("detail.memo") { memoControl(transaction.memo) }
                divider
                row("detail.reference") { referenceControl(detail.referenceNo) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .cardShadow()

            if viewModel.saveFailed {
                Text("detail.saveFailed")
                    .font(BankFont.caption(13))
                    .foregroundStyle(BankTheme.negative)
            }
        }
    }

    private func amount(_ value: Decimal) -> some View {
        let parts = BankFormatter.currencyParts(abs(value))
        let sign = value < 0 ? "−" : "+"
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: sign + parts.main.dropFirst())
                .font(BankFont.figure(42))
                .foregroundStyle(value < 0 ? BankTheme.ink : BankTheme.positive)
            Text(verbatim: parts.fraction)
                .font(BankFont.figure(22))
                .foregroundStyle(BankTheme.fractionText)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: BankFormatter.signedAmount(value)))
    }

    private func statusPill(isPosted: Bool) -> some View {
        Label(isPosted ? "detail.status.posted" : "detail.status.pending", systemImage: isPosted ? "checkmark" : "clock")
            .font(BankFont.caption(13, bold: true))
            .foregroundStyle(isPosted ? BankTheme.positive : BankTheme.caution)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isPosted ? BankTheme.positiveTint : BankTheme.cautionTint, in: Capsule())
    }

    private var divider: some View {
        Rectangle().fill(BankTheme.line).frame(height: 1)
    }

    private func row<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(BankFont.body(14))
                .foregroundStyle(BankTheme.secondaryText)
            Spacer(minLength: 8)
            value()
                .font(BankFont.body(14, bold: true))
                .foregroundStyle(BankTheme.ink)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func categoryControl(_ category: TransactionCategory) -> some View {
        if viewModel.canChangeCategory {
            Menu {
                ForEach(TransactionCategory.assignable) { option in
                    Button {
                        Task { await viewModel.changeCategory(option) }
                    } label: {
                        Label { Text(option.title) } icon: { Image(systemName: option == category ? "checkmark" : option.symbol) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(category.title)
                    if viewModel.isSaving { ProgressView().controlSize(.mini) } else { Image(systemName: "pencil").font(.system(size: 11, weight: .bold)) }
                }
                .font(BankFont.caption(13, bold: true))
                .foregroundStyle(BankTheme.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(BankTheme.accentTint, in: Capsule())
            }
            .accessibilityIdentifier("detail.category")
        } else {
            Text(category.title)
        }
    }

    private func memoControl(_ memo: String?) -> some View {
        Button {
            memoDraft = memo ?? ""
            isEditingMemo = true
        } label: {
            HStack(spacing: 6) {
                if let memo { Text(verbatim: memo) } else { Text("detail.memo.add").foregroundStyle(BankTheme.accent) }
                Image(systemName: "square.and.pencil").font(.system(size: 12)).foregroundStyle(BankTheme.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.memo")
    }

    private func referenceControl(_ reference: String) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: reference).monospaced().font(BankFont.caption(13, bold: true))
            Button {
                // Local-only and short-lived: a reference is not secret, but nothing banking-related should sync to other devices.
                UIPasteboard.general.setItems(
                    [[UTType.plainText.identifier: reference]],
                    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
                )
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15))
                    .foregroundStyle(BankTheme.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(copied ? "detail.copied" : "detail.copyReference"))
        }
    }
}

#Preview {
    NavigationStack {
        TransactionDetailView(
            viewModel: TransactionDetailViewModel(transactionID: MockBankData.transactions()[1].id, repository: MockBankRepository())
        )
    }
}
