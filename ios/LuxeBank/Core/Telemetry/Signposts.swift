import OSLog

/// Named intervals around the flows customers wait on (spec NFR-01). Instruments shows them under
/// Points of Interest, and the performance tests read them with `XCTOSSignpostMetric`.
enum Signposts {
    static let subsystem = "com.luxebank.app"
    static let category = "Performance"
    private static let signposter = OSSignposter(subsystem: subsystem, category: category)

    enum Interval: String {
        /// From PIN / Face ID entry to an unlocked session.
        case unlock = "Unlock"
        /// From request to the dashboard's data on screen.
        case dashboardLoad = "DashboardLoad"
        /// First page of an account's transaction history.
        case historyLoad = "HistoryLoad"
        /// The app's own launch work: from `LuxeBankApp` being created to the first screen appearing.
        case startup = "Startup"

        fileprivate var name: StaticString {
            switch self {
            case .unlock: "Unlock"
            case .dashboardLoad: "DashboardLoad"
            case .historyLoad: "HistoryLoad"
            case .startup: "Startup"
            }
        }
    }

    private static var startupState: OSSignpostIntervalState?

    /// Called once from `LuxeBankApp.init`.
    static func beginStartup() {
        startupState = signposter.beginInterval(Interval.startup.name, id: signposter.makeSignpostID())
    }

    /// Called when the first screen appears; later calls do nothing.
    static func endStartup() {
        guard let state = startupState else { return }
        signposter.endInterval(Interval.startup.name, state)
        startupState = nil
    }

    /// Runs `work` inside a signpost interval.
    static func measure<T>(_ interval: Interval, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(interval.name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(interval.name, state) }
        return try await work()
    }
}
