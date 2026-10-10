import SwiftUI

/// Skeleton shown while data loads (spec 10.4).
struct LoadingStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            bar(width: 140, height: 14)
            bar(width: 240, height: 36)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14).fill(BankTheme.line).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 8) {
                        bar(width: 160, height: 11)
                        bar(width: 90, height: 9)
                    }
                }
            }
        }
        .surfaceCard(padding: 20)
        .padding(.top, 60)
        .accessibilityElement()
        .accessibilityLabel(Text("state.loading"))
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2).fill(BankTheme.line).frame(width: width, height: height)
    }
}

struct ErrorStateView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            IconTile(content: .symbol("exclamationmark.circle"), size: 56, tint: BankTheme.negative, fill: BankTheme.negativeTint)
            Text("state.error.title")
                .font(BankFont.headline(16))
            Text("state.error.message")
                .font(BankFont.caption(13))
                .foregroundStyle(BankTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("state.retry", action: onRetry)
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 160)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 26)
        .padding(.top, 60)
    }
}

/// Placeholder for tabs whose features land in later milestones.
struct ComingSoonView: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title)
                .font(BankFont.title(32))
                .padding(.horizontal, 4)
            VStack(spacing: 12) {
                IconTile(content: .symbol(symbol), size: 56, tint: BankTheme.accent, fill: BankTheme.accentTint)
                Text("comingSoon.title")
                    .font(BankFont.headline(16))
                Text(message)
                    .font(BankFont.caption(13))
                    .foregroundStyle(BankTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .surfaceCard(padding: 28)
            Spacer()
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BankBackground())
    }
}
