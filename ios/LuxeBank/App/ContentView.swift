import SwiftUI

/// Destinations pushed from the home tab.
enum HomeRoute: Hashable {
    case history
    case transaction(UUID)
}

struct ContentView: View {
    @State private var selectedTab: BankTab = .home
    @State private var homePath: [HomeRoute] = []
    @State private var cardPath: [CardRoute] = []
    @State private var profilePath: [ProfileRoute] = []
    @State private var dashboardViewModel: DashboardViewModel
    @State private var historyViewModel: HistoryViewModel?
    @State private var paymentsViewModel: PaymentsViewModel
    @State private var cardsViewModel: CardsViewModel
    @State private var profileViewModel: ProfileViewModel
    @State private var flow: PaymentFlow?
    @State private var showsIntegrityWarning: Bool
    private let repository: BankRepository
    private let payments: PaymentRepository
    private let authorizer: PaymentAuthorizing
    private let profile: ProfileRepository
    private let push = PushRegistrar.shared
    private let asksForPush: Bool
    private let isDeviceCompromised: Bool
    private let network: NetworkMonitor
    @State private var showsOfflineNotice = false

    init(environment: AppEnvironment, session: SessionManager, arguments: [String] = ProcessInfo.processInfo.arguments) {
        let repository = environment.makeBankRepository(session: session)
        let payments = environment.makePaymentRepository(session: session)
        self.repository = repository
        self.payments = payments
        authorizer = DevicePaymentAuthorizer(keys: environment.keyManager, session: session)
        _dashboardViewModel = State(initialValue: DashboardViewModel(repository: repository))
        _paymentsViewModel = State(initialValue: PaymentsViewModel(repository: payments))
        _cardsViewModel = State(initialValue: CardsViewModel(repository: environment.makeCardRepository(session: session)))
        let profile = environment.makeProfileRepository(session: session)
        self.profile = profile
        _profileViewModel = State(initialValue: ProfileViewModel(repository: profile, security: session, biometrics: environment.biometrics))
        // UI tests skip the system permission alert.
        asksForPush = !arguments.contains("-DisablePushPrompt")
        isDeviceCompromised = environment.integrity.isCompromised
        network = environment.network
        // AUTH-11: told once at launch, and again whenever a payment is attempted.
        _showsIntegrityWarning = State(initialValue: environment.integrity.isCompromised)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Switched manually instead of TabView: the system tab bar still draws
            // behind the custom one on newer iOS even when hidden.
            Group {
                switch selectedTab {
                case .home: home
                case .cards:
                    CardsView(viewModel: cardsViewModel, path: $cardPath, authorizer: authorizer) { card in
                        open(.bills(nil, BillTarget(cardID: card.id, cardName: "\(card.productName) · \(card.last4)")))
                    }
                case .payments: PaymentsView(viewModel: paymentsViewModel) { open($0) }
                case .profile:
                    ProfileView(viewModel: profileViewModel, path: $profilePath) {
                        InboxViewModel(repository: profile) { profileViewModel.setUnread($0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Only on the root screens: pushed screens use the whole height (their bottom actions sit there).
            if isAtRoot {
                LuxeTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, BankTheme.Spacing.screen)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !network.isOnline {
                OfflineBanner(updatedAt: dashboardViewModel.updatedAt)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAtRoot)
        .animation(.easeInOut(duration: 0.2), value: network.isOnline)
        .alert("offline.title", isPresented: $showsOfflineNotice) {
            Button("integrity.understood", role: .cancel) {}
        } message: {
            Text("offline.payments")
        }
        .onChange(of: network.isOnline) { _, online in
            guard online else { return }
            Task {
                await dashboardViewModel.load()
                await profileViewModel.refreshUnread()
            }
        }
        .fullScreenCover(item: $flow) { flow in
            paymentFlow(flow)
        }
        .alert("integrity.title", isPresented: $showsIntegrityWarning) {
            Button("integrity.understood", role: .cancel) {}
        } message: {
            Text("integrity.message")
        }
        .task {
            await profileViewModel.load()
            if asksForPush { await push.requestAuthorization() }
        }
        .task(id: push.token) {
            // NOTI-01: tell the bank where to push; retried on the next launch if it fails.
            if let token = push.token { try? await profile.registerPushToken(token) }
        }
        .onChange(of: push.arrivals) {
            Task {
                await profileViewModel.refreshUnread()
                await dashboardViewModel.load()
            }
        }
    }

    /// Payments are not offered on a compromised phone (AUTH-11); the server refuses them anyway.
    private func open(_ flow: PaymentFlow) {
        if isDeviceCompromised {
            showsIntegrityWarning = true
        } else if !network.isOnline {
            // NFR-08: no transactions without a connection.
            showsOfflineNotice = true
        } else {
            self.flow = flow
        }
    }

    /// The bell on the home screen opens the inbox in the profile tab.
    private func openInbox() {
        profilePath = [.inbox]
        selectedTab = .profile
    }

    private var isAtRoot: Bool {
        switch selectedTab {
        case .home: homePath.isEmpty
        case .cards: cardPath.isEmpty
        case .profile: profilePath.isEmpty
        default: true
        }
    }

    private var home: some View {
        NavigationStack(path: $homePath) {
            DashboardView(
                viewModel: dashboardViewModel,
                onShowHistory: { account in
                    historyViewModel = HistoryViewModel(account: account, repository: repository)
                    homePath.append(.history)
                },
                onSelectTransaction: { homePath.append(.transaction($0.id)) },
                onQuickAction: start,
                unreadCount: profileViewModel.unreadCount,
                onOpenInbox: openInbox
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .history:
                    if let historyViewModel {
                        HistoryView(viewModel: historyViewModel) { homePath.append(.transaction($0.id)) }
                    }
                case .transaction(let id):
                    TransactionDetailView(
                        viewModel: TransactionDetailViewModel(transactionID: id, repository: repository) { updated in
                            historyViewModel?.replace(updated)
                            dashboardViewModel.replace(updated)
                        },
                        loadSlip: { try await payments.slip(transactionID: $0) }
                    )
                }
            }
        }
        .tint(BankTheme.ink)
    }

    @ViewBuilder
    private func paymentFlow(_ flow: PaymentFlow) -> some View {
        switch flow {
        case .transfer(let prefill):
            TransferFlowView(
                viewModel: TransferViewModel(repository: payments, prefill: prefill),
                authorizer: authorizer,
                onClose: finish,
                onScan: { self.flow = .scan }
            )
        case .bills(let category, let target):
            BillFlowView(
                viewModel: BillsViewModel(repository: payments, category: category, target: target),
                authorizer: authorizer,
                onClose: finish,
                onScan: { self.flow = .scan }
            )
        case .scan:
            QRScanView(viewModel: QRScanViewModel(repository: payments), onClose: { self.flow = nil }, onResult: { result in
                switch result.kind {
                case .promptPay:
                    self.flow = .transfer(
                        TransferPrefill(kind: .promptPay, proxy: result.proxy, amount: result.amount, amountLocked: result.amountLocked)
                    )
                case .bill:
                    let target = BillTarget(
                        billerCode: result.billerCode, ref1: result.ref1 ?? "", ref2: result.ref2 ?? "",
                        amount: result.amount, amountLocked: result.amountLocked
                    )
                    self.flow = .bills(nil, target)
                }
            })
        }
    }

    private func start(_ action: QuickAction) {
        switch action {
        case .transfer: open(.transfer(nil))
        case .scan: open(.scan)
        case .payBill: open(.bills(nil, nil))
        case .topUp: open(.bills(.mobile, nil))
        }
    }

    /// Back from a flow; balances and lists changed after a payment.
    private func finish(completed: Bool) {
        flow = nil
        guard completed else { return }
        Task {
            await dashboardViewModel.load()
            await paymentsViewModel.load()
            await cardsViewModel.load()
            await historyViewModel?.reload()
            await profileViewModel.refreshUnread()
        }
    }
}

#Preview {
    ContentView(environment: .mock, session: AppEnvironment.mock.makeSessionManager())
}

/// NFR-08: shown at the top of every tab while there is no connection.
private struct OfflineBanner: View {
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.system(size: 13, weight: .semibold))
            Text("offline.badge").font(BankFont.caption(13, bold: true))
            if let updatedAt {
                Text("offline.updated \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(BankFont.caption(12))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(BankTheme.ink, in: Capsule())
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline.banner")
    }
}
