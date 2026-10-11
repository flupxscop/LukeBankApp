import Foundation
import Observation

/// Owns the device binding and the unlock state (AUTH-03…07, AUTH-09).
/// Access tokens live in memory only; the refresh token and device ID live in the Keychain.
@MainActor
@Observable
final class SessionManager {
    enum State: Equatable {
        case unregistered
        case locked
        case unlocked
    }

    enum ResetReason: Equatable {
        case pinLocked
        case deviceRevoked
    }

    static let autoLockInterval: TimeInterval = 5 * 60
    /// Renew a little before expiry so a request never leaves with a token about to lapse.
    static let tokenRenewalMargin: TimeInterval = 30

    private(set) var state: State
    private(set) var deviceID: UUID?
    private(set) var customerFirstName: String?
    private(set) var isBiometricEnabled: Bool
    private(set) var resetReason: ResetReason?
    private(set) var accessToken: String?

    private let repository: AuthRepository
    private let storage: SecureStorage
    private let keys: DeviceKeyManaging
    private let now: () -> Date
    private var lastActivity: Date
    private var backgroundedAt: Date?
    private var accessTokenExpiry: Date?
    private var refreshTask: Task<String, Error>?

    init(repository: AuthRepository, storage: SecureStorage, keys: DeviceKeyManaging, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.storage = storage
        self.keys = keys
        self.now = now
        lastActivity = now()
        let storedDevice = storage.string(for: StorageKey.deviceID).flatMap(UUID.init(uuidString:))
        deviceID = storedDevice
        customerFirstName = storage.string(for: StorageKey.firstName)
        isBiometricEnabled = keys.hasKey(.biometric)
        state = storedDevice != nil && keys.hasKey(.device) ? .locked : .unregistered
    }

    // MARK: Registration

    /// Keeps the new binding but stays on the onboarding flow until `finishOnboarding()`.
    func storeRegistration(_ session: AuthSession) async throws {
        try storage.set(session.deviceId.uuidString, for: StorageKey.deviceID)
        try storage.set(session.refreshToken, for: StorageKey.refreshToken)
        deviceID = session.deviceId
        apply(session)
        resetReason = nil
        await refreshProfile(accessToken: session.accessToken)
    }

    /// Keeps the lock-screen name in the current app language; failures keep the cached name.
    private func refreshProfile(accessToken: String) async {
        guard let profile = try? await repository.profile(accessToken: accessToken) else { return }
        customerFirstName = profile.firstName
        try? storage.set(profile.firstName, for: StorageKey.firstName)
    }

    func enableBiometric() async throws {
        guard let accessToken else { throw APIError.unauthorized }
        let publicKey = try keys.createKey(.biometric)
        do {
            try await repository.enableBiometric(publicKey: publicKey, accessToken: accessToken)
            isBiometricEnabled = true
        } catch {
            keys.deleteKey(.biometric)
            throw error
        }
    }

    func finishOnboarding() {
        lastActivity = now()
        state = .unlocked
    }

    // MARK: Unlock

    func unlock(pin: String) async throws {
        try await login(method: .pin, pin: pin, reason: String(localized: "lock.title"))
    }

    func unlockWithBiometric() async throws {
        try await login(method: .biometric, pin: nil, reason: String(localized: "faceid.reason"))
    }

    private func login(method: LoginMethod, pin: String?, reason: String) async throws {
        guard let deviceID else { throw APIError.unauthorized }
        do {
            let challenge = try await repository.challenge(deviceID: deviceID)
            let signature = try await keys.sign(Data(challenge.utf8), with: method == .pin ? .device : .biometric, reason: reason)
            let session = try await repository.login(deviceID: deviceID, challenge: challenge, signature: signature, method: method, pin: pin)
            apply(session)
            try storage.set(session.refreshToken, for: StorageKey.refreshToken)
            lastActivity = now()
            state = .unlocked
            await refreshProfile(accessToken: session.accessToken)
        } catch let error as APIError {
            switch error.code {
            case "PIN_LOCKED":
                resetDevice(.pinLocked)
            case "DEVICE_NOT_FOUND":
                resetDevice(.deviceRevoked)
            case "BIOMETRIC_NOT_ENABLED", "SIGNATURE_INVALID":
                // The biometric key no longer matches the server (e.g. a new face was enrolled).
                if method == .biometric {
                    keys.deleteKey(.biometric)
                    isBiometricEnabled = false
                }
            default:
                break
            }
            throw error
        }
    }

    // MARK: Access tokens (AUTH-07)

    /// A non-expired access token for API calls. Renews it silently with the refresh token when needed.
    func validAccessToken() async throws -> String {
        guard state == .unlocked else { throw APIError.unauthorized }
        if let accessToken, let accessTokenExpiry, accessTokenExpiry.timeIntervalSince(now()) > Self.tokenRenewalMargin {
            return accessToken
        }
        return try await refreshAccessToken()
    }

    /// Rotates the refresh token. Concurrent callers share one request; a rejected token locks the app.
    func refreshAccessToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { () throws -> String in
            guard let refreshToken = storage.string(for: StorageKey.refreshToken) else { throw APIError.unauthorized }
            let session = try await repository.refresh(refreshToken: refreshToken)
            try storage.set(session.refreshToken, for: StorageKey.refreshToken)
            apply(session)
            return session.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch let error as APIError where error == .unauthorized || error.code == "TOKEN_INVALID" {
            lock()
            throw APIError.unauthorized
        }
    }

    private func apply(_ session: AuthSession) {
        accessToken = session.accessToken
        accessTokenExpiry = now().addingTimeInterval(TimeInterval(session.expiresInSeconds))
    }

    // MARK: Locking (AUTH-04, AUTH-06)

    func lock() {
        guard state == .unlocked else { return }
        accessToken = nil
        accessTokenExpiry = nil
        state = .locked
    }

    func registerActivity() {
        lastActivity = now()
    }

    func checkInactivity() {
        if state == .unlocked, now().timeIntervalSince(lastActivity) >= Self.autoLockInterval {
            lock()
        }
    }

    func didEnterBackground() {
        backgroundedAt = now()
    }

    func didBecomeActive() {
        defer { backgroundedAt = nil }
        if let backgroundedAt, now().timeIntervalSince(backgroundedAt) >= Self.autoLockInterval {
            lock()
        } else {
            checkInactivity()
        }
    }

    // MARK: Sign out

    func logout() async {
        if let accessToken {
            try? await repository.logout(accessToken: accessToken)
        }
        resetDevice(nil)
    }

    private func resetDevice(_ reason: ResetReason?) {
        keys.deleteKey(.device)
        keys.deleteKey(.biometric)
        [StorageKey.deviceID, StorageKey.refreshToken, StorageKey.firstName].forEach(storage.remove)
        deviceID = nil
        accessToken = nil
        customerFirstName = nil
        isBiometricEnabled = false
        resetReason = reason
        state = .unregistered
    }

    private enum StorageKey {
        static let deviceID = "session.deviceId"
        static let refreshToken = "session.refreshToken"
        static let firstName = "customer.firstName"
    }
}

extension SessionManager: AccessTokenProviding {}
