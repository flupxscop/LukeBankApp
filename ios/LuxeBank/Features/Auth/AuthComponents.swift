import SwiftUI

/// Back button + three-step progress used on the onboarding screens.
struct OnboardingHeader: View {
    let step: Int
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BankTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(BankTheme.surface, in: Circle())
                        .cardShadow(radius: 14, y: 4, opacity: 0.1)
                }
                .accessibilityLabel(Text("common.back"))
            }
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? BankTheme.ink : Color(hex: 0xDDE1E8))
                        .frame(height: 5)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("onboarding.step \(step)"))
            Text(verbatim: "\(step)/3")
                .font(BankFont.caption(13, bold: true))
                .foregroundStyle(BankTheme.secondaryText)
        }
    }
}

struct PinDots: View {
    let filled: Int
    var isError = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(isError ? BankTheme.negative : (index < filled ? BankTheme.ink : Color(hex: 0xDDE1E8)))
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 22)
        .background(isError ? BankTheme.negativeTint : BankTheme.surface, in: Capsule())
        .cardShadow(radius: 16, y: 6, opacity: 0.07)
        .accessibilityElement()
        .accessibilityLabel(Text("pin.progress \(filled)"))
        .accessibilityIdentifier("pin.dots")
    }
}

/// Numeric keypad with white floating keys. `leading` fills the empty bottom-left slot.
struct PinPad<Leading: View>: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 22), count: 3)
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(1...9, id: \.self) { digit in key(digit) }
            leading.frame(height: 70)
            key(0)
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(BankTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 70)
            }
            .accessibilityLabel(Text("pin.delete"))
        }
        .padding(.horizontal, 18)
    }

    private func key(_ digit: Int) -> some View {
        Button { onDigit(digit) } label: {
            Text(verbatim: "\(digit)")
                .font(BankFont.headline(28))
                .foregroundStyle(BankTheme.ink)
                .frame(width: 70, height: 70)
                .background(BankTheme.surface, in: Circle())
                .cardShadow(radius: 16, y: 6, opacity: 0.08)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pinpad.\(digit)")
    }
}

extension PinPad where Leading == Color {
    init(onDigit: @escaping (Int) -> Void, onDelete: @escaping () -> Void) {
        self.init(onDigit: onDigit, onDelete: onDelete) { Color.clear }
    }
}

struct InlineError: View {
    let message: LocalizedStringResource?

    var body: some View {
        if let message {
            Text(message)
                .font(BankFont.caption(13, bold: true))
                .foregroundStyle(BankTheme.negative)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isStaticText)
                .transition(.opacity)
        }
    }
}
