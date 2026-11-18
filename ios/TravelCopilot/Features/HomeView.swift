import SwiftUI
import SwiftData

/// Home: the next moment as a big number, offline readiness, the taxi card and the Ask bar.
/// Everything shown comes from stored Vault fields (no generated facts).
struct HomeView: View {
  @Environment(AIService.self) private var ai
  @Environment(AppRouter.self) private var router
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query private var packs: [DestinationPack]
  @Query(sort: \TripPlan.start) private var plans: [TripPlan]
  @Query(filter: #Predicate<TranslationEntry> { $0.isDraft }) private var drafts: [TranslationEntry]
  @State private var taxiItem: VaultItem?

  private var pack: DestinationPack? { packs.first }
  private var hotel: VaultItem? { items.first { $0.kind == "hotel" } }
  private var place: String { pack?.countryName ?? "Your trip" }

  var body: some View {
    @Bindable var router = router
    NavigationStack {
      TimelineView(.periodic(from: .now, by: 30)) { _ in
        ScrollView {
          if items.isEmpty { emptyState } else { content(now: AppClock.now) }
        }
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .safeAreaInset(edge: .bottom) {
        if !items.isEmpty {
          AskBar(placeholder: "When is check-in?") { router.ask = AskRequest() }
            .padding(.horizontal, MTA.margin).padding(.bottom, 8)
        }
      }
      .navigationTitle("Today")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Image(systemName: "asterisk")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(MTA.accent)
            .accessibilityLabel("Travel Copilot")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
          Button { router.showSettings = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel("Settings")
        }
      }
      .navigationDestination(isPresented: $router.showSettings) { SettingsView() }
      .fullScreenCover(item: $taxiItem) { BigCardView(item: $0, pack: pack) }
      #if DEBUG
      .task {
        // `-screen taxi` opens the taxi card (simulator checks).
        if UserDefaults.standard.string(forKey: "screen") == "taxi" { try? await Task.sleep(for: .seconds(1)); taxiItem = hotel }
      }
      #endif
    }
  }

  // MARK: - Content

  @ViewBuilder
  private func content(now: Date) -> some View {
    let events = TripTimeline.events(items: items, plans: plans)
    let range = TripTimeline.range(events)
    let next = events.first { $0.date > now }
    let checks = readiness
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        MTALabel(dayLine(now: now, range: range))
        Spacer()
        ConnectionChip()
      }

      hero(next: next, now: now)

      GridRow4 {
        boxes(next: next, now: now, ready: checks.filter(\.ok).count, total: checks.count)
      }

      progressBar(now: now, range: range)

      MTALabel("Offline ready")
      GridRow4 {
        ForEach(checks, id: \.label) { c in
          VStack(spacing: 6) {
            MilestoneSymbol(systemName: c.ok ? "checkmark" : "exclamationmark", ok: c.ok)
            MTALabel(c.label, color: c.ok ? MTA.text : MTA.obstacle).lineLimit(1).minimumScaleFactor(0.7)
          }
          .frame(maxWidth: .infinity)
        }
      }

      if let hotel, hotel.addressLocal != nil {
        FeatureCard(label: "Show a local", title: "Taxi card",
                    detail: "Hotel address in \(pack?.languageName ?? "the local language") · works offline",
                    systemImage: "car.fill") { taxiItem = hotel }
      }

      Button { router.showHelp = true } label: {
        HStack(spacing: 10) {
          Image(systemName: "phone.fill").foregroundStyle(MTA.urgent)
          Text("Emergency help").mta(.subheadNormal).foregroundStyle(MTA.text)
          Spacer()
          if let n = EmergencyNumbers.numbers(for: pack?.countryCode ?? hotel?.countryCode) {
            Text([n["police"], n["ambulance"]].compactMap { $0 }.joined(separator: " · ")).mta(.label).foregroundStyle(MTA.text2)
          }
          Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(MTA.text2)
        }
        .padding(.vertical, 6)
      }
      .buttonStyle(.plain)
    }
    .mtaScreen()
    .padding(.top, 8).padding(.bottom, 24)
  }

  @ViewBuilder
  private func hero(next: TripEvent?, now: Date) -> some View {
    if let next {
      let days = daysUntil(next.date, now: now)
      HStack(alignment: .center, spacing: 16) {
        Text(days >= 1 ? "D-\(days)" : TripTimeline.time(next.date))
          .mta(.displayLarge).monospacedDigit().foregroundStyle(MTA.text)
          .lineLimit(1).minimumScaleFactor(0.7)
        VStack(alignment: .leading, spacing: 2) {
          MTALabel("Next · \(next.label)")
          // "Check in · Hotel X" → "Hotel X" (the label already says Check-in)
          Text(next.title.components(separatedBy: " · ").last ?? next.title).mta(.body2).foregroundStyle(MTA.text).lineLimit(2)
          if days >= 1 { Text(TripTimeline.dayTitle(next.date) + " · " + TripTimeline.time(next.date)).mta(.body2).foregroundStyle(MTA.text2) }
        }
      }
    } else {
      Text("Trip complete").mta(.displayMedium).foregroundStyle(MTA.text)
    }
  }

  @ViewBuilder
  private func boxes(next: TripEvent?, now: Date, ready: Int, total: Int) -> some View {
    let secs = max(0, Int(next?.date.timeIntervalSince(now) ?? 0))
    let days = secs / 86_400, hours = (secs % 86_400) / 3600, mins = (secs % 3600) / 60
    if days >= 1 {
      NumberBox(value: "\(days)", caption: "Days")
      NumberBox(value: String(format: "%02d", hours), caption: "Hours")
    } else {
      NumberBox(value: String(format: "%02d", hours), caption: "Hours")
      NumberBox(value: String(format: "%02d", mins), caption: "Min")
    }
    NumberBox(value: "\(drafts.count)", caption: "Drafts", style: .filled)
    NumberBox(value: "\(ready)/\(total)", caption: "Ready", style: ready == total ? .status(.onTrack) : .status(.obstacle))
  }

  private func progressBar(now: Date, range: ClosedRange<Date>?) -> some View {
    let fraction: Double = {
      guard let range else { return 0 }
      let end = TripTimeline.calendar.date(byAdding: .day, value: 1, to: range.upperBound)!
      return min(1, max(0, now.timeIntervalSince(range.lowerBound) / end.timeIntervalSince(range.lowerBound)))
    }()
    return GeometryReader { g in
      ZStack(alignment: .leading) {
        Capsule().fill(MTA.subtle)
        Capsule().fill(MTA.accent).frame(width: g.size.width * fraction)
      }
    }
    .frame(height: 3)
    .accessibilityLabel("Trip progress \(Int(fraction * 100)) percent")
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 20) {
      MTALabel("No trip yet")
      Text("Paste your bookings once. Then it works with no signal.").mta(.displayMedium).foregroundStyle(MTA.text)
      NoticeCard(text: "Prepare runs once in the cloud on Wi-Fi. After that, Ask, Say and the taxi card work offline.")
      Button("Prepare my trip") { router.tab = .prepare }.buttonStyle(.mtaPrimary)
    }
    .mtaScreen().padding(.top, 24)
  }

  // MARK: - Facts

  private struct Check { let label: String; let ok: Bool }

  private var readiness: [Check] {
    [
      Check(label: "Vault", ok: !items.isEmpty),
      Check(label: "Pack", ok: pack != nil),
      Check(label: "Numbers", ok: EmergencyNumbers.numbers(for: pack?.countryCode ?? hotel?.countryCode) != nil),
      Check(label: "Model", ok: ai.deviceModelAvailable),
    ]
  }

  private func daysUntil(_ date: Date, now: Date) -> Int {
    let cal = TripTimeline.calendar
    return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
  }

  private func dayLine(now: Date, range: ClosedRange<Date>?) -> String {
    guard let range else { return place }
    let today = TripTimeline.calendar.startOfDay(for: now)
    let total = TripTimeline.days(in: range).count
    if today < range.lowerBound { return "\(place) · in \(daysUntil(range.lowerBound, now: now)) days" }
    if today > range.upperBound { return "\(place) · trip ended" }
    let day = (TripTimeline.calendar.dateComponents([.day], from: range.lowerBound, to: today).day ?? 0) + 1
    return "\(place) · Day \(day) of \(total)"
  }
}
