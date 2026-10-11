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
    @State private var dashboardViewModel: DashboardViewModel
    @State private var historyViewModel: HistoryViewModel?
    @State private var paymentsViewModel: PaymentsViewModel
    @State private var cardsViewModel: CardsViewModel
    @State private var flow: PaymentFlow?
    private let repository: BankRepository
    private let payments: PaymentRepository
    private let authorizer: PaymentAuthorizing

    init(environment: AppEnvironment, session: SessionManager) {
        let repository = environment.makeBankRepository(session: session)
        let payments = environment.makePaymentRepository(session: session)
        self.repository = repository
        self.payments = payments
        authorizer = DevicePaymentAuthorizer(keys: environment.keyManager, session: session)
        _dashboardViewModel = State(initialValue: DashboardViewModel(repository: repository))
        _paymentsViewModel = State(initialValue: PaymentsViewModel(repository: payments))
        _cardsViewModel = State(initialValue: CardsViewModel(repository: environment.makeCardRepository(session: session)))
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
                        flow = .bills(nil, BillTarget(cardID: card.id, cardName: "\(card.productName) · \(card.last4)"))
                    }
                case .payments: PaymentsView(viewModel: paymentsViewModel) { flow = $0 }
                case .profile: ProfileView()
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
        .animation(.easeInOut(duration: 0.2), value: isAtRoot)
        .fullScreenCover(item: $flow) { flow in
            paymentFlow(flow)
        }
    }

    private var isAtRoot: Bool {
        switch selectedTab {
        case .home: homePath.isEmpty
        case .cards: cardPath.isEmpty
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
                onQuickAction: start
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
        case .transfer: flow = .transfer(nil)
        case .scan: flow = .scan
        case .payBill: flow = .bills(nil, nil)
        case .topUp: flow = .bills(.mobile, nil)
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
        }
    }
}

#Preview {
    ContentView(environment: .mock, session: AppEnvironment.mock.makeSessionManager())
}
