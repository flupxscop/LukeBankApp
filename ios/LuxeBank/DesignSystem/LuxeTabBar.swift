import SwiftUI

/// Floating glass tab bar; the selected tab expands into an ink pill with its title.
struct LuxeTabBar: View {
    @Binding var selectedTab: BankTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BankTab.allCases) { tab in
                let isSelected = tab == selectedTab
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                        if isSelected {
                            Text(tab.title)
                                .font(BankFont.caption(13, bold: true))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : BankTheme.secondaryText)
                    .frame(maxWidth: isSelected ? .infinity : 64, minHeight: 56)
                    .background {
                        if isSelected {
                            Capsule().fill(BankTheme.ink)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Color.white, lineWidth: 1))
        .cardShadow(radius: 40, y: 20, opacity: 0.16)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        BankBackground()
        LuxeTabBar(selectedTab: .constant(.home))
            .padding(20)
    }
}
