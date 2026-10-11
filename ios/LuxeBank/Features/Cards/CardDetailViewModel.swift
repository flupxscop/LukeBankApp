import Foundation
import Observation

/// S16 — card controls, the Face ID reveal and reporting a card lost (CARD-03…07).
@MainActor
@Observable
final class CardDetailViewModel {
    private(set) var card: BankCard
    private(set) var secrets: CardSecrets?
    private(set) var secondsLeft = 0
    private(set) var isWorking = false
    private(set) var error: LocalizedStringResource?
    private(set) var isEnteringPin = false
    private(set) var pin = ""
    var dailyLimitDraft: Double

    private let repository: CardRepository
    private let authorizer: PaymentAuthorizing
    private let sleep: (Duration) async throws -> Void
    private let onChange: (BankCard, UUID?) -> Void
    private var revealTask: Task<Void, Never>?

    /// Steps of the daily-limit slider.
    static let limitStep: Decimal = 5_000

    init(
        card: BankCard,
        repository: CardRepository,
        authorizer: PaymentAuthorizing,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onChange: @escaping (BankCard, UUID?) -> Void = { _, _ in }
    ) {
        self.card = card
        self.repository = repository
        self.authorizer = authorizer
        self.sleep = sleep
        self.onChange = onChange
        dailyLimitDraft = NSDecimalNumber(decimal: card.dailyLimit).doubleValue
    }

    var canReveal: Bool { authorizer.isBiometricEnabled }

    // MARK: Freeze and controls

    func setFrozen(_ frozen: Bool) async {
        guard frozen != card.isFrozen else { return }
        await run { try await repository.setFrozen(cardID: card.id, frozen: frozen) }
    }

    func setChannel(_ keyPath: WritableKeyPath<CardChannels, Bool>, _ isOn: Bool) async {
        var channels = card.channels
        channels[keyPath: keyPath] = isOn
        await run { try await repository.updateControls(cardID: card.id, change: CardControlsChange(channels: channels)) }
    }

    /// Called when the slider is released; rounds to the step and stays within the approved maximum (CARD-06).
    func commitDailyLimit() async {
        let steps = (Decimal(dailyLimitDraft) / Self.limitStep as NSDecimalNumber).rounding(accordingToBehavior: nil)
        let limit = min(card.maxDailyLimit, max(Self.limitStep, steps.decimalValue * Self.limitStep))
        dailyLimitDraft = NSDecimalNumber(decimal: limit).doubleValue
        guard limit != card.dailyLimit else { return }
        await run { try await repository.updateControls(cardID: card.id, change: CardControlsChange(dailyLimit: limit)) }
    }

    // MARK: Reveal (CARD-07)

    /// Face ID, then the full number and CVV for `visibleForSeconds`, then hidden again.
    func reveal() async {
        guard secrets == nil, !isWorking else { return }
        guard canReveal else {
            error = "cards.revealNeedsFaceID"
            return
        }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let challenge = try await repository.challenge()
            let authorization = try await authorizer.authorize(challenge: challenge, method: .biometric, pin: nil)
            let shown = try await repository.reveal(cardID: card.id, challenge: challenge, authorization: authorization)
            secrets = shown
            secondsLeft = shown.visibleForSeconds
            revealTask = Task { [weak self] in await self?.countDown() }
        } catch let apiError as APIError {
            error = PaymentErrors.message(for: apiError)
        } catch {
            self.error = "error.biometricCancelled"
        }
    }

    /// Clears the details from memory; also called when the app leaves the foreground or the screen is captured.
    func hide() {
        revealTask?.cancel()
        revealTask = nil
        secrets = nil
        secondsLeft = 0
    }

    private func countDown() async {
        while secondsLeft > 0 {
            do { try await sleep(.seconds(1)) } catch { return }
            secondsLeft -= 1
        }
        secrets = nil
    }

    // MARK: Report lost (CARD-04)

    func startReportLost() {
        error = nil
        pin = ""
        isEnteringPin = true
    }

    func cancelReportLost() {
        pin = ""
        isEnteringPin = false
    }

    func appendPinDigit(_ digit: Int) async {
        guard isEnteringPin, pin.count < 6, !isWorking else { return }
        error = nil
        pin.append(String(digit))
        guard pin.count == 6 else { return }
        isWorking = true
        defer { isWorking = false }
        let old = card.id
        do {
            let challenge = try await repository.challenge()
            let authorization = try await authorizer.authorize(challenge: challenge, method: .pin, pin: pin)
            let replacement = try await repository.reportLost(cardID: old, challenge: challenge, authorization: authorization)
            hide()
            card = replacement
            dailyLimitDraft = NSDecimalNumber(decimal: replacement.dailyLimit).doubleValue
            isEnteringPin = false
            pin = ""
            onChange(replacement, old)
        } catch let apiError as APIError {
            pin = ""
            if apiError.code == "PIN_LOCKED" {
                isEnteringPin = false
                authorizer.handlePinLocked()
            }
            error = apiError.code == "PIN_INVALID" ? "error.pinInvalid \(apiError.remainingAttempts ?? 0)" : PaymentErrors.message(for: apiError)
        } catch {
            pin = ""
            self.error = "error.generic"
        }
    }

    func deletePinDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func run(_ action: () async throws -> BankCard) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            card = try await action()
            dailyLimitDraft = NSDecimalNumber(decimal: card.dailyLimit).doubleValue
            onChange(card, nil)
        } catch {
            self.error = PaymentErrors.message(for: error)
        }
    }
}
