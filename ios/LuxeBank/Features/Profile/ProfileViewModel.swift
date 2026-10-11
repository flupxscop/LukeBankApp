import Foundation
import Observation

/// What Settings needs from the session; `SessionManager` in the app.
@MainActor
protocol SecuritySettings: AnyObject {
    var isBiometricEnabled: Bool { get }
    func enableBiometric() async throws
    func disableBiometric() async throws
    func changePin(current: String, new: String) async throws
    func logout() async
}

extension SessionManager: SecuritySettings {}

/// S19 Profile and S20 Settings (PROF-01…08).
@MainActor
@Observable
final class ProfileViewModel {
    private(set) var profile: BankProfile?
    private(set) var devices: [RegisteredDevice] = []
    private(set) var failed = false
    private(set) var isWorking = false
    private(set) var error: LocalizedStringResource?
    /// The language was changed; it takes effect the next time the app opens.
    private(set) var languagePendingRestart: AppLanguage?

    private let repository: ProfileRepository
    private let security: SecuritySettings
    private let biometrics: BiometricAvailability
    private let applyLanguage: (AppLanguage) -> Void

    init(
        repository: ProfileRepository,
        security: SecuritySettings,
        biometrics: BiometricAvailability,
        applyLanguage: @escaping (AppLanguage) -> Void = AppLanguageSetting.apply
    ) {
        self.repository = repository
        self.security = security
        self.biometrics = biometrics
        self.applyLanguage = applyLanguage
    }

    var isBiometricEnabled: Bool { security.isBiometricEnabled }
    var canUseBiometric: Bool { biometrics.isAvailable || security.isBiometricEnabled }
    var unreadCount: Int { profile?.unreadNotifications ?? 0 }
    /// The language shown in the menu: the one chosen, even before the app restarts.
    var language: AppLanguage { languagePendingRestart ?? AppLanguage.current }

    func load() async {
        do {
            async let devices = repository.devices()
            profile = try await repository.profile()
            self.devices = try await devices
            failed = false
        } catch {
            failed = profile == nil
        }
    }

    func refreshUnread() async {
        guard let latest = try? await repository.profile() else { return }
        profile?.unreadNotifications = latest.unreadNotifications
    }

    func setUnread(_ count: Int) {
        profile?.unreadNotifications = count
    }

    // MARK: Notifications (PROF-05, NOTI-01/02)

    func setTransactionAlerts(_ isOn: Bool) async {
        await updatePreferences(PreferencesChange(transactions: isOn)) { $0.transactions = isOn }
    }

    func setMarketing(_ isOn: Bool) async {
        await updatePreferences(PreferencesChange(marketing: isOn)) { $0.marketing = isOn }
    }

    // MARK: Language (PROF-04)

    /// Saves the choice on the server (push text language) and on the phone (app language after a restart).
    func setLanguage(_ language: AppLanguage) async {
        guard language != self.language else { return }
        await updatePreferences(PreferencesChange(language: language)) { $0.language = language }
        guard error == nil else { return }
        applyLanguage(language)
        languagePendingRestart = language == AppLanguage.current ? nil : language
    }

    /// Shows the change at once and puts it back if the server refuses.
    private func updatePreferences(_ change: PreferencesChange, optimistic: (inout NotificationPreferences) -> Void) async {
        guard var profile else { return }
        let before = profile.preferences
        optimistic(&profile.preferences)
        self.profile = profile
        error = nil
        do {
            self.profile?.preferences = try await repository.updatePreferences(change)
        } catch {
            self.profile?.preferences = before
            self.error = PaymentErrors.message(for: error)
        }
    }

    // MARK: Security (PROF-02, PROF-03, PROF-08)

    func setBiometric(_ isOn: Bool) async {
        guard isOn != security.isBiometricEnabled, !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            if isOn {
                try await security.enableBiometric()
            } else {
                try await security.disableBiometric()
            }
            devices = (try? await repository.devices()) ?? devices
        } catch {
            self.error = PaymentErrors.message(for: error)
        }
    }

    func makeChangePin() -> ChangePinViewModel {
        ChangePinViewModel(security: security)
    }

    /// Signs out and unbinds this iPhone; the app returns to Welcome.
    func logout() async {
        isWorking = true
        await security.logout()
        isWorking = false
    }
}

/// The app language comes from `AppleLanguages`; changing it applies on the next launch.
enum AppLanguageSetting {
    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }
}
