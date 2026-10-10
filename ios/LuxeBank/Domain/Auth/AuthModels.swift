import Foundation

struct RegistrationChallenge: Equatable, Decodable {
    let otpRef: String
    let maskedPhone: String
    let expiresInSeconds: Int
}

struct AuthSession: Equatable, Decodable {
    let deviceId: UUID
    let accessToken: String
    let refreshToken: String
    let expiresInSeconds: Int
}

struct CustomerProfile: Equatable, Decodable {
    let firstName: String
    let tier: String
    let maskedPhone: String
}

enum LoginMethod: String, Encodable {
    case pin = "PIN"
    case biometric = "BIOMETRIC"
}

/// Thai national ID: 13 digits with a mod-11 check digit.
enum CitizenID {
    /// ASCII digits only; Thai digits (๑๒๓) are converted, everything else dropped.
    static func digits(of input: String) -> String {
        String(input.compactMap { character in character.wholeNumberValue.map(String.init) }.joined().prefix(13))
    }

    /// "1-2345-67890-12-1" while typing.
    static func formatted(_ input: String) -> String {
        let digits = Array(digits(of: input))
        var result = ""
        for (index, digit) in digits.enumerated() {
            if [1, 5, 10, 12].contains(index) { result.append("-") }
            result.append(digit)
        }
        return result
    }

    static func isValid(_ input: String) -> Bool {
        let values = digits(of: input).compactMap(\.wholeNumberValue)
        guard values.count == 13 else { return false }
        let sum = (0..<12).reduce(0) { $0 + values[$1] * (13 - $1) }
        return (11 - sum % 11) % 10 == values[12]
    }
}

/// AUTH-02 rules, shown live under the PIN dots and enforced again by the backend.
struct PinRules: Equatable {
    let notSequential: Bool
    let notRepeated: Bool

    init(_ pin: String) {
        let digits = pin.compactMap(\.wholeNumberValue)
        let steps = Set(zip(digits, digits.dropFirst()).map { $1 - $0 })
        notRepeated = Set(digits).count > 1
        notSequential = digits.count < 2 || (steps != [1] && steps != [-1])
    }

    static func isAcceptable(_ pin: String) -> Bool {
        let rules = PinRules(pin)
        return pin.count == 6 && pin.allSatisfy(\.isNumber) && rules.notSequential && rules.notRepeated
    }
}
