import Foundation
import SwiftData

/// The AI call log on the phone (`RoutingEntry` in SwiftData). The newest calls that fit in
/// `detailBudgetBytes` stay in full detail; older ones are compacted into daily `RoutingSummary` rows, so the whole trip's numbers are
/// kept until the traveler clears the log. Exportable as CSV for real-device numbers.
enum RoutingLog {
  /// How much detail to keep, by estimated size: the newest rows that fit stay in full detail,
  /// older ones are compacted into daily summaries (nothing is lost from the trip's numbers).
  /// About 0.5 KB per row, so 10 MB ≈ 20,000 calls, far more than one trip.
  static let detailBudgetBytes = 10 * 1024 * 1024

  /// Rough size of one row in the store: its text plus fixed overhead.
  static func estimatedBytes(_ e: RoutingEntry) -> Int {
    let text = [e.task, e.kind, e.requestedRoute ?? "", e.source ?? "", e.reason, e.outcome, e.network,
                e.detail ?? "", e.note ?? ""]
    return 120 + text.reduce(0) { $0 + $1.utf8.count }
  }

  /// Compacts the oldest rows once the detailed log is over `budget` bytes.
  @MainActor
  static func compact(_ context: ModelContext, budget: Int = detailBudgetBytes) {
    let newestFirst = (try? context.fetch(FetchDescriptor<RoutingEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? []
    var used = 0
    var keep = 0
    for e in newestFirst {
      used += estimatedBytes(e)
      if used > budget { break }
      keep += 1
    }
    compact(context, keep: keep)
  }

  /// Moves the oldest rows beyond `keep` into daily summaries (one per day + task + where it ran + result).
  @MainActor
  static func compact(_ context: ModelContext, keep: Int) {
    let total = (try? context.fetchCount(FetchDescriptor<RoutingEntry>())) ?? 0
    guard total > keep else { return }
    var old = FetchDescriptor<RoutingEntry>(sortBy: [SortDescriptor(\.timestamp)])
    old.fetchLimit = total - keep
    let rows = (try? context.fetch(old)) ?? []
    var summaries = (try? context.fetch(FetchDescriptor<RoutingSummary>())) ?? []
    let calendar = Calendar.current
    for e in rows {
      let day = calendar.startOfDay(for: e.timestamp)
      let s: RoutingSummary
      if let found = summaries.first(where: {
        $0.day == day && $0.task == e.task && $0.kind == e.kind && $0.requestedRoute == e.requestedRoute
          && $0.source == e.source && $0.outcome == e.outcome && $0.network == e.network
      }) {
        s = found
      } else {
        s = RoutingSummary(day: day, task: e.task, kind: e.kind, requestedRoute: e.requestedRoute,
                           source: e.source, outcome: e.outcome, network: e.network, firstAt: e.timestamp)
        context.insert(s)
        summaries.append(s)
      }
      s.count += 1
      s.totalLatencyMs += e.latencyMs
      s.firstAt = min(s.firstAt, e.timestamp)
      s.lastAt = max(s.lastAt, e.timestamp)
      context.delete(e)
    }
    try? context.save()
  }

  /// Totals over detailed rows and compacted days together.
  struct Totals: Equatable {
    var requests = 0, device = 0, cloud = 0, improved = 0, failed = 0
  }

  static func totals(_ entries: [RoutingEntry], _ summaries: [RoutingSummary]) -> Totals {
    var t = Totals()
    func add(_ n: Int, route: String?, source: String?, outcome: String) {
      if route != nil || outcome != "ok" { t.requests += n }
      if source == "onDevice" { t.device += n }
      if source == "inCloud" { t.cloud += n }
      if outcome == "improved" { t.improved += n }
      if outcome == "blocked" || outcome == "error" { t.failed += n }
    }
    for e in entries { add(1, route: e.requestedRoute, source: e.source, outcome: e.outcome) }
    for s in summaries { add(s.count, route: s.requestedRoute, source: s.source, outcome: s.outcome) }
    return t
  }

  static let columns = ["time", "task", "kind", "route_requested", "ran_on", "latency_ms",
                        "outcome", "network", "reason", "note", "error", "calls"]

  /// Compacted days first (latency = average, calls = how many), then each detailed row (calls = 1).
  static func csv(_ entries: [RoutingEntry], summaries: [RoutingSummary] = []) -> String {
    let time = ISO8601DateFormatter()
    let day = ISO8601DateFormatter(); day.formatOptions = [.withFullDate]
    let compacted = summaries.sorted { $0.firstAt < $1.firstAt }.map { s in
      [day.string(from: s.day), s.task, s.kind, s.requestedRoute ?? "", s.source ?? "", "\(s.averageLatencyMs)",
       s.outcome, s.network, "", "compacted: \(s.count) calls, average time", "", "\(s.count)"]
        .map(quote).joined(separator: ",")
    }
    let rows = entries.sorted { $0.timestamp < $1.timestamp }.map { e in
      [time.string(from: e.timestamp), e.task, e.kind, e.requestedRoute ?? "", e.source ?? "",
       "\(e.latencyMs)", e.outcome, e.network, e.reason, e.note ?? "", e.detail ?? "", "1"]
        .map(quote).joined(separator: ",")
    }
    return ([columns.joined(separator: ",")] + compacted + rows).joined(separator: "\n") + "\n"
  }

  static func quote(_ s: String) -> String {
    s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
      ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
  }
}
