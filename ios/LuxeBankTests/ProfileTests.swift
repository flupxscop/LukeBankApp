import Foundation
import Testing
@testable import LuxeBank

@MainActor
final class FakeSecurity: SecuritySettings {
    var isBiometricEnabled = true
    var changePinError: Error?
    private(set) var changedPins: [(String, String)] = []
    private(set) var loggedOut = false

    func enableBiometric() async throws { isBiometricEnabled = true }
    func disableBiometric() async throws { isBiometricEnabled = false }

    func changePin(current: String, new: String) async throws {
        if let changePinError { throw changePinError }
        changedPins.append((current, new))
    }

    func logout() async { loggedOut = true }
}

struct FakeBiometrics: BiometricAvailability {
    var isAvailable = true
}

@MainActor
struct ProfileViewModelTests {
    let repository: MockProfileRepository = {
        let repository = MockProfileRepository(language: .thai)
        repository.delay = .zero
        return repository
    }()
    let security = FakeSecurity()

    private func makeViewModel(applied: @escaping (AppLanguage) -> Void = { _ in }) -> ProfileViewModel {
        ProfileViewModel(repository: repository, security: security, biometrics: FakeBiometrics(), applyLanguage: applied)
    }

    @Test func loadsProfileManagerAndDevices() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        #expect(viewModel.profile?.tier == "GOLD")
        #expect(viewModel.profile?.relationshipManager?.phone == "021234567")
        #expect(viewModel.unreadCount == 2)
        #expect(viewModel.devices.filter(\.isCurrent).count == 1)
    }

    @Test func showsAFailureOnlyWhenNothingLoaded() async {
        repository.shouldFail = true
        let viewModel = makeViewModel()
        await viewModel.load()
        #expect(viewModel.failed)
    }

    @Test func preferenceTogglesSaveAndRollBackOnFailure() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.setMarketing(true)
        #expect(viewModel.profile?.preferences.marketing == true)

        repository.shouldFail = true
        await viewModel.setTransactionAlerts(false)
        #expect(viewModel.profile?.preferences.transactions == true)
        #expect(viewModel.error != nil)
    }

    @Test func languageIsSavedOnTheServerAndAppliedAfterRestart() async {
        var applied: AppLanguage?
        let viewModel = makeViewModel { applied = $0 }
        await viewModel.load()
        let other: AppLanguage = AppLanguage.current == .thai ? .english : .thai

        await viewModel.setLanguage(other)

        #expect(applied == other)
        #expect(viewModel.language == other)
        #expect(viewModel.languagePendingRestart == other)
        #expect(viewModel.profile?.preferences.language == other)
    }

    @Test func languageIsNotAppliedWhenTheServerRefuses() async {
        var applied: AppLanguage?
        let viewModel = makeViewModel { applied = $0 }
        await viewModel.load()
        repository.shouldFail = true
        await viewModel.setLanguage(AppLanguage.current == .thai ? .english : .thai)
        #expect(applied == nil)
        #expect(viewModel.languagePendingRestart == nil)
    }

    @Test func faceIDToggleAndLogoutGoThroughTheSession() async {
        let viewModel = makeViewModel()
        await viewModel.setBiometric(false)
        #expect(!viewModel.isBiometricEnabled)
        await viewModel.setBiometric(true)
        #expect(viewModel.isBiometricEnabled)
        await viewModel.logout()
        #expect(security.loggedOut)
    }
}

@MainActor
struct ChangePinViewModelTests {
    let security = FakeSecurity()

    private func enter(_ pin: String, into viewModel: ChangePinViewModel) async {
        for digit in pin.compactMap(\.wholeNumberValue) { await viewModel.appendDigit(digit) }
    }

    @Test func changesThePinAfterCurrentNewAndConfirm() async {
        let viewModel = ChangePinViewModel(security: security)
        await enter("482193", into: viewModel)
        #expect(viewModel.step == .new)
        await enter("703915", into: viewModel)
        #expect(viewModel.step == .confirm)
        await enter("703915", into: viewModel)
        #expect(viewModel.step == .done)
        #expect(security.changedPins.first?.0 == "482193")
        #expect(security.changedPins.first?.1 == "703915")
    }

    @Test func rejectsWeakSameAndMismatchedPinsLocally() async {
        let viewModel = ChangePinViewModel(security: security)
        await enter("482193", into: viewModel)
        await enter("123456", into: viewModel)
        #expect(viewModel.step == .new)
        #expect(viewModel.error == "error.pinWeak")
        await enter("482193", into: viewModel)
        #expect(viewModel.step == .new)
        await enter("703915", into: viewModel)
        await enter("703916", into: viewModel)
        #expect(viewModel.step == .new)
        #expect(viewModel.error == "error.pinMismatch")
        #expect(security.changedPins.isEmpty)
    }

    @Test func aWrongCurrentPinStartsAgain() async {
        security.changePinError = APIError.server(code: "PIN_INVALID", message: "invalid", remainingAttempts: 3)
        let viewModel = ChangePinViewModel(security: security)
        await enter("111222", into: viewModel)
        await enter("703915", into: viewModel)
        await enter("703915", into: viewModel)
        #expect(viewModel.step == .current)
        #expect(viewModel.error == "error.pinInvalid \(3)")
        #expect(viewModel.pin.isEmpty)
    }
}

@MainActor
struct InboxViewModelTests {
    let repository: MockProfileRepository = {
        let repository = MockProfileRepository(language: .thai)
        repository.delay = .zero
        return repository
    }()

    @Test func opensMarksReadAndReportsTheUnreadCount() async throws {
        var reported: [Int] = []
        let viewModel = InboxViewModel(repository: repository) { reported.append($0) }
        await viewModel.load()
        #expect(viewModel.items.count == 4)
        #expect(viewModel.unreadCount == 2)

        let unread = try #require(viewModel.items.first { !$0.isRead })
        await viewModel.open(unread)
        #expect(viewModel.unreadCount == 1)
        await viewModel.open(unread)
        #expect(viewModel.unreadCount == 1)

        await viewModel.markAllRead()
        #expect(viewModel.unreadCount == 0)
        #expect(!viewModel.items.contains { !$0.isRead })
        #expect(reported.last == 0)
        let after = try await repository.profile()
        #expect(after.unreadNotifications == 0)
    }

    @Test func putsTheReadStateBackWhenTheServerFails() async {
        let viewModel = InboxViewModel(repository: repository)
        await viewModel.load()
        repository.shouldFail = true
        await viewModel.markAllRead()
        #expect(viewModel.unreadCount == 2)
        #expect(viewModel.items.contains { !$0.isRead })
    }

    @Test func pagesWithTheCursor() async {
        let now = Date()
        for index in 0..<30 {
            repository.deliver(InboxItem(
                id: UUID(), kind: .transaction, title: "เงินเข้า ฿\(index)", body: "", createdAt: now.addingTimeInterval(Double(-index)), isRead: true
            ))
        }
        let viewModel = InboxViewModel(repository: repository)
        await viewModel.load()
        #expect(viewModel.items.count == MockProfileRepository.pageSize)
        #expect(viewModel.hasMore)
        await viewModel.loadMore()
        #expect(viewModel.items.count == 34)
        #expect(!viewModel.hasMore)
    }
}

extension SessionManagerTests {
    @Test func changingThePinChecksTheCurrentOne() async throws {
        let session = try await registeredSession()
        await #expect(throws: APIError.self) { try await session.changePin(current: "111222", new: "703915") }
        try await session.changePin(current: "482193", new: "703915")
        session.lock()
        try await session.unlock(pin: "703915")
        #expect(session.state == .unlocked)
    }

    @Test func turningFaceIDOffDeletesTheKey() async throws {
        let session = try await registeredSession()
        try await session.enableBiometric()
        #expect(session.isBiometricEnabled)
        try await session.disableBiometric()
        #expect(!session.isBiometricEnabled)
        #expect(!keys.hasKey(.biometric))
    }
}

extension APIClientTests {
    @MainActor
    struct DeviceIntegrityHeaderTests {
        @Test func aCompromisedPhoneSaysSoOnEveryRequest() async throws {
            _ = StubProtocol.client(status: 200, body: "{}")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubProtocol.self]
            let client = APIClient(
                baseURL: URL(string: "https://api.test/api/v1") ?? URL(fileURLWithPath: "/"),
                session: URLSession(configuration: configuration),
                deviceID: { nil },
                isDeviceCompromised: true
            )
            try await client.sendWithoutResponse(method: "POST", path: "transfers")
            #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "X-Device-Integrity") == "compromised")

            _ = try await StubProtocol.client(status: 200, body: "{}").sendWithoutResponse(method: "GET", path: "accounts")
            #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "X-Device-Integrity") == nil)
        }

        @Test func theMockRefusesPaymentsAndRevealsLikeTheServer() async throws {
            let cards = MockCardRepository()
            cards.delay = .zero
            cards.deviceCompromised = true
            let auth = PaymentAuthorization(method: .biometric, signature: Data(), pin: nil)
            do {
                _ = try await cards.reveal(cardID: MockCardRepository.debitID, challenge: "c", authorization: auth)
                Issue.record("Reveal should be refused")
            } catch let error as APIError {
                #expect(error.code == "DEVICE_COMPROMISED")
                #expect(PaymentErrors.message(for: error) == "error.deviceCompromised")
            }
        }
    }

    @MainActor
    struct RemoteProfileRepositoryTests {
        private let tokens = StubTokens()

        @Test func decodesTheProfileAndSendsPreferenceChanges() async throws {
            let client = StubProtocol.client(status: 200, body: Self.meJSON)
            let repository = RemoteProfileRepository(api: AuthorizedAPI(client: client, tokens: tokens))

            let profile = try await repository.profile()
            #expect(profile.relationshipManager?.name == "นกนางน้อย ใจดี")
            #expect(profile.preferences == NotificationPreferences(language: .thai, transactions: true, marketing: false))
            #expect(profile.unreadNotifications == 3)

            StubProtocol.body = Data(#"{"language":"en","notifyTransactions":true,"notifyMarketing":true,"notifySecurity":true}"#.utf8)
            let updated = try await repository.updatePreferences(PreferencesChange(language: .english, marketing: true))
            #expect(updated.language == .english)
            let request = try #require(StubProtocol.lastRequest)
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/v1/me/preferences")
            let json = try JSONSerialization.jsonObject(with: StubProtocol.body(of: request)) as? [String: Any]
            #expect(json?["language"] as? String == "en")
            #expect(json?["notifyMarketing"] as? Bool == true)
            #expect(json?["notifyTransactions"] == nil)
        }

        @Test func decodesTheInboxAndRegistersThePushToken() async throws {
            let client = StubProtocol.client(status: 200, body: Self.inboxJSON)
            let repository = RemoteProfileRepository(api: AuthorizedAPI(client: client, tokens: tokens))

            let page = try await repository.notifications(cursor: nil)
            #expect(page.items.first?.kind == .security)
            #expect(page.items.first?.isRead == false)
            #expect(page.unreadCount == 1)
            #expect(page.nextCursor == "abc")

            StubProtocol.status = 204
            StubProtocol.body = Data()
            try await repository.registerPushToken("a1b2c3d4e5f6a7b8")
            let request = try #require(StubProtocol.lastRequest)
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/api/v1/me/devices/current/push-token")
            let json = try JSONSerialization.jsonObject(with: StubProtocol.body(of: request)) as? [String: Any]
            #expect(json?["token"] as? String == "a1b2c3d4e5f6a7b8")
        }

        static let meJSON = """
        {"firstName":"นกน้อย","lastName":"ใจงาม","tier":"GOLD","maskedPhone":"08X-XXX-4521",
         "relationshipManager":{"name":"นกนางน้อย ใจดี","phone":"021234567","hours":"จันทร์–ศุกร์ 09:00–18:00"},
         "preferences":{"language":"th","notifyTransactions":true,"notifyMarketing":false,"notifySecurity":true},
         "unreadNotifications":3}
        """

        static let inboxJSON = """
        {"items":[{"id":"7C1D7D0B-5C4B-4F1E-9A31-0B6B0A9C1E11","kind":"security","title":"ระงับบัตรแล้ว","body":"บัตร x8821",
          "createdAt":"2026-10-11T08:15:30.123456Z","read":false}],"nextCursor":"abc","unreadCount":1}
        """
    }
}
