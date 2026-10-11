import Foundation

/// Supplies access tokens for authenticated calls; `SessionManager` in the app.
@MainActor
protocol AccessTokenProviding: AnyObject {
    func validAccessToken() async throws -> String
    func refreshAccessToken() async throws -> String
}

/// Sends authenticated requests. A 401 triggers one token refresh and a single retry;
/// if the refresh is rejected the session locks itself (AUTH-07).
final class AuthorizedAPI {
    private let client: APIClient
    private weak var tokens: AccessTokenProviding?

    init(client: APIClient, tokens: AccessTokenProviding) {
        self.client = client
        self.tokens = tokens
    }

    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        guard let tokens else { throw APIError.unauthorized }
        var authorized = request
        authorized.accessToken = try await tokens.validAccessToken()
        do {
            return try await client.send(authorized)
        } catch APIError.unauthorized {
            authorized.accessToken = try await tokens.refreshAccessToken()
            return try await client.send(authorized)
        }
    }
}
