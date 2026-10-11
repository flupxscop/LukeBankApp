import SwiftUI

/// "จากบัญชีหลัก · 4289  ฿4,825,450.75" with a menu to pick another account.
struct SourceAccountCard: View {
    let accounts: [Account]
    let selected: Account?
    let onSelect: (Account) -> Void

    var body: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    onSelect(account)
                } label: {
                    Text(verbatim: "\(account.name) · \(account.maskedNumber.suffix(4))")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: "LX")
                    .font(BankFont.caption(10, bold: true))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(BankTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    if let selected {
                        Text("transfer.from \(selected.name) \(String(selected.maskedNumber.suffix(4)))")
                            .font(BankFont.caption(12))
                            .foregroundStyle(BankTheme.secondaryText)
                        Text(verbatim: BankFormatter.currency(selected.balance))
                            .font(BankFont.body(16, bold: true))
                            .monospacedDigit()
                            .foregroundStyle(BankTheme.ink)
                    } else {
                        ProgressView()
                    }
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BankTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(BankTheme.silver, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white, lineWidth: 1))
            .cardShadow(radius: 22, y: 8, opacity: 0.08)
        }
        .accessibilityIdentifier("transfer.from")
    }
}

/// Four-way segmented control from the recipient design.
struct SegmentedTabs<Item: Hashable>: View {
    let items: [Item]
    let selection: Item
    let title: (Item) -> LocalizedStringResource
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button { onSelect(item) } label: {
                    Text(title(item))
                        .font(BankFont.caption(13, bold: true))
                        .foregroundStyle(isSelected ? BankTheme.ink : BankTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(BankTheme.surface)
                                    .cardShadow(radius: 8, y: 2, opacity: 0.12)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(BankTheme.segmentTrack, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Title above a white input with the focused blue ring.
struct LabeledInput<Content: View>: View {
    let title: LocalizedStringKey
    var isActive = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BankFont.caption(13, bold: true))
                .foregroundStyle(isActive ? BankTheme.accent : Color(hex: 0x3A404C))
            content()
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.field, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BankTheme.Radius.field, style: .continuous)
                        .stroke(isActive ? BankTheme.accent : BankTheme.lineStrong, lineWidth: isActive ? 1.5 : 1)
                )
        }
    }
}

/// Calculator keypad for amounts: digits, decimal point and delete (S09).
struct AmountKeypad: View {
    let onKey: (Character) -> Void
    let onDelete: () -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array("123456789.0"), id: \.self) { key in
                Button { onKey(key) } label: {
                    Text(String(key))
                        .font(BankFont.headline(24))
                        .foregroundStyle(BankTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("amount.\(key == "." ? "dot" : String(key))")
            }
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.system(size: 22))
                    .foregroundStyle(BankTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .accessibilityLabel(Text("pin.delete"))
        }
    }
}

/// Initial in a round tile; used for payees.
struct PayeeAvatar: View {
    let payee: Payee
    var size: CGFloat = 54

    var body: some View {
        let colors = palette
        Text(verbatim: payee.initial)
            .font(BankFont.headline(size * 0.33))
            .foregroundStyle(colors.foreground)
            .frame(width: size, height: size)
            .background(colors.background, in: Circle())
            .accessibilityHidden(true)
    }

    private var palette: (foreground: Color, background: Color) {
        switch payee.kind {
        case .promptPay: (BankTheme.positive, BankTheme.positiveTint)
        case .luxeBank: (BankTheme.accent, BankTheme.accentTint)
        default: (BankTheme.ink, BankTheme.porcelain)
        }
    }
}

/// Bottom call to action pinned above the keyboard / home indicator.
struct BottomAction: View {
    let title: LocalizedStringKey
    var isEnabled = true
    var isLoading = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityIdentifier(identifier ?? "")
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(BankTheme.porcelain.opacity(0.95))
    }
}
