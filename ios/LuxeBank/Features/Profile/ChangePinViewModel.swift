import Foundation
import Observation

/// PROF-02: current PIN → new PIN → confirm. Checked against the PIN rules before the server sees it.
@MainActor
@Observable
final class ChangePinViewModel {
    enum Step: Equatable {
        case current
        case new
        case confirm
        case done
    }

    private(set) var step: Step = .current
    private(set) var pin = ""
    private(set) var isWorking = false
    private(set) var error: LocalizedStringResource?
    private var currentPin = ""
    private var newPin = ""
    private let security: SecuritySettings

    init(security: SecuritySettings) {
        self.security = security
    }

    var title: LocalizedStringResource {
        switch step {
        case .current: "changePin.current"
        case .new: "changePin.new"
        case .confirm: "changePin.confirm"
        case .done: "changePin.done"
        }
    }

    func appendDigit(_ digit: Int) async {
        guard pin.count < 6, !isWorking, step != .done else { return }
        error = nil
        pin.append(String(digit))
        guard pin.count == 6 else { return }
        let entered = pin
        pin = ""
        switch step {
        case .current:
            currentPin = entered
            step = .new
        case .new:
            guard PinRules.isAcceptable(entered) else {
                error = "error.pinWeak"
                return
            }
            guard entered != currentPin else {
                error = "changePin.sameAsCurrent"
                return
            }
            newPin = entered
            step = .confirm
        case .confirm:
            guard entered == newPin else {
                error = "error.pinMismatch"
                newPin = ""
                step = .new
                return
            }
            await submit()
        case .done:
            break
        }
    }

    func deleteDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await security.changePin(current: currentPin, new: newPin)
            step = .done
        } catch let apiError as APIError {
            switch apiError.code {
            case "PIN_INVALID":
                // The current PIN was wrong: start again from it.
                error = "error.pinInvalid \(apiError.remainingAttempts ?? 0)"
                restart()
            case "PIN_LOCKED":
                // The session already reset the device; the app returns to Welcome.
                error = "error.pinLocked"
            case "PIN_POLICY_VIOLATION":
                error = "error.pinWeak"
                newPin = ""
                step = .new
            default:
                error = PaymentErrors.message(for: apiError)
                restart()
            }
        } catch {
            self.error = "error.generic"
            restart()
        }
    }

    private func restart() {
        currentPin = ""
        newPin = ""
        step = .current
    }
}
