import SwiftUI

/// Porcelain background with the soft blue light leak in the top-left corner.
struct BankBackground: View {
    var body: some View {
        ZStack {
            BankTheme.porcelain
            RadialGradient(
                colors: [BankTheme.glow.opacity(0.45), BankTheme.glow.opacity(0)],
                center: UnitPoint(x: 0.1, y: -0.05),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

struct CardShadow: ViewModifier {
    var radius: CGFloat = 30
    var y: CGFloat = 10
    var opacity: Double = 0.07

    func body(content: Content) -> some View {
        content.shadow(color: BankTheme.shadow.opacity(opacity), radius: radius / 2, x: 0, y: y)
    }
}

extension View {
    func cardShadow(radius: CGFloat = 30, y: CGFloat = 10, opacity: Double = 0.07) -> some View {
        modifier(CardShadow(radius: radius, y: y, opacity: opacity))
    }

    /// White card surface used across the app.
    func surfaceCard(radius: CGFloat = BankTheme.Radius.card, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .cardShadow()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    /// Disabled state is a solid grey so nothing behind the button shows through.
    private struct PrimaryButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(BankFont.body(16, bold: true))
                .foregroundStyle(isEnabled ? Color.white : BankTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    isEnabled ? BankTheme.ink : Color(hex: 0xDDE1E8),
                    in: RoundedRectangle(cornerRadius: BankTheme.Radius.button, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BankFont.body(15, bold: true))
            .foregroundStyle(BankTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.button, style: .continuous))
            .cardShadow(radius: 14, y: 4, opacity: 0.08)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Rounded square that holds a monogram or an SF Symbol.
struct IconTile: View {
    enum Content {
        case symbol(String)
        case monogram(String)
    }

    let content: Content
    var size: CGFloat = 44
    var tint: Color = BankTheme.ink
    var fill: Color = BankTheme.surface

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                switch content {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(tint)
                case .monogram(let text):
                    Text(text)
                        .font(BankFont.caption(12, bold: true))
                        .foregroundStyle(tint)
                }
            }
            .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(BankFont.headline(18))
                .foregroundStyle(BankTheme.ink)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(BankFont.caption(13, bold: true))
                    .foregroundStyle(BankTheme.accent)
                    .frame(minHeight: 44)
            }
        }
    }
}

/// Money amount with a dimmed satang part, e.g. ฿4,825,450 + .75
struct MoneyText: View {
    let amount: Decimal
    var size: CGFloat = 44
    var hidden = false
    /// What the amount is, e.g. "Total balance"; VoiceOver reads it before the amount.
    var label: LocalizedStringKey?

    var body: some View {
        let parts = BankFormatter.currencyParts(amount)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(hidden ? "฿ ••••••" : parts.main)
                .font(BankFont.figure(size))
                .foregroundStyle(BankTheme.ink)
            if !hidden {
                Text(parts.fraction)
                    .font(BankFont.figure(size * 0.5))
                    .foregroundStyle(BankTheme.fractionText)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { Text($0) } ?? amountText)
        .accessibilityValue(label == nil ? Text(verbatim: "") : amountText)
    }

    private var amountText: Text {
        hidden ? Text("balance.hidden") : Text(BankFormatter.currency(amount))
    }
}
