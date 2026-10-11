import Foundation
import Testing
@testable import LuxeBank

struct CitizenIDTests {
    @Test func validatesChecksum() {
        #expect(CitizenID.isValid("1-2345-67890-12-1"))
        #expect(!CitizenID.isValid("1-2345-67890-12-4"))
        #expect(!CitizenID.isValid("123456789012"))
    }

    @Test func formatsWhileTyping() {
        #expect(CitizenID.formatted("1234567890121") == "1-2345-67890-12-1")
        #expect(CitizenID.formatted("12345") == "1-2345")
        #expect(CitizenID.formatted("1-2a3") == "1-23")
        #expect(CitizenID.formatted("12345678901219999") == "1-2345-67890-12-1")
        #expect(CitizenID.formatted("ๅ/-ภถุ") == "")
        #expect(CitizenID.formatted("๑๒๓๔๕") == "1-2345")
    }
}

struct PinRulesTests {
    @Test(arguments: ["123456", "654321", "111111", "12345", "12a456"])
    func rejectsWeakPins(pin: String) {
        #expect(!PinRules.isAcceptable(pin))
    }

    @Test(arguments: ["482193", "135790", "112233"])
    func acceptsReasonablePins(pin: String) {
        #expect(PinRules.isAcceptable(pin))
    }

    @Test func reportsRulesLive() {
        #expect(PinRules("123").notSequential == false)
        #expect(PinRules("111").notRepeated == false)
        #expect(PinRules("482").notSequential && PinRules("482").notRepeated)
    }
}

/// Stands in for the Secure Enclave in unit tests.
final class FakeKeyManager: DeviceKeyManaging {
    private(set) var keys: Set<String> = []
    var cancelBiometric = false

    func createKey(_ kind: DeviceKeyKind) throws -> Data {
        keys.insert(name(kind))
        return Data([0x04] + Array(repeating: 1, count: 64))
    }

    func hasKey(_ kind: DeviceKeyKind) -> Bool { keys.contains(name(kind)) }

    func sign(_ message: Data, with kind: DeviceKeyKind, reason: String) async throws -> Data {
        guard hasKey(kind) else { throw DeviceKeyError.missingKey }
        if kind == .biometric, cancelBiometric { throw DeviceKeyError.cancelled }
        return Data("sig".utf8)
    }

    func deleteKey(_ kind: DeviceKeyKind) { keys.remove(name(kind)) }

    private func name(_ kind: DeviceKeyKind) -> String { kind == .device ? "device" : "biometric" }
}

struct StubBiometrics: BiometricAvailability {
    var isAvailable: Bool
}

final class Clock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}

@MainActor
struct RegistrationFlowTests {
    let storage = InMemorySecureStorage()
    let keys = FakeKeyManager()
    let repository: MockAuthRepository = {
        let repository = MockAuthRepository()
        repository.delay = .zero
        return repository
    }()

    private func makeViewModel(biometrics: Bool = true) -> (RegistrationViewModel, SessionManager) {
        let session = SessionManager(repository: repository, storage: storage, keys: keys)
        let viewModel = RegistrationViewModel(
            repository: repository, session: session, keys: keys, biometrics: StubBiometrics(isAvailable: biometrics)
        )
        return (viewModel, session)
    }

    private func enter(_ digits: String, into viewModel: RegistrationViewModel, pin: Bool) async {
        for digit in digits.compactMap(\.wholeNumberValue) {
            if pin { await viewModel.appendPinDigit(digit) } else { await viewModel.appendOTPDigit(digit) }
        }
    }

    @Test func completesOnboardingWithFaceID() async {
        let (viewModel, session) = makeViewModel()
        #expect(session.state == .unregistered)

        viewModel.citizenID = "1-2345-6789"
        viewModel.citizenID = "1-2345-67890121x"
        #expect(viewModel.citizenID == "1-2345-67890-12-1")
        #expect(viewModel.citizenIDDigits == MockAuthRepository.demoCitizenID)
        viewModel.password = MockAuthRepository.demoPassword
        await viewModel.submitCredentials()
        #expect(viewModel.path == [.otp])
        #expect(viewModel.password.isEmpty)

        await enter("000000", into: viewModel, pin: false)
        #expect(viewModel.path == [.otp, .pin])

        await enter("482193", into: viewModel, pin: true)
        #expect(viewModel.isConfirmingPin)
        await enter("482193", into: viewModel, pin: true)
        #expect(viewModel.path.last == .biometric)
        #expect(session.state == .unregistered)
        #expect(session.deviceID != nil)
        #expect(keys.hasKey(.device))

        await viewModel.enableBiometric()
        #expect(session.isBiometricEnabled)
        #expect(session.state == .unlocked)
        #expect(session.customerFirstName == "นกน้อย")
    }

    @Test func skipsFaceIDStepWhenUnavailable() async {
        let (viewModel, session) = makeViewModel(biometrics: false)
        viewModel.citizenID = MockAuthRepository.demoCitizenID
        viewModel.password = MockAuthRepository.demoPassword
        await viewModel.submitCredentials()
        await enter("000000", into: viewModel, pin: false)
        await enter("482193", into: viewModel, pin: true)
        await enter("482193", into: viewModel, pin: true)
        #expect(session.state == .unlocked)
    }

    @Test func showsRemainingAttemptsForWrongPassword() async {
        let (viewModel, _) = makeViewModel()
        viewModel.citizenID = MockAuthRepository.demoCitizenID
        viewModel.password = "wrong"
        await viewModel.submitCredentials()
        #expect(viewModel.path.isEmpty)
        #expect(viewModel.error == "error.credentials.remaining \(4)")
    }

    @Test func rejectsWeakAndMismatchedPins() async {
        let (viewModel, _) = makeViewModel()
        viewModel.citizenID = MockAuthRepository.demoCitizenID
        viewModel.password = MockAuthRepository.demoPassword
        await viewModel.submitCredentials()
        await enter("000000", into: viewModel, pin: false)

        await enter("123456", into: viewModel, pin: true)
        #expect(viewModel.error == "error.pinWeak")
        #expect(!viewModel.isConfirmingPin)

        await enter("482193", into: viewModel, pin: true)
        await enter("482190", into: viewModel, pin: true)
        #expect(viewModel.error == "error.pinMismatch")
        #expect(!viewModel.isConfirmingPin)
    }

    @Test func wrongOTPClearsTheCode() async {
        let (viewModel, _) = makeViewModel()
        viewModel.citizenID = MockAuthRepository.demoCitizenID
        viewModel.password = MockAuthRepository.demoPassword
        await viewModel.submitCredentials()
        await enter("123123", into: viewModel, pin: false)
        #expect(viewModel.otpCode.isEmpty)
        #expect(viewModel.path == [.otp])
    }
}

@MainActor
struct SessionManagerTests {
    let storage = InMemorySecureStorage()
    let keys = FakeKeyManager()
    let clock = Clock()
    let repository: MockAuthRepository = {
        let repository = MockAuthRepository()
        repository.delay = .zero
        return repository
    }()

    func registeredSession() async throws -> SessionManager {
        let session = SessionManager(repository: repository, storage: storage, keys: keys, now: { [clock] in clock.now })
        _ = try keys.createKey(.device)
        let auth = try await repository.registerDevice(registrationToken: "t", pin: "482193", deviceName: "iPhone", publicKey: Data())
        try await session.storeRegistration(auth)
        session.finishOnboarding()
        return session
    }

    @Test func relaunchWithBoundDeviceStartsLocked() async throws {
        _ = try await registeredSession()
        let relaunched = SessionManager(repository: repository, storage: storage, keys: keys)
        #expect(relaunched.state == .locked)
        #expect(relaunched.customerFirstName == "นกน้อย")
    }

    @Test func unlocksWithCorrectPin() async throws {
        let session = try await registeredSession()
        session.lock()
        #expect(session.state == .locked)
        #expect(session.accessToken == nil)
        try await session.unlock(pin: "482193")
        #expect(session.state == .unlocked)
    }

    @Test func fiveWrongPinsResetTheDevice() async throws {
        let session = try await registeredSession()
        session.lock()
        for _ in 0..<4 {
            await #expect(throws: APIError.self) { try await session.unlock(pin: "908172") }
        }
        await #expect(throws: APIError.self) { try await session.unlock(pin: "908172") }
        #expect(session.state == .unregistered)
        #expect(session.resetReason == .pinLocked)
        #expect(!keys.hasKey(.device))
        #expect(storage.string(for: "session.deviceId") == nil)
    }

    @Test func locksAfterFiveMinutesOfInactivity() async throws {
        let session = try await registeredSession()
        clock.advance(299)
        session.checkInactivity()
        #expect(session.state == .unlocked)
        clock.advance(2)
        session.checkInactivity()
        #expect(session.state == .locked)
    }

    @Test func locksWhenBackgroundedForFiveMinutes() async throws {
        let session = try await registeredSession()
        session.didEnterBackground()
        clock.advance(60)
        session.didBecomeActive()
        #expect(session.state == .unlocked)

        session.didEnterBackground()
        clock.advance(301)
        session.didBecomeActive()
        #expect(session.state == .locked)
    }

    @Test func cancelledFaceIDKeepsTheLockScreen() async throws {
        let session = try await registeredSession()
        try await session.enableBiometric()
        session.lock()
        keys.cancelBiometric = true
        await #expect(throws: DeviceKeyError.cancelled) { try await session.unlockWithBiometric() }
        #expect(session.state == .locked)
        keys.cancelBiometric = false
        try await session.unlockWithBiometric()
        #expect(session.state == .unlocked)
    }

    @Test func logoutClearsEverything() async throws {
        let session = try await registeredSession()
        await session.logout()
        #expect(session.state == .unregistered)
        #expect(session.resetReason == nil)
        #expect(storage.string(for: "session.refreshToken") == nil)
    }
}

@Suite(.serialized)
struct APIClientTests {
    @Test func mapsServerErrorBody() async throws {
        let body = #"{"error":{"code":"PIN_INVALID","message":"PIN is incorrect","traceId":"t","remainingAttempts":3}}"#
        let client = StubProtocol.client(status: 401, body: body)
        await #expect(throws: APIError.server(code: "PIN_INVALID", message: "PIN is incorrect", remainingAttempts: 3)) {
            let _: CustomerProfile = try await client.send(APIRequest(method: "GET", path: "me"))
        }
    }

    @Test func mapsMissingAuthToUnauthorized() async throws {
        let client = StubProtocol.client(status: 401, body: #"{"error":{"code":"UNAUTHORIZED","message":"Authentication required"}}"#)
        await #expect(throws: APIError.unauthorized) {
            let _: CustomerProfile = try await client.send(APIRequest(method: "GET", path: "me"))
        }
    }

    @Test func sendsSecurityHeaders() async throws {
        let client = StubProtocol.client(status: 200, body: #"{"firstName":"Noknoi","tier":"GOLD","maskedPhone":"08X-XXX-4521"}"#)
        let profile: CustomerProfile = try await client.send(APIRequest(method: "GET", path: "me", accessToken: "abc"))
        #expect(profile.firstName == "Noknoi")
        let request = try #require(StubProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(request.value(forHTTPHeaderField: "X-Trace-Id") != nil)
        #expect(request.value(forHTTPHeaderField: "X-Device-Id") == StubProtocol.deviceID.uuidString)
    }
}

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    /// Responses served in order before falling back to `status`/`body`.
    nonisolated(unsafe) static var queue: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let deviceID = UUID()

    static func client(status: Int, body: String) -> APIClient {
        self.status = status
        self.body = Data(body.utf8)
        queue = []
        requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://api.test/api/v1") ?? URL(fileURLWithPath: "/"),
            session: URLSession(configuration: configuration),
            deviceID: { deviceID }
        )
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.requests.append(request)
        var status = Self.status
        var body = Self.body
        if !Self.queue.isEmpty {
            let next = Self.queue.removeFirst()
            status = next.status
            body = Data(next.body.utf8)
        }
        if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession moves bodies into a stream before they reach a URLProtocol.
    static func body(of request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return request.httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
