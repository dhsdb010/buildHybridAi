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
        #if DEBUG
          // `-offlineFor 30`: act offline for the first 30 s after launch, then come back online
          // (to try offline drafts and the catch-up pass in the simulator).
          if let until = Connectivity.fakeOfflineUntil, Date() < until { self?.isOnline = false; return }
        #endif
        self?.isOnline = online
        self?.isExpensive = expensive
        self?.isConstrained = constrained
        self?.interface = iface
      }
    }
    monitor.start(queue: DispatchQueue(label: "Connectivity"))
    #if DEBUG
      if let until = Self.fakeOfflineUntil {
        isOnline = false
        Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
          self?.isOnline = true
        }
      }
    #endif
  }

  #if DEBUG
    private static let fakeOfflineUntil: Date? = {
      let s = UserDefaults.standard.double(forKey: "offlineFor")
      return s > 0 ? Date().addingTimeInterval(s) : nil
    }()
  #endif

  /// Good connection for deferred cloud work (Catch-up pass).
  var isGoodForCloud: Bool { isOnline && !isExpensive && !isConstrained }
}
