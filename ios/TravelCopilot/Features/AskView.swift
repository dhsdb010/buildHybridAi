import SwiftUI
import SwiftData

/// Ask my trip (on-device classifier → stored field) or Say in <language> (context translation).
struct AskView: View {
  let request: AskRequest
  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var net
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query private var packs: [DestinationPack]
  @Query(sort: \Place.createdAt) private var places: [Place]
  @Environment(LocationService.self) private var location
  @Environment(AppRouter.self) private var router
  @State private var mode = 0
  @State private var question = ""
  @State private var asked = ""
  @State private var asking = false
  @State private var outcome: AskOutcome?
  @State private var error: String?
  @State private var taxiItem: VaultItem?
  @State private var translationCard: TranslationEntry?
  @FocusState private var focused: Bool

  private var pack: DestinationPack? { packs.first }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          MTASegmented(options: ["Ask my trip", "Say in \(pack?.languageName ?? "local language")"], selection: $mode)
          if asking {
            HStack(spacing: 10) { ProgressView(); Text(mode == 0 ? "Looking in your Vault…" : "Translating…").mta(.body1).foregroundStyle(MTA.text2) }
          } else if let error {
            NoticeCard(text: error)
          } else if let outcome {
            result(outcome)
          } else {
            suggestions
          }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.immediately)
      .background(MTA.surface)
      .safeAreaInset(edge: .bottom) { inputBar.padding(.horizontal, MTA.margin).padding(.bottom, 8) }
      .navigationTitle("Ask")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { dismiss() } } }
      .fullScreenCover(item: $taxiItem) { BigCardView(item: $0, pack: pack) }
      .fullScreenCover(item: $translationCard) { TranslationCardView(entry: $0, pack: pack) }
    }
    .task {
      mode = request.mode
      question = request.text
      if request.autoSubmit, !question.isEmpty { await submit() } else { focused = true }
    }
    .onChange(of: mode) { outcome = nil; error = nil }
  }

  // MARK: - Pieces

  private var inputBar: some View {
    HStack {
      TextField(mode == 0 ? "When is check-in?" : "At the pharmacy: I'm allergic to penicillin", text: $question, axis: .vertical)
        .mta(.body1).lineLimit(1...3).focused($focused).submitLabel(.send)
        .onSubmit { Task { await submit() } }
      Button { Task { await submit() } } label: {
        Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(MTA.onColor)
          .frame(width: 40, height: 40).background(MTA.accent, in: .circle)
      }
      .disabled(question.nilIfEmpty == nil || asking)
      .accessibilityLabel(mode == 0 ? "Ask" : "Translate")
    }
    .padding(.leading, 20).padding(.trailing, 6).padding(.vertical, 6)
    .background(MTA.surface, in: .rect(cornerRadius: 26))
    .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(MTA.border, lineWidth: 2) }
  }

  private var suggestions: some View {
    let list = mode == 0
      ? ["When is check-in?", "What's my hotel booking code?", places.contains { $0.kind == "plan" }
          ? "How far is \(places.first { $0.kind == "plan" }!.name) from my hotel?" : "Show my hotel to a taxi driver"]
      : ["Where is the nearest pharmacy?", "At the pharmacy: I'm allergic to penicillin", "Please call a taxi"]
    return VStack(alignment: .leading, spacing: 10) {
      MTALabel(mode == 0 ? "Answers come from your saved bookings" : "Context-aware · works offline")
      ForEach(list, id: \.self) { s in
        Button { question = s; Task { await submit() } } label: {
          Text(s).mta(.body1).foregroundStyle(MTA.text).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.subtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func result(_ outcome: AskOutcome) -> some View {
    MTALabel("You asked")
    Text(asked).mta(.headline).foregroundStyle(MTA.text)
    switch outcome {
    case let .vault(answer, item, meta):
      chips(meta)
      // "2026-12-03 15:00" → big "15:00" + "Thu, Dec 3"; anything else shown as-is.
      let parts = answer.value.split(separator: " ")
      if parts.count == 2, let d = TripTimeline.date(String(parts[0]), String(parts[1])) {
        Text(TripTimeline.time(d)).mta(.displayLarge).monospacedDigit().foregroundStyle(MTA.text)
        MTALabel(TripTimeline.dayTitle(d), color: MTA.text)
      } else {
        Text(answer.value).mta(answer.value.count <= 12 ? .displayLarge : .headline).monospacedDigit().foregroundStyle(MTA.text)
          .lineLimit(3).minimumScaleFactor(0.6)
      }
      Text(answer.text).mta(.body1).foregroundStyle(MTA.text)
      OutlineCard(stroke: MTA.onTrack) {
        MTALabel("From your booking", color: MTA.onTrack)
        HStack(spacing: 10) {
          TripBullet(systemName: item.kind == "hotel" ? "bed.double.fill" : "airplane", size: 24)
          Text(item.title).mta(.subheadNormal).foregroundStyle(MTA.text)
        }
        FieldRow(label: "Value", value: answer.value)
        if let code = item.confirmationCode { FieldRow(label: "Ref", value: code) }
      }
      Text("Read from your saved booking. The on-device model only picks the field — it never writes the answer.")
        .mta(.body2).foregroundStyle(MTA.text2)
      if answer.showTaxiCard { Button("Show taxi card") { taxiItem = item }.buttonStyle(.mtaPrimary) }
    case let .place(answer, place, meta):
      chips(meta)
      Text(answer.distance).mta(.displayLarge).monospacedDigit().foregroundStyle(MTA.text)
      MTALabel(answer.estimate, color: MTA.text)
      Text(answer.text).mta(.body1).foregroundStyle(MTA.text)
      OutlineCard(stroke: MTA.onTrack) {
        MTALabel("From your offline map", color: MTA.onTrack)
        HStack(spacing: 10) {
          TripBullet(systemName: place.symbol, status: place.kind == "plan" ? .onTrack : .accent, size: 24)
          Text(place.name).mta(.subheadNormal).foregroundStyle(MTA.text)
        }
        FieldRow(label: "From", value: answer.from)
        FieldRow(label: "Straight line", value: answer.distance)
      }
      Text("Calculated from saved coordinates — works offline. The on-device model only picks the place.")
        .mta(.body2).foregroundStyle(MTA.text2)
      Button("Open map") { router.tab = .map; dismiss() }.buttonStyle(.mtaPrimary)
    case let .notInVault(meta):
      chips(meta)
      Text("That isn't in your saved bookings, so I won't guess.").mta(.subheadMedium).foregroundStyle(MTA.text)
    case let .translation(entry, meta):
      chips(meta, draft: entry.isDraft)
      Text(entry.translation).mta(.headline).foregroundStyle(MTA.text)
      if !entry.romanization.isEmpty { Text(entry.romanization).mta(.body2).foregroundStyle(MTA.text2) }
      if !entry.note.isEmpty { Label(entry.note, systemImage: "info.circle").mta(.body2).foregroundStyle(MTA.text2) }
      Button("Show full screen") { translationCard = entry }.buttonStyle(.mtaPrimary)
    case let .other(meta):
      chips(meta)
      Text("I answer questions about your bookings. To talk to someone, switch to Say.").mta(.body1).foregroundStyle(MTA.text)
    }
  }

  private func chips(_ meta: AIMeta, draft: Bool = false) -> some View {
    HStack(spacing: 8) {
      SourceChip(source: meta.source, latencyMs: meta.latencyMs)
      if !net.isOnline { Chip(text: "Offline", systemImage: "icloud.slash") }
      if draft { Chip(text: "Draft", systemImage: "icloud.dashed", color: MTA.obstacle) }
    }
  }

  private func submit() async {
    guard let q = question.nilIfEmpty, !asking else { return }
    focused = false
    asking = true; error = nil; outcome = nil; asked = q
    defer { asking = false }
    do {
      let here = location.location.map { (lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
      let r = mode == 0
        ? try await ai.ask(q, items: items, pack: pack, places: places, here: here)
        : try await ai.say(q, items: items, pack: pack)
      outcome = r
      question = ""
      if case let .translation(entry, _) = r { translationCard = entry }
    } catch {
      self.error = error.localizedDescription
    }
  }
}
