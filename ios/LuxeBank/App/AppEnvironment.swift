import Foundation

/// Dependency container (spec 6.2). Mock repositories by default; pass
/// `-LuxeBankAPI http://127.0.0.1:8080` as a launch argument to use a local backend.
@MainActor
struct AppEnvironment {
    let dashboardRepository: DashboardRepository
    let authRepository: AuthRepository
    let secureStorage: SecureStorage
    let keyManager: DeviceKeyManaging
    let biometrics: BiometricAvailability

    static func makeDefault(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let storage = KeychainStore()
        #if DEBUG
        // UI tests start from a clean install state.
        if arguments.contains("-ResetSession") {
            ["session.deviceId", "session.refreshToken", "customer.firstName", "key.device", "key.biometric"].forEach(storage.remove)
        }
        #endif
        let auth: AuthRepository
        if let index = arguments.firstIndex(of: "-LuxeBankAPI"), arguments.indices.contains(index + 1),
           let base = URL(string: arguments[index + 1]) {
            let client = APIClient(
                baseURL: base.appending(path: "api/v1"),
                session: URLSession(configuration: .ephemeral, delegate: PinnedSessionDelegate(pins: []), delegateQueue: nil),
                deviceID: { storage.string(for: "session.deviceId").flatMap(UUID.init(uuidString:)) }
            )
            auth = RemoteAuthRepository(client: client)
        } else {
            auth = MockAuthRepository()
        }
        return AppEnvironment(
            dashboardRepository: MockDashboardRepository(),
            authRepository: auth,
            secureStorage: storage,
            keyManager: SecureEnclaveKeyManager(storage: storage),
            biometrics: SystemBiometrics()
        )
    }

    static var mock: AppEnvironment {
        let storage = InMemorySecureStorage()
        return AppEnvironment(
            dashboardRepository: MockDashboardRepository(),
            authRepository: MockAuthRepository(),
            secureStorage: storage,
            keyManager: SecureEnclaveKeyManager(storage: storage),
            biometrics: SystemBiometrics()
        )
    }

    func makeSessionManager() -> SessionManager {
        SessionManager(repository: authRepository, storage: secureStorage, keys: keyManager)
    }

    func makeRegistrationViewModel(session: SessionManager) -> RegistrationViewModel {
        RegistrationViewModel(repository: authRepository, session: session, keys: keyManager, biometrics: biometrics)
    }
}
