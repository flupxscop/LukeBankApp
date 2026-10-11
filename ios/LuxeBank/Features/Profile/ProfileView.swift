import SwiftUI

/// Screens pushed from the profile tab.
enum ProfileRoute: Hashable {
    case settings
    case inbox
    case privileges
    case info(InfoPage)
}

/// S19 — who the customer is, their relationship manager and the way into settings (PROF-01, PROF-07, PROF-09).
struct ProfileView: View {
    @State var viewModel: ProfileViewModel
    @Binding var path: [ProfileRoute]
    let makeInbox: () -> InboxViewModel
    @State private var isChatting = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ProfileRoute.self) { route in
                    destination(route).toolbar(.hidden, for: .navigationBar)
                }
        }
        .tint(BankTheme.ink)
        .sheet(isPresented: $isChatting) {
            if let manager = viewModel.profile?.relationshipManager {
                RMChatView(manager: manager)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let profile = viewModel.profile {
            ScrollView {
                VStack(spacing: 18) {
                    header(profile)
                    if let manager = profile.relationshipManager { managerCard(manager) }
                    menu(profile)
                    footer
                }
                .padding(.horizontal, BankTheme.Spacing.screen)
                .padding(.top, 12)
                .padding(.bottom, BankTheme.Spacing.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .background(BankBackground())
            .refreshable { await viewModel.load() }
        } else if viewModel.failed {
            ErrorStateView { Task { await viewModel.load() } }
                .padding(.horizontal, BankTheme.Spacing.screen)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(BankBackground())
        } else {
            LoadingStateView()
                .padding(.horizontal, BankTheme.Spacing.screen)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(BankBackground())
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private func destination(_ route: ProfileRoute) -> some View {
        switch route {
        case .settings:
            SettingsView(viewModel: viewModel) { path.removeLast() }
        case .inbox:
            InboxView(viewModel: makeInbox()) { path.removeLast() }
        case .privileges:
            PrivilegesView(tier: viewModel.profile?.tier ?? "") { path.removeLast() }
        case .info(let page):
            InfoView(page: page) { path.removeLast() }
        }
    }

    private func header(_ profile: BankProfile) -> some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button { path.append(.settings) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BankTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(BankTheme.surface, in: Circle())
                        .cardShadow(radius: 14, y: 4, opacity: 0.08)
                }
                .accessibilityLabel(Text("settings.title"))
                .accessibilityIdentifier("profile.settings")
            }
            Circle()
                .fill(AngularGradient(colors: [BankTheme.glow, .white, Color(hex: 0xB7BDC9), BankTheme.glow], center: .center))
                .frame(width: 92, height: 92)
                .overlay {
                    Circle().fill(.white).padding(3)
                    Text(verbatim: String(profile.firstName.prefix(1))).font(BankFont.title(34)).foregroundStyle(BankTheme.ink)
                }
                .cardShadow(radius: 22, y: 8, opacity: 0.12)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("profile.greeting \(profile.firstName)")
                    .font(BankFont.title(26))
                    .accessibilityIdentifier("profile.name")
                Text("profile.member \(profile.tier)")
                    .font(BankFont.caption(11, bold: true))
                    .tracking(1.5)
                    .foregroundStyle(BankTheme.caution)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(BankTheme.cautionTint, in: Capsule())
            }
        }
    }

    private func managerCard(_ manager: RelationshipManager) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(verbatim: String(manager.name.prefix(1))).font(BankFont.headline(18)).foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("profile.rm").font(BankFont.caption(12)).foregroundStyle(.white.opacity(0.65))
                    Text(verbatim: manager.name).font(BankFont.headline(17)).foregroundStyle(.white)
                    Text(verbatim: manager.hours).font(BankFont.caption(12)).foregroundStyle(.white.opacity(0.65))
                }
            }
            HStack(spacing: 10) {
                managerButton("profile.rm.call", symbol: "phone.fill", identifier: "profile.rm.call") {
                    if let url = URL(string: "tel:\(manager.phone)") { openURL(url) }
                }
                managerButton("profile.rm.chat", symbol: "bubble.left.fill", identifier: "profile.rm.chat") { isChatting = true }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                BankTheme.ink
                Circle()
                    .fill(RadialGradient(colors: [BankTheme.glow.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 110))
                    .frame(width: 220, height: 220)
                    .offset(x: 90, y: -90)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
        .cardShadow(radius: 26, y: 10, opacity: 0.18)
    }

    private func managerButton(_ title: LocalizedStringKey, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(BankFont.body(15, bold: true))
                .foregroundStyle(BankTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func menu(_ profile: BankProfile) -> some View {
        VStack(spacing: 0) {
            Button { path.append(.settings) } label: {
                SettingsRow(symbol: "lock.shield", title: "profile.menu.security", subtitle: "profile.menu.security.detail")
            }
            SettingsDivider()
            Button { path.append(.inbox) } label: {
                SettingsRow(symbol: "bell", title: "profile.menu.notifications") {
                    HStack(spacing: 6) {
                        UnreadBadge(count: profile.unreadNotifications)
                        SettingsChevron()
                    }
                }
            }
            .accessibilityIdentifier("profile.inbox")
            SettingsDivider()
            Button { path.append(.settings) } label: {
                SettingsRow(
                    symbol: "globe", title: "profile.menu.language",
                    value: viewModel.language == .english ? "language.english" : "language.thai"
                )
            }
            SettingsDivider()
            Button { path.append(.privileges) } label: {
                SettingsRow(symbol: "crown", title: "profile.menu.privileges", subtitle: "profile.menu.privileges.detail")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
        .cardShadow()
    }

    private var footer: some View {
        HStack(spacing: 16) {
            ForEach(InfoPage.allCases, id: \.self) { page in
                Button { path.append(.info(page)) } label: {
                    Text(page.title).font(BankFont.caption(12, bold: true)).foregroundStyle(BankTheme.secondaryText)
                }
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
