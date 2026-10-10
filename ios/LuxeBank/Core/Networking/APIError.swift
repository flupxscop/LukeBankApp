import Foundation

/// Errors surfaced to view models. Server errors carry the shared error body (spec section 9).
enum APIError: Error, Equatable {
    case server(code: String, message: String, remainingAttempts: Int?)
    case unauthorized
    case network
    case decoding

    var code: String? {
        if case .server(let code, _, _) = self { return code }
        return nil
    }

    var remainingAttempts: Int? {
        if case .server(_, _, let remaining) = self { return remaining }
        return nil
    }
}

struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
        let traceId: String?
        let remainingAttempts: Int?
    }

    let error: Detail
}
