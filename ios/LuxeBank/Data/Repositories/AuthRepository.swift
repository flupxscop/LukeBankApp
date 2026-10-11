import Foundation

/// AUTH-01…09 against `/api/v1/auth`. Errors are `APIError` with the server codes
/// (INVALID_CREDENTIALS, OTP_INVALID, PIN_LOCKED, …).
protocol AuthRepository {
    func startRegistration(citizenID: String, password: String) async throws -> RegistrationChallenge
    func verifyOTP(reference: String, code: String) async throws -> String
    func registerDevice(registrationToken: String, pin: String, deviceName: String, publicKey: Data) async throws -> AuthSession
    func challenge(deviceID: UUID) async throws -> String
    func login(deviceID: UUID, challenge: String, signature: Data, method: LoginMethod, pin: String?) async throws -> AuthSession
    func enableBiometric(publicKey: Data, accessToken: String) async throws
    func refresh(refreshToken: String) async throws -> AuthSession
    func profile(accessToken: String) async throws -> CustomerProfile
    func logout(accessToken: String) async throws
}

final class RemoteAuthRepository: AuthRepository {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func startRegistration(citizenID: String, password: String) async throws -> RegistrationChallenge {
        try await client.send(APIRequest(method: "POST", path: "auth/register", body: ["citizenId": citizenID, "password": password]))
    }

    func verifyOTP(reference: String, code: String) async throws -> String {
        struct Response: Decodable { let registrationToken: String }
        let response: Response = try await client.send(APIRequest(method: "POST", path: "auth/otp/verify", body: ["otpRef": reference, "code": code]))
        return response.registrationToken
    }

    func registerDevice(registrationToken: String, pin: String, deviceName: String, publicKey: Data) async throws -> AuthSession {
        let body = [
            "registrationToken": registrationToken,
            "pin": pin,
            "deviceName": deviceName,
            "devicePublicKey": publicKey.base64EncodedString(),
        ]
        return try await client.send(APIRequest(method: "POST", path: "auth/devices", body: body))
    }

    func challenge(deviceID: UUID) async throws -> String {
        struct Response: Decodable { let challenge: String }
        let response: Response = try await client.send(APIRequest(method: "POST", path: "auth/challenge", body: ["deviceId": deviceID.uuidString]))
        return response.challenge
    }

    func login(deviceID: UUID, challenge: String, signature: Data, method: LoginMethod, pin: String?) async throws -> AuthSession {
        struct Body: Encodable {
            let deviceId: UUID
            let challenge: String
            let signature: String
            let method: LoginMethod
            let pin: String?
        }
        let body = Body(deviceId: deviceID, challenge: challenge, signature: signature.base64EncodedString(), method: method, pin: pin)
        return try await client.send(APIRequest(method: "POST", path: "auth/login", body: body))
    }

    func enableBiometric(publicKey: Data, accessToken: String) async throws {
        try await client.sendWithoutResponse(
            method: "PUT", path: "auth/biometric", body: ["biometricPublicKey": publicKey.base64EncodedString()], accessToken: accessToken
        )
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        try await client.send(APIRequest(method: "POST", path: "auth/refresh", body: ["refreshToken": refreshToken]))
    }

    func profile(accessToken: String) async throws -> CustomerProfile {
        try await client.send(APIRequest(method: "GET", path: "me", accessToken: accessToken))
    }

    func logout(accessToken: String) async throws {
        try await client.sendWithoutResponse(method: "POST", path: "auth/logout", accessToken: accessToken)
    }
}
