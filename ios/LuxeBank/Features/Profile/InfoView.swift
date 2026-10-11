import SwiftUI

/// PROF-09 — help, privacy (PDPA) and terms. Static copy in the simulation; a real bank would load
/// versioned documents and record consent.
enum InfoPage: String, CaseIterable, Hashable {
    case help
    case privacy
    case terms

    var title: LocalizedStringResource {
        switch self {
        case .help: "info.help"
        case .privacy: "info.privacy"
        case .terms: "info.terms"
        }
    }

    fileprivate var sections: [(LocalizedStringResource, LocalizedStringResource)] {
        switch self {
        case .help:
            [("info.help.lost", "info.help.lost.body"), ("info.help.fraud", "info.help.fraud.body"), ("info.help.contact", "info.help.contact.body")]
        case .privacy:
            [
                ("info.privacy.collect", "info.privacy.collect.body"),
                ("info.privacy.use", "info.privacy.use.body"),
                ("info.privacy.rights", "info.privacy.rights.body"),
            ]
        case .terms:
            [("info.terms.device", "info.terms.device.body"), ("info.terms.limits", "info.terms.limits.body")]
        }
    }
}

struct InfoView: View {
    let page: InfoPage
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PushedHeader(title: page.title, onBack: onBack)
                Text("info.simulation")
                    .font(BankFont.caption(12))
                    .foregroundStyle(BankTheme.caution)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BankTheme.cautionTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.0).font(BankFont.headline(16)).accessibilityAddTraits(.isHeader)
                        Text(section.1).font(BankFont.body(14)).foregroundStyle(BankTheme.secondaryText)
                    }
                    .surfaceCard(padding: 18)
                }
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BankBackground())
    }
}

/// Member privileges by tier (S19 menu). Static in the simulation.
struct PrivilegesView: View {
    let tier: String
    let onBack: () -> Void

    private struct Perk {
        let symbol: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
    }

    private let perks = [
        Perk(symbol: "fork.knife", title: "privileges.dining", detail: "privileges.dining.body"),
        Perk(symbol: "airplane", title: "privileges.lounge", detail: "privileges.lounge.body"),
        Perk(symbol: "arrow.left.arrow.right", title: "privileges.fx", detail: "privileges.fx.body"),
        Perk(symbol: "person.badge.shield.checkmark", title: "privileges.rm", detail: "privileges.rm.body"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PushedHeader(title: "profile.menu.privileges", onBack: onBack)
                Text("profile.member \(tier)")
                    .font(BankFont.caption(12, bold: true))
                    .tracking(1.5)
                    .foregroundStyle(BankTheme.caution)
                VStack(spacing: 0) {
                    ForEach(Array(perks.enumerated()), id: \.offset) { index, perk in
                        if index > 0 { SettingsDivider() }
                        HStack(alignment: .top, spacing: 14) {
                            IconTile(content: .symbol(perk.symbol), size: 40, tint: BankTheme.caution, fill: BankTheme.cautionTint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perk.title).font(BankFont.body(15, bold: true))
                                Text(perk.detail).font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
                .cardShadow()
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BankBackground())
    }
}
