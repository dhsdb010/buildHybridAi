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
  @Query(filter: #Predicate<TranslationEntry> { $0.polishedTranslation != nil }) private var improved: [TranslationEntry]
  @Query(sort: \ExpenseItem.spentAt) private var expenses: [ExpenseItem]
  @Query private var savedPlaces: [Place]
  @Environment(AuthService.self) private var auth
  @State private var deckPage = 0
  @State private var taxiItem: VaultItem?
  @State private var template: PlanTemplate?

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
          FloatingAsk()
        }
      }
      .navigationTitle("Today")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        // You on the left, the people you travel with on the right (Figma 12 · option B).
        // Settings is inside Profile.
        ToolbarItem(placement: .topBarLeading) {
          Button { router.showProfile = true } label: { ProfileAvatar(size: 32) }
            .accessibilityLabel("Profile")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
          Button { router.showChats = true } label: { Image(systemName: "bubble.left.and.bubble.right") }
            .accessibilityLabel("Chats")
        }
      }
      .navigationDestination(isPresented: $router.showSettings) { SettingsView() }
      .navigationDestination(isPresented: $router.showProfile) { ProfileView() }
      .navigationDestination(isPresented: $router.showChats) { ChatsView() }
      .fullScreenCover(item: $taxiItem) { BigCardView(item: $0, pack: pack) }
      .onChange(of: router.showTaxi, initial: true) { _, show in
        guard show else { return }
        router.showTaxi = false
        taxiItem = hotel
      }
      .fullScreenCover(item: $template) { t in PlanView(template: t, onClose: { template = nil }) }
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
    let ended = range.map { TripTimeline.calendar.startOfDay(for: now) > $0.upperBound } ?? false
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        MTALabel(dayLine(now: now, range: range))
        Spacer()
        ConnectionChip()
      }

      if ended {
        afterTrip(events: events)
      } else {
        hero(next: next, now: now)

        GridRow4 {
          boxes(next: next, now: now, ready: checks.filter(\.ok).count, total: checks.count)
        }

        progressBar(now: now, range: range)

        if case let .waiting(n) = ai.catchUp { improveNow(n) }

        // Offline ready on one line: a small dot per check, beside the title.
        HStack(spacing: 10) {
          MTALabel("Offline ready", color: MTA.text)
          Spacer(minLength: 4)
          ForEach(checks, id: \.label) { c in
            HStack(spacing: 4) {
              Circle().fill(c.ok ? MTA.onTrack : MTA.obstacle).frame(width: 7, height: 7)
              Text(c.label).font(MTAType.tab.font).foregroundStyle(c.ok ? MTA.text : MTA.obstacle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(c.label) \(c.ok ? "ready" : "missing")")
          }
        }
      }

      emergencyRow

      if !ended {
        let cards = UpNext.cards(events, now: now, done: JourneyDone.ids, language: pack?.languageName)
        if !cards.isEmpty { upNext(cards) }
      }

      spendCard(ended: ended)

      if let idea = PlanTemplate.available.first(where: { $0.countryCode != (pack?.countryCode ?? hotel?.countryCode) }) {
        PackageCard(template: idea, after: ended) { template = idea }
      }

    }
    .mtaScreen()
    .padding(.top, 8).padding(.bottom, 24)
  }

  /// Always on Home, at every stage of the trip (and after it).
  private var emergencyRow: some View {
    Button { router.showHelp = true } label: {
      HStack(spacing: 10) {
        EmergencyLogo()
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

  // MARK: Up next

  @ViewBuilder
  private func upNext(_ cards: [UpNextCard]) -> some View {
    let page = min(deckPage, cards.count - 1)
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        MTALabel("Up next", color: MTA.text)
        Spacer()
        if cards.count > 1 { Text("\(page + 1) of \(cards.count) · swipe").mta(.tab).foregroundStyle(MTA.text2) }
      }
      TabView(selection: $deckPage) {
        ForEach(cards.indices, id: \.self) { i in
          let c = cards[i]
          FeatureCard(label: c.label, title: c.title, detail: c.detail, systemImage: c.symbol, height: 124) { open(c.action) }
            .tag(i)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(height: 124)
      if cards.count > 1 {
        HStack(spacing: 6) {
          ForEach(cards.indices, id: \.self) { i in
            Capsule().fill(i == page ? MTA.text : MTA.subtle.opacity(0.5)).frame(width: i == page ? 20 : 6, height: 6)
          }
        }
        .animation(.snappy, value: page)
        .accessibilityHidden(true)
      }
    }
  }

  private func open(_ action: UpNextCard.Action) {
    switch action {
    case .taxi: taxiItem = hotel
    case .planDay: router.tab = .trip
    case .spend: router.tab = .trip; router.tripMode = 1
    case .none: break
    }
  }

  // MARK: Spend

  @ViewBuilder
  private func spendCard(ended: Bool) -> some View {
    let rate = ExpenseService.savedRate
    let home = Spend.homeCurrency
    let local = Spend.currency(country: pack?.countryCode ?? hotel?.countryCode) ?? expenses.first?.currency ?? home
    let total = Spend.localTotal(expenses)
    let homeTotal = Spend.homeTotal(expenses, rate: rate)
    let budget = ExpenseService.budget
    let status = Spend.status(spent: homeTotal ?? 0, budget: budget)
    let settle = Spend.toSettle(expenses)
    let detail: String = {
      if expenses.isEmpty { return "Scan receipts as you go · works offline" }
      guard let homeTotal else { return "\(settle) to settle when you’re online" }
      if ended && settle == 0 { return "\(Spend.money(total, local)) · \(status == .near ? "near" : "within") your \(Spend.money(budget, home)) budget" }
      let left = Spend.money(max(0, budget - homeTotal), home, whole: true)
      return "≈ \(Spend.money(homeTotal, home, whole: true)) · \(left) left" + (settle > 0 ? " · \(settle) to settle" : "")
    }()
    FeatureCard(label: ended && settle == 0 && !expenses.isEmpty ? "Trip report · settled" : "Spending · trip so far",
                title: ended && settle == 0 && homeTotal != nil && !expenses.isEmpty ? Spend.money(homeTotal!, home) : Spend.money(total, local),
                detail: detail, systemImage: "receipt",
                status: status == .near ? .obstacle : .onTrack) {
      router.tab = .trip; router.tripMode = 1
    }
  }

  // MARK: After the trip

  /// Figma 09 · After the trip: welcome back by name, the trip at a glance, then Prepare a new trip.
  @ViewBuilder
  private func afterTrip(events: [TripEvent]) -> some View {
    let name = Profile.firstName(account: auth.account?.name)
    Text(name.map { "Welcome back, \($0)" } ?? "Welcome back").mta(.displayMedium).foregroundStyle(MTA.text)
      .lineLimit(2).minimumScaleFactor(0.8)
    if let summary = summary(events) {
      NavigationLink {
        TripSummaryView(summary: summary, place: tripCity, country: place)
      } label: {
        YourTripCard(summary: summary, expenses: expenses.count, better: improved.count, steps: Steps.saved(summary.range))
      }
      .buttonStyle(.plain)
    }
    Button { router.tab = .prepare } label: {
      Label("Prepare a new trip", systemImage: "arrow.right").labelStyle(TrailingIcon())
    }
    .buttonStyle(.mtaPrimary)
  }

  private func summary(_ events: [TripEvent]) -> TripSummary? {
    TripSummary.build(
      events: events,
      plans: plans.map { .init(start: $0.start, title: $0.title, detail: $0.detail, kind: $0.kind, latitude: $0.latitude, longitude: $0.longitude) },
      places: savedPlaces.map { .init(name: $0.name, kind: $0.kind, latitude: $0.latitude, longitude: $0.longitude) },
      expenses: expenses.map { .init(date: $0.spentAt, merchant: $0.merchant, amount: $0.amount, currency: $0.currency, category: $0.kind) })
  }

  /// "Tokyo" from the flight in ("Tokyo Haneda"), else the country.
  private var tripCity: String {
    TripSummary.city(destination: items.first { $0.kind == "flight" }?.destination) ?? place
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

  /// On roaming / Low Data the catch-up pass waits for Wi-Fi; this lets the traveler run it now.
  private func improveNow(_ n: Int) -> some View {
    OutlineCard {
      MTALabel("On roaming or Low Data")
      Text("\(n) draft\(n == 1 ? "" : "s") wait for Wi-Fi").mta(.subheadMedium).foregroundStyle(MTA.text)
      Text("Improving uses a little mobile data.").mta(.body2).foregroundStyle(MTA.text2)
      Button("Improve now") { Task { await CatchUpService.run(ai: ai, manual: true, pack: pack) } }
        .buttonStyle(.mtaPrimary)
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
    // Orange while offline drafts wait for the catch-up pass.
    NumberBox(value: "\(drafts.count)", caption: "Drafts", style: drafts.isEmpty ? .filled : .status(.obstacle))
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
    VStack(alignment: .leading, spacing: 18) {
      MTALabel("No trip yet")
      Text("Start your trip here").mta(.displayMedium).foregroundStyle(MTA.text)
      Text("Already booked? Add it once on Wi-Fi, then it works with no signal.")
        .mta(.body1).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      Button { router.tab = .prepare } label: {
        Label("Prepare my trip", systemImage: "arrow.right").labelStyle(TrailingIcon())
      }
      .buttonStyle(.mtaPrimary)

      MTALabel("Not booked yet? Start from an idea").padding(.top, 10)
      ScrollView(.horizontal) {
        HStack(spacing: MTA.gutter) {
          ForEach(PlanTemplate.available) { t in
            TemplateCard(template: t) { template = t }
          }
        }
        .padding(.horizontal, MTA.margin)
      }
      .scrollIndicators(.hidden)
      .padding(.horizontal, -MTA.margin)
      Text("Opens the AI planner with this trip filled in. You can change anything.")
        .mta(.body2).foregroundStyle(MTA.text2)
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

/// Emergency help's logo: the SF Symbol staroflife in iOS system red (Symbols, the default), or our Star of Life (Emoji).
struct EmergencyLogo: View {
  @AppStorage(TripIcon.styleKey) private var style = TripIcon.Style.symbol.rawValue
  var body: some View {
    Group {
      if style == TripIcon.Style.emoji.rawValue {
        Image("StarOfLife").resizable().scaledToFit()
      } else {
        Image(systemName: "staroflife.fill").resizable().scaledToFit().foregroundStyle(.red)  // iOS system red #FF3B30
      }
    }
    .frame(width: 26, height: 26)
    .accessibilityHidden(true)
  }
}

/// A trip idea as a ready-made package (MTA poster style, accent blue). Opens the planner filled in.
struct PackageCard: View {
  let template: PlanTemplate
  /// After the trip: "Where next?"
  var after = false
  var action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        MTALabel(after ? "Where next? · trip package" : "Trip package · next trip", color: MTA.onColor)
        Spacer()
        Text("\(template.days) days").mta(.label).foregroundStyle(MTA.accent)
          .padding(.horizontal, 8).padding(.vertical, 3).background(.white, in: .capsule)
      }
      Text(template.city).mta(.displayMedium).foregroundStyle(MTA.onColor)
      Text("\(template.theme). Flights, stay, day plans and a phrase pack, ready to change.")
        .mta(.body2).foregroundStyle(MTA.onColor).fixedSize(horizontal: false, vertical: true)
      Button(action: action) {
        Label("Use this plan", systemImage: "arrow.right").labelStyle(TrailingIcon())
          .mta(.button2).foregroundStyle(MTA.accent)
          .padding(.horizontal, 18).padding(.vertical, 11)
          .background(.white, in: .capsule)
      }
      .buttonStyle(.plain)
      Text("A trip idea to start from. You can change anything.").mta(.tab).foregroundStyle(MTA.onColor.opacity(0.9))
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTA.accent, in: .rect(cornerRadius: 20))
    .overlay(alignment: .topTrailing) {
      Image(systemName: "asterisk").font(.system(size: 44, weight: .semibold)).foregroundStyle(MTA.onColor.opacity(0.3))
        .padding(.top, 52).padding(.trailing, 22)
    }
    .accessibilityElement(children: .contain)
  }
}
