import SwiftUI

/// Hairline between settings rows, starting after the icon.
struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(BankTheme.line).padding(.leading, 54)
    }
}

/// A titled white card holding settings rows; put a `SettingsDivider` between rows.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BankFont.caption(13, bold: true))
                .foregroundStyle(BankTheme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
            .cardShadow()
        }
    }
}

/// Icon, title, optional subtitle and whatever sits on the trailing side.
struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var tint: Color = BankTheme.ink
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(content: .symbol(symbol), size: 40, tint: tint, fill: BankTheme.surfaceSunken)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BankFont.body(15, bold: true)).foregroundStyle(BankTheme.ink)
                if let subtitle {
                    Text(subtitle).font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == SettingsChevron {
    init(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, value: LocalizedStringKey? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { SettingsChevron(value: value) }
    }
}

struct SettingsChevron: View {
    var value: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 6) {
            if let value {
                Text(value).font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BankTheme.fractionText)
                .accessibilityHidden(true)
        }
    }
}

/// Red count badge for unread notifications.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count >= 1 {
            Text(verbatim: count > 99 ? "99+" : "\(count)")
                .font(BankFont.caption(11, bold: true))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(BankTheme.negative, in: Capsule())
                .accessibilityLabel(Text("inbox.unread \(count)"))
        }
    }
}

/// Round back button used on pushed profile screens.
struct CircleBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BankTheme.ink)
                .frame(width: 44, height: 44)
                .background(BankTheme.surface, in: Circle())
                .cardShadow(radius: 14, y: 4, opacity: 0.1)
        }
        .accessibilityLabel(Text("common.back"))
    }
}

/// Title bar of a pushed screen: back button, centred title, optional trailing action.
struct PushedHeader<Trailing: View>: View {
    let title: LocalizedStringResource
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            CircleBackButton(action: onBack)
            Spacer()
            Text(title).font(BankFont.headline(17)).accessibilityAddTraits(.isHeader)
            Spacer()
            trailing.frame(minWidth: 44, minHeight: 44)
        }
    }
}

extension PushedHeader where Trailing == Color {
    init(title: LocalizedStringResource, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack) { Color.clear }
    }
}
