import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The log as a .csv file for the share sheet.
struct LogCSV: Transferable {
  let text: String
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
      let stamp = Date.now.formatted(.iso8601.year().month().day())
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("travel-copilot-ai-log-\(stamp).csv")
      try csv.text.write(to: url, atomically: true, encoding: .utf8)
      return SentTransferredFile(url)
    }
  }
}

/// Every AI request and where it ran: the hybrid behavior, visible in the product.
struct RoutingLogView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \RoutingEntry.timestamp, order: .reverse) private var entries: [RoutingEntry]
  @State private var filter = 0
  @State private var selected: RoutingEntry?

  /// "Catch-up": the drafts made offline and what the cloud did with them later.
  private var shown: [RoutingEntry] {
    filter == 0 ? entries : entries.filter { $0.task.hasPrefix("Catch-up") || $0.task == "translate" || $0.outcome == "deferred" }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Notes ("Catch-up · back online") aren't AI requests, so they don't count here.
          MTALabel("\(entries.filter { $0.requestedRoute != nil || $0.outcome != "ok" }.count) AI requests · keeps the latest \(RoutingLog.limit)")
          Text("Where AI ran").mta(.displayMedium).foregroundStyle(MTA.text)
          GridRow4 {
            NumberBox(value: "\(entries.filter { $0.source == "onDevice" }.count)", caption: "Device", style: .status(.onTrack))
            NumberBox(value: "\(entries.filter { $0.source == "inCloud" }.count)", caption: "Cloud", style: .filled)
            NumberBox(value: "\(entries.filter { $0.outcome == "improved" }.count)", caption: "Improved", style: .status(.accent))
            NumberBox(value: "\(entries.filter { $0.outcome == "blocked" || $0.outcome == "error" }.count)", caption: "Failed")
          }
          MTASegmented(options: ["All", "Catch-up"], selection: $filter)
          MTALabel("Latest")
          if shown.isEmpty {
            Text(filter == 0 ? "No AI requests yet." : "No offline drafts yet. Translations made on the phone show up here, then again when the cloud improves them.").mta(.body1).foregroundStyle(MTA.text2)
          }
          LazyVStack(spacing: 0) {
            ForEach(shown) { e in
              Button { selected = e } label: { LogRow(entry: e) }.buttonStyle(.plain)
            }
          }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .sheet(item: $selected) { LogDetail(entry: $0) }
      #if DEBUG
      .task {
        // `-logDetail error` opens the latest failed request (simulator checks).
        if UserDefaults.standard.string(forKey: "logDetail") == "error" {
          try? await Task.sleep(for: .seconds(1)); selected = entries.first { $0.detail != nil }
        }
      }
      #endif
      .navigationTitle("Routing log")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          // CSV of every row, for real-device numbers (Devpost, video). Stays on the phone until you share it.
          ShareLink(item: LogCSV(text: RoutingLog.csv(entries)),
                    preview: SharePreview("Travel Copilot AI log · \(entries.count) rows")) {
            Label("Export", systemImage: "square.and.arrow.up")
          }
          .disabled(entries.isEmpty)
        }
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
        if entry.detail != nil { MTALabel("\(LogDetail.summary(entry)) · details", color: MTA.urgent) }
        if let note = entry.note {
          Text(note).mta(.body2).foregroundStyle(entry.outcome == "kept" ? MTA.urgent : MTA.accent).lineLimit(2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      MTALabel(entry.latencyMs > 0 ? SourceChip.format(entry.latencyMs) : "—", color: MTA.text)
      Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(MTA.text2)
    }
    .padding(.vertical, 12)
    .contentShape(.rect)
    .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle).frame(height: 1) }
    .accessibilityElement(children: .combine)
  }

  static let names = [
    "classifyAsk": "Ask · classify", "translate": "Say · translate", "translateReply": "Reply · translate",
    "parseBooking": "Prepare · parse booking", "destinationPack": "Prepare · destination pack",
    "Catch-up · translate": "Catch-up · improve draft", "Catch-up · start": "Catch-up · back online",
  ]

  /// iphone = on-device · icloud = cloud · icloud.dashed = waiting for Wi-Fi · exclamationmark = failed
  private var mark: (symbol: String, status: MTAStatus) {
    switch (entry.outcome, entry.source) {
    case ("ok", "onDevice"): ("iphone", .onTrack)
    case ("improved", _): ("sparkles", .accent)
    case ("unchanged", _): ("checkmark", .onTrack)
    case ("kept", _): ("exclamationmark.shield", .urgent)
    case ("ok", nil): ("arrow.triangle.2.circlepath", .accent)
    case ("ok", _): ("icloud", .accent)
    case ("deferred", _): ("icloud.dashed", .notice)
    default: ("exclamationmark", .urgent)
    }
  }
}


/// Tap a log row: every field of the request, including the raw error.
private struct LogDetail: View {
  let entry: RoutingEntry
  @Environment(\.dismiss) private var dismiss

  /// Short, readable cause for the row ("Over quota", "Offline"…). The raw text stays in the details.
  static func summary(_ e: RoutingEntry) -> String {
    let d = e.detail ?? ""
    if d.contains("429") || d.contains("resourceExhausted") { return "Over quota" }
    if d.contains("403") || d.contains("permissionDenied") { return "Not allowed" }
    if d.contains("NotConfigured") { return "Firebase not set up" }
    if d.contains("offline") || d.contains("NSURLErrorDomain") { return "No connection" }
    return "Error"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text(LogRow.names[entry.task] ?? entry.task).mta(.headline).foregroundStyle(MTA.text)
          FieldRow(label: "Time", value: entry.timestamp.formatted(date: .abbreviated, time: .standard))
          FieldRow(label: "Kind", value: entry.kind.capitalized)
          FieldRow(label: "Outcome", value: entry.outcome,
                   highlight: ["ok", "improved", "unchanged"].contains(entry.outcome) ? nil : .urgent)
          if let note = entry.note { FieldRow(label: "Result", value: note) }
          FieldRow(label: "Ran on", value: entry.source == "onDevice" ? "This iPhone" : entry.source == "inCloud" ? "Cloud · Gemini" : "—")
          FieldRow(label: "Route", value: entry.requestedRoute ?? "—")
          FieldRow(label: "Network", value: entry.network)
          FieldRow(label: "Why", value: entry.reason)
          FieldRow(label: "Time taken", value: entry.latencyMs > 0 ? SourceChip.format(entry.latencyMs) : "—")
          if let d = entry.detail {
            MTALabel("Error · \(Self.summary(entry))").padding(.top, 8)
            Text(d).font(.system(.footnote, design: .monospaced)).foregroundStyle(MTA.text)
              .textSelection(.enabled)
              .padding(12).frame(maxWidth: .infinity, alignment: .leading)
              .background(MTA.raised, in: .rect(cornerRadius: 12))
            Button("Copy error") { UIPasteboard.general.string = d }.buttonStyle(.mtaSecondary(height: 44))
          }
        }
        .mtaScreen().padding(.vertical, 16)
      }
      .background(MTA.surface)
      .navigationTitle("Request details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
    .presentationDetents([.medium, .large])
  }
}
