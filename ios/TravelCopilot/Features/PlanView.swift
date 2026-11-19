import CoreLocation
import SwiftData
import SwiftUI

/// State of one planning conversation (in memory until the user saves the plan).
@MainActor
@Observable
final class PlanSession {
  enum Step: Int, CaseIterable { case brief, memories, destination, days, stay, eat, book }

  var step: Step = .brief
  var brief: PlanBrief
  let countries = PlanLanguages.countries()
  let whenOptions: [(label: String, date: Date)]
  let dayOptions = [3, 5, 7, 10]
  let dislikeOptions = ["Long queues", "Tourist traps", "Early starts", "Too much walking", "Big chains"]

  var memoryMeta: AIMeta?
  var ideas: [DestinationIdea] = []
  var idea: DestinationIdea?
  var outline: [DayIdea] = []
  var center: CLLocationCoordinate2D?
  var hotels: [PlanPlace] = []
  var hotel: PlanPlace?
  var places: [String: [PlanPlace]] = [:]   // "food-2" → options for day 3
  var kept: [PlanPlace] = []
  var seeMode = 0                           // 0 Eat · 1 See
  var day = 0
  var loading = false
  var error: String?
  var showWhy = false

  init(template: PlanTemplate? = nil) {
    let cal = TripTimeline.calendar
    let now = AppClock.now
    func early(_ months: Int) -> (String, Date) {
      let first = cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: months, to: now)!))!
      let d = cal.date(byAdding: .day, value: 2, to: first)!
      return ("Early " + d.formatted(.dateTime.month(.abbreviated)), d)
    }
    let soon = ("In 2 weeks", cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: now))!)
    whenOptions = [soon, early(1), early(2)]
    brief = PlanBrief(start: whenOptions[1].date, whenLabel: whenOptions[1].label.lowercased())
    if let template {
      brief.country = template.country
      brief.typed = "\(template.city), \(template.theme.lowercased())"
      brief.days = template.days
    }
  }

  var barIndex: Int {
    switch step {
    case .brief, .memories, .destination: 0
    case .days: 1
    case .stay: 2
    case .eat: 3 + seeMode
    case .book: 5
    }
  }

  var kind: PlanPlaceKind { seeMode == 0 ? .food : .sight }
  var key: String { "\(kind.rawValue)-\(day)" }
  var countryCode: String { idea?.countryCode.uppercased() ?? brief.country?.code ?? "" }
  func dayDate(_ i: Int) -> Date { TripTimeline.calendar.date(byAdding: .day, value: i, to: brief.start) ?? brief.start }
}

/// "Help me plan": chat that builds a trip step by step. Online only (Gemini + Google Maps).
struct PlanView: View {
  /// After "I've booked": go to Add bookings. `nil` = just close.
  var onBooked: (() -> Void)?
  var onClose: () -> Void

  init(template: PlanTemplate? = nil, onBooked: (() -> Void)? = nil, onClose: @escaping () -> Void) {
    self.onBooked = onBooked
    self.onClose = onClose
    _s = State(initialValue: PlanSession(template: template))
  }

  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var net
  @Environment(\.modelContext) private var context
  @State private var s: PlanSession
  @State private var input = ""
  @FocusState private var inputFocused: Bool

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            PlanBar(current: s.barIndex)
            PlanOnlineRow()
            if !net.isOnline {
              NoticeCard(text: "Planning needs internet to check live places and reviews. Your answers stay on this iPhone; carry on when you're back online.")
            }
            stepContent
            if s.loading {
              HStack(spacing: 10) { ProgressView(); Text("Asking Gemini…").mta(.body2).foregroundStyle(MTA.text2) }
            }
            if let e = s.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent) }
            Color.clear.frame(height: 1).id("end")
          }
          .mtaScreen().padding(.top, 8).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: s.step) { withAnimation { proxy.scrollTo("end") } }
      }
      .background(MTA.surface)
      .safeAreaInset(edge: .bottom) { if hasInput { inputBar } }
      .navigationTitle(s.idea.map { "\($0.city) · \(s.brief.days) days" } ?? "Plan a trip")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back", systemImage: "chevron.left") { back() }
        }
        ToolbarItem(placement: .topBarTrailing) { Button("Later") { onClose() } }
      }
      .sheet(isPresented: $s.showWhy) { WhyPlacesSheet() }
      .animation(.snappy, value: s.step)
      #if DEBUG
      .task { await debugAuto() }
      #endif
    }
  }

  // MARK: Steps

  @ViewBuilder private var stepContent: some View {
    switch s.step {
    case .brief: briefStep
    case .memories: memoriesStep
    case .destination: destinationStep
    case .days: daysStep
    case .stay: stayStep
    case .eat: eatStep
    case .book: bookStep
    }
  }

  private var briefStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Hi! Where would you like to go? Or shall I suggest a few places?")
      FlowLayout {
        QuickChip(text: "Suggest for me", selected: s.brief.country == nil && s.brief.typed.isEmpty) {
          s.brief.country = nil; s.brief.typed = ""
        }
        ForEach(s.countries.prefix(8)) { c in
          QuickChip(text: c.name, selected: s.brief.country == c) {
            if s.brief.country != c { s.brief.typed = "" }
            s.brief.country = c
          }
        }
      }
      Button { s.showWhy = true } label: {
        Label("Why only these places?", systemImage: "info.circle").mta(.body2).foregroundStyle(MTA.accent)
      }
      .buttonStyle(.plain)
      if !s.brief.typed.isEmpty { ChatYou(s.brief.typed) }
      ChatAI("When, and for how long?")
      FlowLayout {
        ForEach(s.whenOptions, id: \.label) { o in
          QuickChip(text: o.label, selected: s.brief.start == o.date) {
            s.brief.start = o.date; s.brief.whenLabel = o.label.lowercased()
          }
        }
        ForEach(s.dayOptions, id: \.self) { d in
          QuickChip(text: "\(d) days", selected: s.brief.days == d) { s.brief.days = d }
        }
      }
      Button("Next") { s.step = .memories }.buttonStyle(.mtaPrimary).padding(.top, 8)
    }
  }

  private var memoriesStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Tell me about a trip you still think about. What made it special?")
      if s.brief.memory.isEmpty {
        Text("Type it below: a meal, a street, a moment.").mta(.body2).foregroundStyle(MTA.text2)
      } else {
        ChatYou(s.brief.memory)
      }
      ChatAI("Anything you didn't enjoy?")
      FlowLayout {
        ForEach(s.dislikeOptions, id: \.self) { d in
          QuickChip(text: d, selected: s.brief.dislikes.contains(d)) {
            if let i = s.brief.dislikes.firstIndex(of: d) { s.brief.dislikes.remove(at: i) } else { s.brief.dislikes.append(d) }
            s.brief.tags = nil
          }
        }
      }
      if let t = s.brief.tags { rememberCard(t) }
      if s.brief.tags == nil && (!s.brief.memory.isEmpty || !s.brief.dislikes.isEmpty) {
        Button("Remember this") { Task { await remember() } }.buttonStyle(.mtaSecondary).disabled(s.loading)
      }
      Button(s.brief.tags == nil && s.brief.memory.isEmpty ? "Skip, show ideas" : "Show me ideas") {
        Task { await loadIdeas() }
      }
      .buttonStyle(.mtaPrimary).disabled(s.loading || !net.isOnline)
    }
  }

  private func rememberCard(_ t: MemoryTags) -> some View {
    OutlineCard(stroke: MTA.border) {
      HStack { MTALabel("What I'll remember"); Spacer(); if let m = s.memoryMeta { SourceChip(source: m.source, latencyMs: m.latencyMs) } }
      tagRow("Loves", t.loves.joined(separator: " · "))
      if !t.avoid.isEmpty { tagRow("Avoid", t.avoid.joined(separator: " · ")) }
      tagRow("Pace", t.pace)
      HStack(spacing: 8) {
        Image(systemName: "iphone").foregroundStyle(MTA.text2)
        Text("Summarized on this iPhone when it can. Only this summary goes to the cloud.").mta(.body2).foregroundStyle(MTA.text2)
      }
    }
  }

  private func tagRow(_ k: String, _ v: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(k).mta(.label).foregroundStyle(MTA.text).frame(width: 52, alignment: .leading)
      Text(v).mta(.body2).foregroundStyle(MTA.text)
    }
  }

  private var destinationStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Three ideas for \(s.brief.days) days, \(s.brief.whenLabel):")
      ForEach(s.ideas, id: \.city) { idea in
        OptionCard(label: "Destination · \(idea.country)", source: "Gemini", title: idea.city, why: idea.why,
                   badges: [ScoreBadge(label: "Typical", value: idea.weather)], facts: "Stay: \(idea.base)",
                   kept: s.idea == idea,
                   onKeep: { Task { await keep(idea) } },
                   onSwap: { Task { await swap(idea) } })
      }
    }
  }

  private var daysStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Here is a rough shape. Type below to change anything.")
      ForEach(Array(s.outline.enumerated()), id: \.offset) { i, d in
        HStack(spacing: 14) {
          Milestone(value: "\(i + 1)", state: .upcoming)
          VStack(alignment: .leading, spacing: 2) {
            MTALabel(TripTimeline.dayTitle(s.dayDate(i)))
            Text(d.title).mta(.body1).foregroundStyle(MTA.text)
          }
        }
      }
      if !s.outline.isEmpty {
        Text("Rough plan from Gemini. Places come next, from Google Maps.").mta(.body2).foregroundStyle(MTA.text2)
        Button("Looks good, find a hotel") { Task { await loadHotels() } }.buttonStyle(.mtaPrimary).disabled(s.loading)
      }
    }
  }

  private var stayStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Hotels near your day plans, from \(s.hotels.first?.source ?? "the map"):")
      ForEach(s.hotels) { p in placeCard(p, kept: s.hotel == p, keep: { s.hotel = p }, swap: { Task { await swapHotel(p) } }) }
      if !s.loading && s.hotels.isEmpty { Text("No hotels came back. Type below to try again.").mta(.body2).foregroundStyle(MTA.text2) }
      if s.hotel != nil {
        Button("Next: eat & see") { s.step = .eat; Task { await loadPlaces() } }.buttonStyle(.mtaPrimary)
      }
    }
  }

  private var eatStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      MTASegmented(options: ["Eat", "See"], selection: $s.seeMode)
      FlowLayout {
        ForEach(s.outline.indices, id: \.self) { i in QuickChip(text: "Day \(i + 1)", selected: s.day == i) { s.day = i } }
      }
      if s.outline.indices.contains(s.day) {
        ChatAI("Day \(s.day + 1) is in \(s.outline[s.day].area). \(s.seeMode == 0 ? "Places locals rate highly" : "Things to see"), near your stops:")
      }
      ForEach(s.places[s.key] ?? []) { p in
        placeCard(p, kept: s.kept.contains(p), keep: { toggle(p) }, swap: { Task { await swapPlace(p) } })
      }
      Button("Done, book these") { s.step = .book }.buttonStyle(.mtaPrimary).disabled(s.loading)
    }
    .onChange(of: s.seeMode) { Task { await loadPlaces() } }
    .onChange(of: s.day) { Task { await loadPlaces() } }
  }

  private var bookStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Your plan is ready. Book these, then paste the confirmation emails and I'll make everything work offline.")
      MTALabel("Book outside the app")
      if let idea = s.idea {
        BookRow(systemImage: "airplane", title: "Flight to \(idea.city)",
                detail: "\(TripTimeline.dayTitle(s.brief.start)) · Google Flights", url: PlanService.flightsURL(city: idea.city, start: s.brief.start))
      }
      if let h = s.hotel {
        BookRow(systemImage: "bed.double.fill", title: h.name, detail: "\(s.brief.days - 1) nights · Google Maps", url: h.mapsURL)
      }
      NoticeCard(text: "Suggestions aren't bookings. Only pasted confirmations go into your Vault.")
      MTALabel("Saved to your trip")
      GridRow4 {
        NumberBox(value: "\(s.brief.days)", caption: "Days")
        NumberBox(value: "\(s.kept.count + (s.hotel == nil ? 0 : 1))", caption: "Places")
        NumberBox(value: "\(s.kept.filter { $0.kind == .food }.count)", caption: "Food", style: .filled)
        NumberBox(value: "\(s.hotel == nil ? 1 : 2)", caption: "To book", style: .status(.onTrack))
      }
      if let onBooked {
        Button("I've booked, paste confirmations") { Task { await save(); onBooked() } }.buttonStyle(.mtaPrimary)
      }
      Button(onBooked == nil ? "Save to my trip" : "Book later") { Task { await save(); onClose() } }
        .buttonStyle(MTAButtonStyle(kind: onBooked == nil ? .primary : .secondary))
    }
  }

  private func placeCard(_ p: PlanPlace, kept: Bool, keep: @escaping () -> Void, swap: @escaping () -> Void) -> some View {
    var badges: [ScoreBadge] = []
    if let g = p.googleScore { badges.append(ScoreBadge(label: "Google", value: g)) }
    else if let url = p.mapsURL { badges.append(ScoreBadge(label: "Google", value: "Reviews", url: url)) }
    if let site = LocalReviews.site(country: s.countryCode, kind: p.kind),
       let url = LocalReviews.url(country: s.countryCode, kind: p.kind, name: p.name, city: s.idea?.city ?? "") {
      badges.append(ScoreBadge(label: "Local", value: "Check on \(site)", url: url))
    }
    let label = (p.kind == .hotel ? "Hotel" : p.kind == .food ? "Food" : "See") + " · " + p.area
    return OptionCard(label: label, source: p.source, title: p.name, why: p.why, badges: badges,
                      facts: p.price, kept: kept, mapsURL: p.mapsURL, onKeep: keep, onSwap: swap)
  }

  // MARK: Input bar

  private var hasInput: Bool { s.step != .book }

  private var inputBar: some View {
    HStack {
      TextField(placeholder, text: $input, axis: .vertical)
        .mta(.body1).lineLimit(1...3).focused($inputFocused).submitLabel(.send).onSubmit(send)
      Button(action: send) {
        Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(MTA.onColor)
          .frame(width: 40, height: 40).background(MTA.accent, in: .circle)
      }
      .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || s.loading)
      .accessibilityLabel("Send")
    }
    .padding(.leading, 20).padding(.trailing, 6).padding(.vertical, 6)
    .background(MTA.surface, in: .rect(cornerRadius: 26))
    .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(MTA.border, lineWidth: 2) }
    .padding(.horizontal, MTA.margin).padding(.bottom, 8)
  }

  private var placeholder: String {
    switch s.step {
    case .brief: "Or type a place or idea…"
    case .memories: "A trip you loved…"
    case .destination: "Somewhere warmer? Smaller towns?"
    case .days: "More food, a slower day 3…"
    case .stay: "Cheaper? Closer to the station?"
    default: "Vegetarian? Open late?"
    }
  }

  private func send() {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    input = ""; inputFocused = false
    switch s.step {
    case .brief:
      s.brief.typed = text
      // Keep the chosen country only if the text names a place in it; otherwise let the model match countries.
      if let c = s.brief.country, !text.localizedCaseInsensitiveContains(c.name) { s.brief.country = nil }
    case .memories: s.brief.memory = text; s.brief.tags = nil
    case .destination: s.brief.typed = text; Task { await loadIdeas() }
    case .days: Task { await loadOutline(note: text) }
    case .stay: Task { await loadHotels(note: text) }
    case .eat: s.places[s.key] = nil; Task { await loadPlaces(note: text) }
    case .book: break
    }
  }

  // MARK: Actions

  private func back() {
    guard let prev = PlanSession.Step(rawValue: s.step.rawValue - 1) else { onClose(); return }
    s.error = nil; s.step = prev
  }

  private func run(_ work: () async throws -> Void) async {
    s.loading = true; s.error = nil
    defer { s.loading = false }
    do { try await work() } catch {
      let text = String(describing: error)
      s.error = text.contains("429") || text.contains("resourceExhausted")
        ? "Gemini is busy or over its free quota. Try again in a minute."
        : error.localizedDescription
    }
  }

  private func remember() async {
    await run {
      let (tags, meta) = try await PlanService.remember(s.brief, ai: ai)
      s.brief.tags = tags; s.memoryMeta = meta
    }
  }

  private func loadIdeas() async {
    s.step = .destination; s.ideas = []
    await run { s.ideas = try await PlanService.destinations(s.brief, ai: ai) }
  }

  private func swap(_ idea: DestinationIdea) async {
    await run {
      let more = try await PlanService.destinations(s.brief, avoid: s.ideas.map(\.city), ai: ai)
      if let i = s.ideas.firstIndex(of: idea), let next = more.first { s.ideas[i] = next }
    }
  }

  private func keep(_ idea: DestinationIdea) async {
    s.idea = idea
    s.hotels = []; s.hotel = nil; s.places = [:]; s.kept = []
    s.center = await MapService.search("\(idea.city), \(idea.country)")
    await loadOutline()
  }

  private func loadOutline(note: String = "") async {
    guard let idea = s.idea else { return }
    s.step = .days
    await run { s.outline = try await PlanService.outline(s.brief, idea: idea, note: note, ai: ai) }
  }

  private func loadHotels(note: String = "") async {
    guard let idea = s.idea else { return }
    s.step = .stay
    await run {
      s.hotels = try await PlanService.places(.hotel, area: idea.base, city: idea.city, near: s.center, brief: s.brief,
                                              avoid: note.isEmpty ? [] : s.hotels.map(\.name), note: note, ai: ai)
    }
  }

  private func swapHotel(_ p: PlanPlace) async {
    guard let idea = s.idea else { return }
    await run {
      let more = try await PlanService.places(.hotel, area: idea.base, city: idea.city, near: s.center, brief: s.brief,
                                              avoid: s.hotels.map(\.name), ai: ai)
      if let i = s.hotels.firstIndex(of: p), let next = more.first(where: { !s.hotels.contains($0) }) { s.hotels[i] = next }
    }
  }

  private func loadPlaces(note: String = "") async {
    guard let idea = s.idea, s.outline.indices.contains(s.day), s.places[s.key] == nil else { return }
    let key = s.key, kind = s.kind, day = s.day
    await run {
      s.places[key] = try await PlanService.places(kind, area: s.outline[day].area, city: idea.city, near: s.center,
                                                    brief: s.brief, note: note, day: day, ai: ai)
    }
  }

  private func swapPlace(_ p: PlanPlace) async {
    guard let idea = s.idea, let day = p.day else { return }
    let key = "\(p.kind.rawValue)-\(day)"
    await run {
      let current = s.places[key] ?? []
      let more = try await PlanService.places(p.kind, area: s.outline[day].area, city: idea.city, near: s.center,
                                              brief: s.brief, avoid: current.map(\.name), day: day, ai: ai)
      if let i = current.firstIndex(of: p), let next = more.first(where: { !current.contains($0) }) {
        s.places[key]?[i] = next
        s.kept.removeAll { $0 == p }
      }
    }
  }

  private func toggle(_ p: PlanPlace) {
    if let i = s.kept.firstIndex(of: p) { s.kept.remove(at: i) } else { s.kept.append(p) }
  }

  private func save() async {
    guard let idea = s.idea else { return }
    await PlanService.save(brief: s.brief, idea: idea, outline: s.outline, hotel: s.hotel, kept: s.kept, context: context)
  }

  #if DEBUG
  /// `-planAuto`: answers the brief with sample data and runs every step, then stops at
  /// `-planStep brief|memories|destination|days|stay|eat|book` (default book). Simulator checks only.
  private func debugAuto() async {
    guard ProcessInfo.processInfo.arguments.contains("-planAuto") else { return }
    let target = UserDefaults.standard.string(forKey: "planStep") ?? "book"
    func at(_ name: String) -> Bool { target == name }
    try? await Task.sleep(for: .seconds(1))
    s.brief.country = s.countries.first
    if at("brief") { return }
    s.step = .memories
    s.brief.memory = "A 7am fish-market breakfast in Lisbon, and getting lost in tiny design shops in Copenhagen."
    s.brief.dislikes = ["Long queues", "Tourist traps"]
    await remember()
    if at("memories") { return }
    await loadIdeas()
    if at("destination") { return }
    guard let first = s.ideas.first else { return }
    await keep(first)
    if at("days") { return }
    await loadHotels()
    s.hotel = s.hotels.first
    if at("stay") { return }
    s.step = .eat
    await loadPlaces()
    if let p = s.places[s.key]?.first { s.kept.append(p) }
    if at("eat") { return }
    s.step = .book
  }
  #endif
}

/// ⓘ "Why only these places?"
struct WhyPlacesSheet: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "globe").font(.system(size: 30)).foregroundStyle(MTA.accent).padding(.top, 24)
      Text("Why only these places?").mta(.headline).foregroundStyle(MTA.text)
      Text("When you're offline, Travel Copilot uses the AI built into your iPhone to translate, read menus and answer questions. Right now it speaks a limited set of languages, so we suggest places where offline help works fully.")
        .mta(.body1).foregroundStyle(MTA.text)
      MTALabel("Works fully offline")
      Text(PlanLanguages.languageNames().joined(separator: " · ")).mta(.subheadNormal).foregroundStyle(MTA.text)
      Text("Sorry the list is short. We'll add more languages as the on-device model learns them. You can still type any place: planning works, but offline translation there may not.")
        .mta(.body2).foregroundStyle(MTA.text2)
      Spacer(minLength: 0)
      Button("Got it") { dismiss() }.buttonStyle(.mtaPrimary)
    }
    .mtaScreen().padding(.bottom, 12)
    .background(MTA.surface)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
