import Foundation
import Network
import Observation

/// NFR-08: whether the phone can reach the network. While offline the app keeps showing the data it last
/// loaded, marks it "Offline" and turns transactions off.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        // UI tests can't switch the simulator's network off.
        if arguments.contains("-SimulateOffline") {
            isOnline = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.luxebank.network-monitor"))
    }

    /// A fixed state for previews and tests.
    init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    deinit {
        monitor.cancel()
    }
}
