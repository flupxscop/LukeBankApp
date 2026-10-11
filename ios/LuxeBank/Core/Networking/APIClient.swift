import Foundation
import OSLog

struct APIRequest<Response: Decodable> {
    let method: String
    let path: String
    var body: Encodable?
    var accessToken: String?
    var query: [URLQueryItem] = []
    var headers: [String: String] = [:]
}

/// Thin JSON client for `/api/v1`. Adds the headers from spec section 9 and maps errors.
/// Never logs request or response bodies (spec 13.1 A09).
final class APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let deviceID: () -> UUID?
    private let logger = Logger(subsystem: "com.luxebank.app", category: "network")

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession, deviceID: @escaping () -> UUID?) {
        self.baseURL = baseURL
        self.session = session
        self.deviceID = deviceID
    }

    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        let data = try await perform(
            request.method, request.path, query: request.query, headers: request.headers, body: request.body, token: request.accessToken
        )
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    func sendWithoutResponse(method: String, path: String, body: Encodable? = nil, accessToken: String? = nil) async throws {
        _ = try await perform(method, path, body: body, token: accessToken)
    }

    private func perform(
        _ method: String, _ path: String, query: [URLQueryItem] = [], headers: [String: String] = [:], body: Encodable?, token accessToken: String?
    ) async throws -> Data {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(Locale.current.language.languageCode?.identifier == "en" ? "en" : "th", forHTTPHeaderField: "Accept-Language")
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Trace-Id")
        if let deviceID = deviceID() {
            urlRequest.setValue(deviceID.uuidString, forHTTPHeaderField: "X-Device-Id")
        }
        if let accessToken {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            logger.error("Request \(method, privacy: .public) \(path, privacy: .public) failed: network")
            throw APIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network }
        guard (200..<300).contains(http.statusCode) else {
            logger.notice("Request \(method, privacy: .public) \(path, privacy: .public) -> \(http.statusCode)")
            if let body = try? decoder.decode(APIErrorBody.self, from: data) {
                if body.error.code == "UNAUTHORIZED" { throw APIError.unauthorized }
                throw APIError.server(code: body.error.code, message: body.error.message, remainingAttempts: body.error.remainingAttempts)
            }
            throw http.statusCode == 401 ? APIError.unauthorized : APIError.network
        }
        return data
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable

    init(_ value: Encodable) { self.value = value }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
