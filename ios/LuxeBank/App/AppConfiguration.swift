import Foundation

/// Where the app gets its data (spec 7.0, 13.1 M5).
/// Debug builds use mock repositories unless `-LuxeBankAPI <url>` is passed. Release builds always use the
/// backend from `LuxeBankAPIBaseURL` with the SPKI pins in `LuxeBankAPIPins`, and refuse to start without
/// both, so a release can never ship mock money or an unpinned connection.
enum AppConfiguration: Equatable {
    case mock
    case remote(baseURL: URL, pins: Set<String>)

    enum ConfigurationError: Error, Equatable {
        case missingBaseURL
        case missingPins
    }

    static func resolve(arguments: [String], info: [String: Any], isDebug: Bool) -> Result<AppConfiguration, ConfigurationError> {
        let pins = Set(
            ((info["LuxeBankAPIPins"] as? String) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        if isDebug {
            guard let index = arguments.firstIndex(of: "-LuxeBankAPI"), arguments.indices.contains(index + 1),
                  let url = URL(string: arguments[index + 1]) else { return .success(.mock) }
            return .success(.remote(baseURL: url, pins: pins))
        }
        guard let value = info["LuxeBankAPIBaseURL"] as? String, let url = URL(string: value), url.scheme == "https" else {
            return .failure(.missingBaseURL)
        }
        guard !pins.isEmpty else { return .failure(.missingPins) }
        return .success(.remote(baseURL: url, pins: pins))
    }

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppConfiguration {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        switch resolve(arguments: arguments, info: Bundle.main.infoDictionary ?? [:], isDebug: isDebug) {
        case .success(let configuration):
            return configuration
        case .failure(let error):
            // Fail fast like the backend's prod guard: set LUXEBANK_API_BASE_URL and LUXEBANK_API_PINS for release builds.
            fatalError("Release build is not configured for a backend: \(error)")
        }
    }
}
