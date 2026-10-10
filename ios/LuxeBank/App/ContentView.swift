import SwiftUI

struct ContentView: View {
    @State private var selectedTab: BankTab = .home
    @State private var dashboardViewModel: DashboardViewModel

    init(environment: AppEnvironment) {
        _dashboardViewModel = State(initialValue: DashboardViewModel(repository: environment.dashboardRepository))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Switched manually instead of TabView: the system tab bar still draws
            // behind the custom one on newer iOS even when hidden.
            Group {
                switch selectedTab {
                case .home: DashboardView(viewModel: dashboardViewModel)
                case .cards: CardsView()
                case .payments: PaymentsView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LuxeTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, BankTheme.Spacing.screen)
                .padding(.bottom, 8)
        }
    }
}

#Preview {
    ContentView(environment: .mock)
}
