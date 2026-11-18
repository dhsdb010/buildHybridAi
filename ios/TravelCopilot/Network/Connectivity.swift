import Foundation
import Network
import Observation

/// Publishes the network facts the routing policy cares about:
/// reachable at all, expensive (cellular / roaming / hotspot), constrained (Low Data Mode).
@MainActor
@Observable
final class Connectivity {
  private(set) var isOnline = true
  private(set) var isExpensive = false
  private(set) var isConstrained = false
  private(set) var interface = "unknown"

  private let monitor = NWPathMonitor()

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      let expensive = path.isExpensive
      let constrained = path.isConstrained
      let iface: String =
        path.usesInterfaceType(.wifi) ? "wifi"
        : path.usesInterfaceType(.cellular) ? "cellular"
        : path.usesInterfaceType(.wiredEthernet) ? "ethernet"
        : online ? "other" : "none"
      Task { @MainActor [weak self] in
        self?.isOnline = online
        self?.isExpensive = expensive
        self?.isConstrained = constrained
        self?.interface = iface
      }
    }
    monitor.start(queue: DispatchQueue(label: "Connectivity"))
  }

  /// Good connection for deferred cloud work (Catch-up pass).
  var isGoodForCloud: Bool { isOnline && !isExpensive && !isConstrained }
}
