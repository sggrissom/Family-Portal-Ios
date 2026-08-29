import Foundation
import Network

@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    var isConnected: Bool = true
    var onConnectivityRestored: (() -> Void)?

    private var wasConnected: Bool = true

    /// - Parameter startMonitoring: pass `false` to leave `isConnected` under the caller's control; a live `NWPathMonitor` overwrites whatever a test sets.
    init(startMonitoring: Bool = true) {
        guard startMonitoring else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let nowConnected = path.status == .satisfied

                if !self.wasConnected && nowConnected {
                    self.onConnectivityRestored?()
                }

                self.wasConnected = nowConnected
                self.isConnected = nowConnected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
