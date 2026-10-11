import Foundation

/// Behaves like the backend with the local demo customer (spec 13.3.2, synthetic data):
/// citizen ID 1-2345-67890-12-1, password LuxeDemo#2026, OTP 000000.
/// Signatures are not verified here; the backend tests cover that.
final class MockAuthRepository: AuthRepository {
    static let demoCitizenID = "1234567890121"
    static let demoPassword = "LuxeDemo#2026"

    private var pinByDevice: [UUID: String] = [:]
    private var failedPins = 0
    private var failedPasswords = 0
    private var currentDevice: UUID?
    var delay: Duration = .milliseconds(350)

    func startRegistration(citizenID: String, password: String) async throws -> RegistrationChallenge {
        try await pause()
        guard citizenID == Self.demoCitizenID, password == Self.demoPassword else {
            failedPasswords += 1
            if failedPasswords >= 5 { throw APIError.server(code: "ACCOUNT_LOCKED", message: "locked", remainingAttempts: nil) }
            throw APIError.server(code: "INVALID_CREDENTIALS", message: "invalid", remainingAttempts: 5 - failedPasswords)
        }
        failedPasswords = 0
        return RegistrationChallenge(otpRef: "KXQ7", maskedPhone: "08X-XXX-4521", expiresInSeconds: 300)
    }

    func verifyOTP(reference: String, code: String) async throws -> String {
        try await pause()
        guard code == "000000" else { throw APIError.server(code: "OTP_INVALID", message: "invalid", remainingAttempts: 4) }
        return "mock-registration-token"
    }

    func registerDevice(registrationToken: String, pin: String, deviceName: String, publicKey: Data) async throws -> AuthSession {
        try await pause()
        guard PinRules.isAcceptable(pin) else { throw APIError.server(code: "PIN_POLICY_VIOLATION", message: "weak", remainingAttempts: nil) }
        let deviceID = UUID()
        pinByDevice[deviceID] = pin
        return session(deviceID)
    }

    func challenge(deviceID: UUID) async throws -> String {
        try await pause()
        return UUID().uuidString
    }

    func login(deviceID: UUID, challenge: String, signature: Data, method: LoginMethod, pin: String?) async throws -> AuthSession {
        try await pause()
        if method == .biometric {
            // The app only offers Face ID when it holds a biometric key, so the mock trusts it.
            return session(deviceID)
        }
        // A fresh mock (e.g. after relaunch) accepts the first PIN it sees for the stored device.
        let expected = pinByDevice[deviceID] ?? pin
        pinByDevice[deviceID] = expected
        guard pin == expected else {
            failedPins += 1
            if failedPins >= 5 { throw APIError.server(code: "PIN_LOCKED", message: "locked", remainingAttempts: nil) }
            throw APIError.server(code: "PIN_INVALID", message: "invalid", remainingAttempts: 5 - failedPins)
        }
        failedPins = 0
        return session(deviceID)
    }

    func enableBiometric(publicKey: Data, accessToken: String) async throws {
        try await pause()
    }

    var refreshShouldFail = false
    private(set) var refreshCount = 0

    func refresh(refreshToken: String) async throws -> AuthSession {
        refreshCount += 1
        if refreshShouldFail { throw APIError.server(code: "TOKEN_INVALID", message: "expired", remainingAttempts: nil) }
        return AuthSession(deviceId: UUID(), accessToken: "mock-access-\(refreshCount)", refreshToken: "mock-refresh-\(refreshCount)", expiresInSeconds: 900)
    }

    func profile(accessToken: String) async throws -> CustomerProfile {
        CustomerProfile(firstName: "นกน้อย", tier: "GOLD", maskedPhone: "08X-XXX-4521")
    }

    func logout(accessToken: String) async throws {}

    func disableBiometric(accessToken: String) async throws {
        try await pause()
    }

    func changePin(currentPin: String, newPin: String, accessToken: String) async throws {
        try await pause()
        let device = currentDevice ?? UUID()
        let expected = pinByDevice[device] ?? currentPin
        guard currentPin == expected else {
            failedPins += 1
            if failedPins >= 5 { throw APIError.server(code: "PIN_LOCKED", message: "locked", remainingAttempts: nil) }
            throw APIError.server(code: "PIN_INVALID", message: "invalid", remainingAttempts: 5 - failedPins)
        }
        guard PinRules.isAcceptable(newPin) else { throw APIError.server(code: "PIN_POLICY_VIOLATION", message: "weak", remainingAttempts: nil) }
        failedPins = 0
        pinByDevice[device] = newPin
    }

    private func session(_ deviceID: UUID) -> AuthSession {
        currentDevice = deviceID
        return AuthSession(deviceId: deviceID, accessToken: "mock-access", refreshToken: "mock-refresh", expiresInSeconds: 900)
    }

    private func pause() async throws {
        try await Task.sleep(for: delay)
    }
}
