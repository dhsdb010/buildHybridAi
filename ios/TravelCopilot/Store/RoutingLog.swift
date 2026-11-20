import Foundation
import SwiftData

/// The AI call log on the phone (`RoutingEntry` in SwiftData): kept to a fixed size, and exportable
/// as CSV so real-device numbers (share on-device, latency, failures) can be taken off the phone.
enum RoutingLog {
  static let limit = 500

  /// Deletes the oldest rows beyond `limit`.
  @MainActor
  static func trim(_ context: ModelContext, keep: Int = limit) {
    let total = (try? context.fetchCount(FetchDescriptor<RoutingEntry>())) ?? 0
    guard total > keep else { return }
    var old = FetchDescriptor<RoutingEntry>(sortBy: [SortDescriptor(\.timestamp)])
    old.fetchLimit = total - keep
    for e in (try? context.fetch(old)) ?? [] { context.delete(e) }
    try? context.save()
  }

  static let columns = ["time", "task", "kind", "route_requested", "ran_on", "latency_ms",
                        "outcome", "network", "reason", "note", "error"]

  /// One row per entry, oldest first, RFC 4180 quoting.
  static func csv(_ entries: [RoutingEntry]) -> String {
    let time = ISO8601DateFormatter()
    let rows = entries.sorted { $0.timestamp < $1.timestamp }.map { e in
      [time.string(from: e.timestamp), e.task, e.kind, e.requestedRoute ?? "", e.source ?? "",
       "\(e.latencyMs)", e.outcome, e.network, e.reason, e.note ?? "", e.detail ?? ""]
        .map(quote).joined(separator: ",")
    }
    return ([columns.joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
  }

  static func quote(_ s: String) -> String {
    s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
      ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
  }
}
