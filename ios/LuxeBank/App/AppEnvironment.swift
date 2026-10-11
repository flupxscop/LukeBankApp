import Foundation

/// Dependency container (spec 6.2). Mock repositories by default; pass
/// `-LuxeBankAPI http://127.0.0.1:8080` as a launch argument to use a local backend.
typealias BankRepository = DashboardRepository & TransactionRepository

@MainActor
struct AppEnvironment {
    let authRepository: AuthRepository
    let secureStorage: SecureStorage
    let keyManager: DeviceKeyManaging
    let biometrics: BiometricAvailability
    /// Set when running against a backend; otherwise `mockBank` serves data.
    let apiClient: APIClient?
    let mockBank: MockBankRepository?
    let mockPayments: MockPaymentRepository?

    static func makeDefault(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let storage = KeychainStore()
        #if DEBUG
        // UI tests start from a clean install state.
        if arguments.contains("-ResetSession") {
            ["session.deviceId", "session.refreshToken", "customer.firstName", "key.device", "key.biometric"].forEach(storage.remove)
        }
        #endif
        let auth: AuthRepository
        var apiClient: APIClient?
        if let index = arguments.firstIndex(of: "-LuxeBankAPI"), arguments.indices.contains(index + 1),
           let base = URL(string: arguments[index + 1]) {
            let client = APIClient(
                baseURL: base.appending(path: "api/v1"),
                session: URLSession(configuration: .ephemeral, delegate: PinnedSessionDelegate(pins: []), delegateQueue: nil),
                deviceID: { storage.string(for: "session.deviceId").flatMap(UUID.init(uuidString:)) }
            )
            auth = RemoteAuthRepository(client: client)
            apiClient = client
        } else {
            auth = MockAuthRepository()
        }
        let mockBank = apiClient == nil ? MockBankRepository() : nil
        return AppEnvironment(
            authRepository: auth,
            secureStorage: storage,
            keyManager: SecureEnclaveKeyManager(storage: storage),
            biometrics: SystemBiometrics(),
            apiClient: apiClient,
            mockBank: mockBank,
            mockPayments: apiClient == nil ? MockPaymentRepository(bank: mockBank) : nil
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
            apiClient: nil,
            mockBank: bank,
            mockPayments: MockPaymentRepository(bank: bank)
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

    func makeRegistrationViewModel(session: SessionManager) -> RegistrationViewModel {
        RegistrationViewModel(repository: authRepository, session: session, keys: keyManager, biometrics: biometrics)
    }
}
