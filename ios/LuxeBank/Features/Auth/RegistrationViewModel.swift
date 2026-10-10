import Foundation
import Observation
import UIKit

/// Onboarding: credentials → OTP → PIN (enter + confirm) → optional Face ID (AUTH-01…03).
@MainActor
@Observable
final class RegistrationViewModel {
    enum Step: Hashable {
        case otp
        case pin
        case biometric
    }

    var path: [Step] = []
    /// Digits only; the field formats them as "1-2345-67890-12-1".
    var citizenIDDigits = ""

    var citizenID: String {
        get { CitizenID.formatted(citizenIDDigits) }
        set { citizenIDDigits = CitizenID.digits(of: newValue) }
    }

    var password = ""
    private(set) var otpCode = ""
    private(set) var pin = ""
    private(set) var isConfirmingPin = false
    private(set) var challenge: RegistrationChallenge?
    private(set) var isLoading = false
    private(set) var error: LocalizedStringResource?
    private(set) var resendAvailableAt: Date?

    private var firstPin = ""
    private var registrationToken: String?
    private let repository: AuthRepository
    private let session: SessionManager
    private let keys: DeviceKeyManaging
    private let biometrics: BiometricAvailability
    private let now: () -> Date

    init(
        repository: AuthRepository,
        session: SessionManager,
        keys: DeviceKeyManaging,
        biometrics: BiometricAvailability,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.session = session
        self.keys = keys
        self.biometrics = biometrics
        self.now = now
    }

    var isCitizenIDValid: Bool { CitizenID.isValid(citizenIDDigits) }
    var canSubmitCredentials: Bool { isCitizenIDValid && !password.isEmpty && !isLoading }
    var pinRules: PinRules { PinRules(pin) }

    // MARK: Step 1 — credentials

    func submitCredentials() async {
        guard canSubmitCredentials else { return }
        await run {
            challenge = try await repository.startRegistration(citizenID: citizenIDDigits, password: password)
            password = ""
            otpCode = ""
            resendAvailableAt = now().addingTimeInterval(45)
            path = [.otp]
        }
    }

    // MARK: Step 2 — OTP

    func appendOTPDigit(_ digit: Int) async {
        guard otpCode.count < 6, !isLoading else { return }
        error = nil
        otpCode.append(String(digit))
        if otpCode.count == 6 { await submitOTP() }
    }

    func deleteOTPDigit() {
        guard !otpCode.isEmpty else { return }
        otpCode.removeLast()
    }

    func submitOTP() async {
        guard let challenge, otpCode.count == 6 else { return }
        await run {
            registrationToken = try await repository.verifyOTP(reference: challenge.otpRef, code: otpCode)
            path.append(.pin)
        }
        if error != nil { otpCode = "" }
    }

    func resendOTP() async {
        guard let resendAvailableAt, now() >= resendAvailableAt else { return }
        path = []
        challenge = nil
    }

    // MARK: Step 3 — PIN

    func appendPinDigit(_ digit: Int) async {
        guard pin.count < 6, !isLoading else { return }
        error = nil
        pin.append(String(digit))
        guard pin.count == 6 else { return }

        if !isConfirmingPin {
            guard PinRules.isAcceptable(pin) else {
                error = "error.pinWeak"
                pin = ""
                return
            }
            firstPin = pin
            pin = ""
            isConfirmingPin = true
            return
        }
        guard pin == firstPin else {
            error = "error.pinMismatch"
            pin = ""
            firstPin = ""
            isConfirmingPin = false
            return
        }
        await registerDevice()
    }

    func deletePinDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func registerDevice() async {
        guard let registrationToken else { return }
        await run {
            let publicKey = try keys.createKey(.device)
            let result = try await repository.registerDevice(
                registrationToken: registrationToken,
                pin: pin,
                deviceName: UIDevice.current.model,
                publicKey: publicKey
            )
            try await session.storeRegistration(result)
            self.registrationToken = nil
            if biometrics.isAvailable {
                path.append(.biometric)
            } else {
                session.finishOnboarding()
            }
        }
        pin = ""
        firstPin = ""
    }

    // MARK: Step 4 — Face ID

    func enableBiometric() async {
        await run {
            try await session.enableBiometric()
            session.finishOnboarding()
        }
    }

    func skipBiometric() {
        session.finishOnboarding()
    }

    // MARK: Helpers

    private func run(_ work: () async throws -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            self.error = AuthErrorMessage.message(for: error)
        }
    }
}

enum AuthErrorMessage {
    static func message(for error: Error) -> LocalizedStringResource {
        guard let apiError = error as? APIError else {
            return error is DeviceKeyError ? "error.biometricCancelled" : "error.generic"
        }
        let remaining = apiError.remainingAttempts ?? 0
        switch apiError.code {
        case "INVALID_CREDENTIALS": return apiError.remainingAttempts == nil ? "error.credentials" : "error.credentials.remaining \(remaining)"
        case "ACCOUNT_LOCKED": return "error.accountLocked"
        case "OTP_INVALID": return "error.otpInvalid \(remaining)"
        case "OTP_EXPIRED", "OTP_LOCKED", "REGISTRATION_EXPIRED": return "error.otpExpired"
        case "PIN_POLICY_VIOLATION": return "error.pinWeak"
        case "PIN_INVALID": return "error.pinInvalid \(remaining)"
        case "PIN_LOCKED": return "error.pinLocked"
        case "RATE_LIMITED": return "error.rateLimited"
        default: return apiError == .network ? "error.network" : "error.generic"
        }
    }
}
