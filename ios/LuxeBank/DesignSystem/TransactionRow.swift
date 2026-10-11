import SwiftUI

/// Merchant, category and amount; used by the home screen and the history list.
struct TransactionRow: View {
    enum Style {
        /// Home screen: shadowed white tile on the porcelain background.
        case floating
        /// Inside a white card: flat porcelain tile.
        case inset
    }

    let transaction: Transaction
    let subtitle: String
    var style: Style = .floating

    var body: some View {
        HStack(spacing: style == .floating ? 14 : 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .font(BankFont.body(15, bold: true))
                    .foregroundStyle(BankTheme.ink)
                    .lineLimit(1)
                (Text(transaction.category.title) + Text(verbatim: " · " + subtitle))
                    .font(BankFont.caption(12))
                    .foregroundStyle(BankTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(BankFormatter.signedAmount(transaction.amount))
                .font(BankFont.body(15, bold: true))
                .monospacedDigit()
                .foregroundStyle(transaction.isIncome ? BankTheme.positive : BankTheme.ink)
        }
        .padding(.vertical, style == .floating ? 8 : 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tile: some View {
        let content = transaction.monogram.map(IconTile.Content.monogram) ?? .symbol(transaction.category.symbol)
        switch style {
        case .floating:
            IconTile(content: content, size: 44).cardShadow(radius: 12, y: 4, opacity: 0.08)
        case .inset:
            IconTile(
                content: content,
                size: 42,
                tint: transaction.category == .transfer ? BankTheme.accent : BankTheme.ink,
                fill: transaction.category == .transfer ? BankTheme.accentTint : BankTheme.porcelain
            )
        }
    }
}

/// Rounded filter pill from the history design; dark when selected.
struct FilterChip<Label: View>: View {
    let isSelected: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .font(BankFont.caption(13, bold: true))
            .foregroundStyle(isSelected ? .white : BankTheme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isSelected ? BankTheme.ink : BankTheme.surface, in: Capsule())
            .contentShape(Capsule())
    }
}

/// Empty result with an optional action (spec 10.4).
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            IconTile(content: .symbol("doc.text"), size: 56, tint: BankTheme.secondaryText, fill: BankTheme.porcelain)
            Text(title)
                .font(BankFont.headline(16))
            Text(message)
                .font(BankFont.caption(13))
                .foregroundStyle(BankTheme.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(BankFont.body(14, bold: true))
                    .foregroundStyle(BankTheme.accent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(BankTheme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 26)
    }
}
