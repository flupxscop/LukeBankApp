import SwiftUI

/// S01 — first launch. Language follows the per-app language in iOS Settings (PROF-04).
struct WelcomeView: View {
    let resetReason: SessionManager.ResetReason?
    let onStart: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "LUXEBANK")
                    .font(BankFont.caption(14, bold: true))
                    .tracking(4)
                Spacer()
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label { Text("welcome.language") } icon: { Image(systemName: "globe") }
                        .font(BankFont.caption(13, bold: true))
                        .foregroundStyle(BankTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(BankTheme.surface, in: Capsule())
                        .cardShadow(radius: 14, y: 4, opacity: 0.08)
                }
            }

            Spacer()
            TitaniumCardArt()
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                if let resetReason {
                    Text(resetReason == .pinLocked ? "welcome.reset.pinLocked" : "welcome.reset.revoked")
                        .font(BankFont.caption(13, bold: true))
                        .foregroundStyle(BankTheme.caution)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BankTheme.cautionTint, in: RoundedRectangle(cornerRadius: 14))
                }
                (Text("welcome.title.1") + Text(verbatim: "\n") + Text("welcome.title.2").foregroundColor(BankTheme.accent))
                    .font(BankFont.title(34))
                    .foregroundStyle(BankTheme.ink)
                Text("welcome.subtitle")
                    .font(BankFont.body(15))
                    .foregroundStyle(BankTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 28)

            Button(action: onStart) {
                Label { Text("welcome.start") } icon: { Image(systemName: "arrow.right") }
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("welcome.start")

            Text("welcome.terms")
                .font(BankFont.caption(12))
                .foregroundStyle(BankTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(BankBackground())
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

/// Tilted titanium card with a sheen, matching the onboarding artwork.
struct TitaniumCardArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white, lineWidth: 1))
                .frame(width: 250, height: 158)
                .rotationEffect(.degrees(-10))
                .offset(x: -26, y: 34)
                .cardShadow(radius: 40, y: 20, opacity: 0.1)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BankTheme.titanium)
                .overlay {
                    LinearGradient(colors: [.clear, .white.opacity(0.8), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .overlay(alignment: .topLeading) {
                    Text(verbatim: "LUXE").font(BankFont.caption(14, bold: true)).tracking(4).padding(22)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(verbatim: "•••• 8821").font(BankFont.caption(15, bold: true)).foregroundStyle(Color(hex: 0x3A404C)).padding(22)
                }
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white, lineWidth: 1))
                .frame(width: 276, height: 174)
                .rotationEffect(.degrees(5))
                .cardShadow(radius: 70, y: 40, opacity: 0.28)
        }
        .accessibilityHidden(true)
    }
}
