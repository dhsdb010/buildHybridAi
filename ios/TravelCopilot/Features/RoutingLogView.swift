import SwiftUI
import SwiftData

/// Every AI request and where it ran: the hybrid behavior, visible in the product.
struct RoutingLogView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \RoutingEntry.timestamp, order: .reverse) private var entries: [RoutingEntry]
  @State private var filter = 0

  private var shown: [RoutingEntry] { filter == 0 ? entries : entries.filter { $0.outcome == "deferred" } }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          MTALabel("\(entries.count) requests")
          Text("Where AI ran").mta(.displayMedium).foregroundStyle(MTA.text)
          GridRow4 {
            NumberBox(value: "\(entries.filter { $0.source == "onDevice" }.count)", caption: "Device", style: .status(.onTrack))
            NumberBox(value: "\(entries.filter { $0.source == "inCloud" }.count)", caption: "Cloud", style: .filled)
            NumberBox(value: "\(entries.filter { $0.outcome == "deferred" }.count)", caption: "Deferred")
            NumberBox(value: "\(entries.filter { $0.outcome == "blocked" || $0.outcome == "error" }.count)", caption: "Failed")
          }
          MTASegmented(options: ["All", "Waiting for Wi-Fi"], selection: $filter)
          MTALabel("Latest")
          if shown.isEmpty {
            Text(filter == 0 ? "No AI requests yet." : "Nothing is waiting for Wi-Fi.").mta(.body1).foregroundStyle(MTA.text2)
          }
          LazyVStack(spacing: 0) {
            ForEach(shown) { e in LogRow(entry: e) }
          }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .navigationTitle("Routing log")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Clear", role: .destructive) { entries.forEach(context.delete) }.disabled(entries.isEmpty)
        }
      }
    }
  }
}

private struct LogRow: View {
  let entry: RoutingEntry

  var body: some View {
    HStack(spacing: 14) {
      TripBullet(systemName: mark.symbol, status: mark.status, size: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(Self.names[entry.task] ?? entry.task).mta(.subheadNormal).foregroundStyle(MTA.text)
        Text("\(entry.kind.capitalized) · \(entry.network) · \(entry.reason)").mta(.body2).foregroundStyle(MTA.text2).lineLimit(2)
        if let d = entry.detail { Text(d).mta(.body2).foregroundStyle(MTA.urgent).lineLimit(2) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      MTALabel(entry.latencyMs > 0 ? SourceChip.format(entry.latencyMs) : "—", color: MTA.text)
    }
    .padding(.vertical, 12)
    .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle).frame(height: 1) }
    .accessibilityElement(children: .combine)
  }

  static let names = [
    "classifyAsk": "Ask · classify", "translate": "Say · translate", "translateReply": "Reply · translate",
    "parseBooking": "Prepare · parse booking", "destinationPack": "Prepare · destination pack",
  ]

  /// iphone = on-device · icloud = cloud · icloud.dashed = waiting for Wi-Fi · exclamationmark = failed
  private var mark: (symbol: String, status: MTAStatus) {
    switch (entry.outcome, entry.source) {
    case ("ok", "onDevice"): ("iphone", .onTrack)
    case ("ok", _): ("icloud", .accent)
    case ("deferred", _): ("icloud.dashed", .notice)
    default: ("exclamationmark", .urgent)
    }
  }
}
