import Combine
import SwiftUI

/// Chooses onboarding, lock screen or the app from the session state (spec 6.4).
struct RootView: View {
    let environment: AppEnvironment
    @State private var session: SessionManager
    @State private var registration: RegistrationViewModel?
    @Environment(\.scenePhase) private var scenePhase

    private let inactivityTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    init(environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: environment.makeSessionManager())
    }

    var body: some View {
        ZStack {
            switch session.state {
            case .unregistered:
                if let registration {
                    RegistrationFlowView(viewModel: registration) { self.registration = nil }
                        .transition(.move(edge: .trailing))
                } else {
                    WelcomeView(resetReason: session.resetReason) {
                        registration = environment.makeRegistrationViewModel(session: session)
                    }
                }
            case .locked:
                LockView(session: session)
            case .unlocked:
                ContentView(environment: environment)
                    .simultaneousGesture(TapGesture().onEnded { session.registerActivity() })
            }

            if scenePhase != .active {
                PrivacyOverlay()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .onChange(of: session.state) { _, state in
            if state != .unregistered { registration = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: session.didEnterBackground()
            case .active: session.didBecomeActive()
            default: break
            }
        }
        .onReceive(inactivityTimer) { _ in session.checkInactivity() }
    }
}

/// Hides balances in the App Switcher snapshot (AUTH-10).
private struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            BankBackground()
            Text(verbatim: "LUXEBANK")
                .font(BankFont.headline(18))
                .tracking(6)
                .foregroundStyle(BankTheme.ink)
        }
        .accessibilityHidden(true)
    }
}
