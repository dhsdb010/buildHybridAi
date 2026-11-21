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
  @Query(sort: \RoutingSummary.day, order: .reverse) private var summaries: [RoutingSummary]
  @State private var filter = 0
  @State private var confirmClear = false
  /// The list shows the newest rows first, a page at a time (totals always cover everything).
  @State private var showing = 300
  @State private var selected: RoutingEntry?

  /// "Catch-up": the drafts made offline and what the cloud did with them later.
  private var shown: [RoutingEntry] {
    filter == 0 ? entries : entries.filter { $0.task.hasPrefix("Catch-up") || $0.task == "translate" || $0.task == "Blue · open question" || $0.outcome == "deferred" }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Totals cover the whole trip: detailed rows plus older days compacted into summaries.
          // Notes ("Catch-up · back online") aren't AI requests, so they don't count.
          let t = RoutingLog.totals(entries, summaries)
          MTALabel("\(t.requests) AI requests\(summaries.isEmpty ? "" : " · older days compacted")")
          Text("Where AI ran").mta(.displayMedium).foregroundStyle(MTA.text)
          GridRow4 {
            NumberBox(value: "\(t.device)", caption: "Device", style: .status(.onTrack))
            NumberBox(value: "\(t.cloud)", caption: "Cloud", style: .filled)
            NumberBox(value: "\(t.improved)", caption: "Better", style: .status(.accent))
            NumberBox(value: "\(t.failed)", caption: "Failed")
          }
          MTASegmented(options: ["All", "Catch-up"], selection: $filter)
          MTALabel("Latest")
          if shown.isEmpty {
            Text(filter == 0 ? "No AI requests yet." : "No offline drafts yet. Translations made on the phone show up here, then again when the cloud improves them.").mta(.body1).foregroundStyle(MTA.text2)
          }
          LazyVStack(spacing: 0) {
            ForEach(shown.prefix(showing)) { e in
              Button { selected = e } label: { LogRow(entry: e) }.buttonStyle(.plain)
            }
          }
          if shown.count > showing {
            Button("Show \(min(300, shown.count - showing)) more") { showing += 300 }.buttonStyle(.mtaSecondary(height: 44))
          }
          if filter == 0 && !summaries.isEmpty { earlier }
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
      .confirmationDialog("Clear the whole AI log?", isPresented: $confirmClear, titleVisibility: .visible) {
        Button("Clear log", role: .destructive) {
          entries.forEach(context.delete); summaries.forEach(context.delete); try? context.save()
        }
      } message: {
        Text("Every request and the compacted earlier days are removed. Export it first if you want to keep the numbers. Your bookings and chats stay.")
      }
      .navigationTitle("Routing log")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          // CSV of every row, for real-device numbers (Devpost, video). Stays on the phone until you share it.
          ShareLink(item: LogCSV(text: RoutingLog.csv(entries, summaries: summaries)),
                    preview: SharePreview("Travel Copilot AI log · \(RoutingLog.totals(entries, summaries).requests) requests")) {
            Label("Export", systemImage: "square.and.arrow.up")
          }
          .disabled(entries.isEmpty && summaries.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Clear", role: .destructive) { confirmClear = true }.disabled(entries.isEmpty && summaries.isEmpty)
        }
      }
    }
  }
}

extension RoutingLogView {
  struct EarlierLine { let label: String; let count: Int; let avgMs: Int }

  /// One line per task and result for the day (summaries that differ only by network are merged).
  static func lines(_ rows: [RoutingSummary]) -> [EarlierLine] {
    func label(_ s: RoutingSummary) -> String {
      let result = s.source == "onDevice" ? "on-device" : s.source == "inCloud" ? "cloud"
        : ["error", "blocked"].contains(s.outcome) ? "failed" : s.outcome == "ok" ? "note" : s.outcome
      // "Plan · hotel near Katamachi" → "Plan · hotel": one line per kind of place, not per area.
      let task = s.task.hasPrefix("Plan · ") ? String(s.task.components(separatedBy: " near ")[0]) : s.task
      return "\(LogRow.names[task] ?? task) · \(result)"
    }
    return Dictionary(grouping: rows, by: label).map { key, group in
      let n = group.reduce(0) { $0 + $1.count }
      return EarlierLine(label: key, count: n, avgMs: n > 0 ? group.reduce(0) { $0 + $1.totalLatencyMs } / n : 0)
    }
    .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
  }

  /// Older days, compacted: one line per day and kind of call, with how many and the average time.
  var earlier: some View {
    VStack(alignment: .leading, spacing: 0) {
      MTALabel("Earlier · compacted by day").padding(.top, 16).padding(.bottom, 4)
      Text("When the detailed log passes \(RoutingLog.detailBudgetBytes / 1_048_576) MB, older calls are kept as daily totals, so the log covers your whole trip. Clear it when the trip is over.")
        .mta(.body2).foregroundStyle(MTA.text2).padding(.bottom, 8)
      ForEach(Dictionary(grouping: summaries, by: \.day).sorted { $0.key > $1.key }, id: \.key) { day, rows in
        Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
          .mta(.subheadNormal).foregroundStyle(MTA.text).padding(.top, 10)
        ForEach(Self.lines(rows), id: \.label) { line in
          HStack(spacing: 10) {
            Text("\(line.count)×").mta(.body2).monospacedDigit().foregroundStyle(MTA.text).frame(width: 44, alignment: .leading)
            Text(line.label).mta(.body2).foregroundStyle(MTA.text2).lineLimit(1)
            Spacer()
            Text(line.avgMs > 0 ? "avg \(SourceChip.format(line.avgMs))" : "—").mta(.body2).monospacedDigit().foregroundStyle(MTA.text2)
          }
          .padding(.vertical, 6)
          .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle.opacity(0.4)).frame(height: 1) }
        }
      }
    }
  }
}

struct LogRow: View {
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
    "Blue · open question": "Blue · open question (cloud)",
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
