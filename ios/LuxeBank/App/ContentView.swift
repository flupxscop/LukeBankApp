import SwiftUI

/// Destinations pushed from the home tab.
enum HomeRoute: Hashable {
    case history
    case transaction(UUID)
}

struct ContentView: View {
    @State private var selectedTab: BankTab = .home
    @State private var homePath: [HomeRoute] = []
    @State private var dashboardViewModel: DashboardViewModel
    @State private var historyViewModel: HistoryViewModel?
    private let repository: BankRepository

    init(environment: AppEnvironment, session: SessionManager) {
        let repository = environment.makeBankRepository(session: session)
        self.repository = repository
        _dashboardViewModel = State(initialValue: DashboardViewModel(repository: repository))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Switched manually instead of TabView: the system tab bar still draws
            // behind the custom one on newer iOS even when hidden.
            Group {
                switch selectedTab {
                case .home: home
                case .cards: CardsView()
                case .payments: PaymentsView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if homePath.isEmpty {
                LuxeTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, BankTheme.Spacing.screen)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: homePath.isEmpty)
    }

    private var home: some View {
        NavigationStack(path: $homePath) {
            DashboardView(
                viewModel: dashboardViewModel,
                onShowHistory: { account in
                    historyViewModel = HistoryViewModel(account: account, repository: repository)
                    homePath.append(.history)
                },
                onSelectTransaction: { homePath.append(.transaction($0.id)) }
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
                        }
                    )
                }
            }
        }
        .tint(BankTheme.ink)
    }
}

#Preview {
    ContentView(environment: .mock, session: AppEnvironment.mock.makeSessionManager())
}
