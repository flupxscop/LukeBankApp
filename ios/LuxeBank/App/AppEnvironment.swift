import Foundation

/// Dependency container (spec 6.2). See `AppConfiguration` for mock vs backend: Debug builds use mocks
/// unless `-LuxeBankAPI http://127.0.0.1:8080` is passed; Release builds always use the pinned backend.
typealias BankRepository = DashboardRepository & TransactionRepository

@MainActor
struct AppEnvironment {
    let authRepository: AuthRepository
    let secureStorage: SecureStorage
    let keyManager: DeviceKeyManaging
    let biometrics: BiometricAvailability
    let integrity: DeviceIntegrityChecking
    let network: NetworkMonitor
    /// Set when running against a backend; otherwise `mockBank` serves data.
    let apiClient: APIClient?
    let mockBank: MockBankRepository?
    let mockPayments: MockPaymentRepository?
    let mockCards: MockCardRepository?
    let mockProfile: MockProfileRepository?

    static func makeDefault(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let storage = KeychainStore()
        #if DEBUG
        // UI tests start from a clean install state.
        if arguments.contains("-ResetSession") {
            ["session.deviceId", "session.refreshToken", "customer.firstName", "key.device", "key.biometric"].forEach(storage.remove)
        }
        #endif
        let integrity = SystemDeviceIntegrity(arguments: arguments)
        let auth: AuthRepository
        var apiClient: APIClient?
        switch AppConfiguration.current(arguments: arguments) {
        case .remote(let base, let pins):
            let client = APIClient(
                baseURL: base.appending(path: "api/v1"),
                session: URLSession(configuration: .ephemeral, delegate: PinnedSessionDelegate(pins: pins), delegateQueue: nil),
                deviceID: { storage.string(for: "session.deviceId").flatMap(UUID.init(uuidString:)) },
                isDeviceCompromised: integrity.isCompromised
            )
            auth = RemoteAuthRepository(client: client)
            apiClient = client
        case .mock:
            auth = MockAuthRepository()
        }
        let mockBank = apiClient == nil ? MockBankRepository() : nil
        let mockPayments = apiClient == nil ? MockPaymentRepository(bank: mockBank) : nil
        let mockCards = apiClient == nil ? MockCardRepository() : nil
        mockPayments?.deviceCompromised = integrity.isCompromised
        mockCards?.deviceCompromised = integrity.isCompromised
        return AppEnvironment(
            authRepository: auth,
            secureStorage: storage,
            keyManager: SecureEnclaveKeyManager(storage: storage),
            biometrics: SystemBiometrics(),
            integrity: integrity,
            network: NetworkMonitor(arguments: arguments),
            apiClient: apiClient,
            mockBank: mockBank,
            mockPayments: mockPayments,
            mockCards: mockCards,
            mockProfile: apiClient == nil ? MockProfileRepository() : nil
        )
    }

    static var mock: AppEnvironment {
        let storage = InMemorySecureStorage()
        let bank = MockBankRepository()
        return AppEnvironment(
            authRepository: MockAuthRepository(),
            secureStorage: storage,
            keyManager: SecureEnclaveKeyManager(storage: storage),
            biometrics: SystemBiometrics(),
            integrity: SystemDeviceIntegrity(arguments: []),
            network: NetworkMonitor(isOnline: true),
            apiClient: nil,
            mockBank: bank,
            mockPayments: MockPaymentRepository(bank: bank),
            mockCards: MockCardRepository(),
            mockProfile: MockProfileRepository()
        )
    }

    func makeSessionManager() -> SessionManager {
        SessionManager(repository: authRepository, storage: secureStorage, keys: keyManager)
    }

    /// Accounts, dashboard and history for the signed-in customer, authorised through `session`.
    func makeBankRepository(session: SessionManager) -> BankRepository {
        if let apiClient {
            return RemoteBankRepository(api: AuthorizedAPI(client: apiClient, tokens: session))
        }
        return mockBank ?? MockBankRepository()
    }

    /// Transfers, bills and QR for the signed-in customer (M3).
    func makePaymentRepository(session: SessionManager) -> PaymentRepository {
        if let apiClient {
            return RemotePaymentRepository(api: AuthorizedAPI(client: apiClient, tokens: session))
        }
        return mockPayments ?? MockPaymentRepository(bank: mockBank)
    }

    /// Cards for the signed-in customer (M4).
    func makeCardRepository(session: SessionManager) -> CardRepository {
        if let apiClient {
            return RemoteCardRepository(api: AuthorizedAPI(client: apiClient, tokens: session))
        }
        return mockCards ?? MockCardRepository()
    }

    /// Profile, preferences and the inbox (M5).
    func makeProfileRepository(session: SessionManager) -> ProfileRepository {
        if let apiClient {
            return RemoteProfileRepository(api: AuthorizedAPI(client: apiClient, tokens: session))
        }
        return mockProfile ?? MockProfileRepository()
    }

    func makeRegistrationViewModel(session: SessionManager) -> RegistrationViewModel {
        RegistrationViewModel(repository: authRepository, session: session, keys: keyManager, biometrics: biometrics)
    }
}
