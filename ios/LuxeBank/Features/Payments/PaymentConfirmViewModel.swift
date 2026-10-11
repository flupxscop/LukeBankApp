import Foundation
import Observation

/// Signs a payment challenge with the bound device: the device key with the PIN, or the Face ID-gated key (TRF-07, TRF-09).
@MainActor
protocol PaymentAuthorizing: AnyObject {
    var isBiometricEnabled: Bool { get }
    func authorize(challenge: String, method: LoginMethod, pin: String?) async throws -> PaymentAuthorization
    /// The server locked the PIN: unbind this device, as on the lock screen.
    func handlePinLocked()
}

@MainActor
final class DevicePaymentAuthorizer: PaymentAuthorizing {
    private let keys: DeviceKeyManaging
    private let session: SessionManager

    init(keys: DeviceKeyManaging, session: SessionManager) {
        self.keys = keys
        self.session = session
    }

    var isBiometricEnabled: Bool { session.isBiometricEnabled }

    func authorize(challenge: String, method: LoginMethod, pin: String?) async throws -> PaymentAuthorization {
        let signature = try await keys.sign(
            Data(challenge.utf8), with: method == .biometric ? .biometric : .device, reason: String(localized: "payment.faceid.reason")
        )
        return PaymentAuthorization(method: method, signature: signature, pin: pin)
    }

    func handlePinLocked() {
        session.deviceLocked()
    }
}

/// S10 — review and confirm a priced inquiry; shared by transfers and bills (BILL-05).
/// One idempotency key per inquiry, reused on every retry, so a lost response never pays twice (TRF-14).
@MainActor
@Observable
final class PaymentConfirmViewModel {
    enum Phase: Equatable {
        case review
        case enteringPin
        case submitting
        case expired
        /// Paid; the slip is on its way and the PIN sheet closes.
        case done
    }

    typealias Submit = (_ authorization: PaymentAuthorization, _ idempotencyKey: String, _ save: Bool) async throws -> PaymentSlip

    let inquiry: PaymentInquiry
    var save: Bool
    private(set) var phase: Phase = .review
    private(set) var pin = ""
    private(set) var error: LocalizedStringResource?
    private(set) var slip: PaymentSlip?

    private let authorizer: PaymentAuthorizing
    private let submit: Submit
    private let now: () -> Date
    let idempotencyKey = UUID().uuidString

    init(inquiry: PaymentInquiry, authorizer: PaymentAuthorizing, saveByDefault: Bool, now: @escaping () -> Date = Date.init, submit: @escaping Submit) {
        self.inquiry = inquiry
        self.authorizer = authorizer
        self.submit = submit
        self.now = now
        save = saveByDefault
    }

    /// Face ID is required from ฿50,000 and preferred whenever the customer turned it on.
    var usesBiometric: Bool { inquiry.requiresBiometric || authorizer.isBiometricEnabled }
    var needsBiometricSetup: Bool { inquiry.requiresBiometric && !authorizer.isBiometricEnabled }
    var canUsePin: Bool { !inquiry.requiresBiometric }

    func secondsLeft(at date: Date? = nil) -> Int {
        max(0, Int((inquiry.expiresAt.timeIntervalSince(date ?? now())).rounded(.down)))
    }

    func tick() {
        if secondsLeft() == 0, phase == .review || phase == .enteringPin { phase = .expired }
    }

    func confirm() async {
        guard phase == .review else { return }
        if needsBiometricSetup {
            error = "error.stepUpSetup"
            return
        }
        if usesBiometric {
            await send(method: .biometric, pin: nil)
        } else {
            startPin()
        }
    }

    func startPin() {
        guard canUsePin else { return }
        error = nil
        pin = ""
        phase = .enteringPin
    }

    func cancelPin() {
        pin = ""
        phase = .review
    }

    func appendPinDigit(_ digit: Int) async {
        guard phase == .enteringPin, pin.count < 6 else { return }
        error = nil
        pin.append(String(digit))
        if pin.count == 6 { await send(method: .pin, pin: pin) }
    }

    func deletePinDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func send(method: LoginMethod, pin: String?) async {
        let previous = phase
        phase = .submitting
        error = nil
        do {
            let authorization = try await authorizer.authorize(challenge: inquiry.challenge, method: method, pin: pin)
            slip = try await submit(authorization, idempotencyKey, save)
            self.pin = ""
            phase = .done
        } catch let apiError as APIError {
            handle(apiError, previous: previous)
        } catch {
            // Face ID cancelled or the key was unavailable.
            phase = previous == .enteringPin ? .enteringPin : .review
            self.pin = ""
            self.error = "error.biometricCancelled"
        }
    }

    private func handle(_ apiError: APIError, previous: Phase) {
        pin = ""
        switch apiError.code {
        case "PIN_INVALID":
            phase = .enteringPin
            error = "error.pinInvalid \(apiError.remainingAttempts ?? 0)"
        case "PIN_LOCKED":
            authorizer.handlePinLocked()
            phase = .review
            error = "error.pinLocked"
        case "INQUIRY_EXPIRED":
            phase = .expired
        default:
            phase = previous == .enteringPin ? .review : previous
            error = apiError.code == "STEP_UP_REQUIRED" ? "error.stepUpSetup" : PaymentErrors.message(for: apiError)
        }
    }
}

/// Server error codes → what the customer reads (spec section 9).
enum PaymentErrors {
    private static let messages: [String: LocalizedStringResource] = [
        "INSUFFICIENT_FUNDS": "error.insufficientFunds",
        "DAILY_LIMIT_EXCEEDED": "error.dailyLimit",
        "RECIPIENT_NOT_FOUND": "error.recipientNotFound",
        "BILL_NOT_FOUND": "error.billNotFound",
        "SERVICE_UNAVAILABLE": "error.serviceUnavailable",
        "DUPLICATE_REQUEST": "error.duplicate",
        "QR_INVALID": "error.qrInvalid",
        "RATE_LIMITED": "error.rateLimited",
        "VALIDATION_FAILED": "error.invalidDetails",
        "DEVICE_COMPROMISED": "error.deviceCompromised",
    ]

    static func message(for error: Error) -> LocalizedStringResource {
        guard let apiError = error as? APIError else { return "error.generic" }
        if let code = apiError.code, let message = messages[code] { return message }
        return apiError == .network ? "error.network" : "error.generic"
    }
}
