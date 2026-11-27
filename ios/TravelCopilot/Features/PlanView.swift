import CoreLocation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// State of one planning conversation (in memory until the user saves the plan).
@MainActor
@Observable
final class PlanSession {
  enum Step: Int, CaseIterable { case brief, memories, avoid, when, destination, days, stay, eat, book }

  var step: Step = .brief
  var brief: PlanBrief
  let countries = PlanLanguages.countries()
  let wantOptions = ["More of that", "Something new", "Slow & rest", "Nightlife"]
  /// Used when there's nothing to guess from, or the suggestion call fails.
  static let fallbackDislikes = ["Long queues", "Tourist traps", "Early starts", "Too much walking", "Big chains"]
  /// Dislikes suggested from the traveller's taste (on-device first).
  var avoidOptions: [String] = []
  /// Timed stops per day (index), made when the traveler opens a day; editable.
  var dayStops: [Int: [DayStop]] = [:]
  /// Photos and files added with +, shown in the step they were added in.
  var attachments: [PlanAttachment] = []
  var openDay: DayIndex?
  /// Budget slider position and the "No limit" chip; copied into `brief.budget` when ideas load.
  var budgetValue: Double = 2500
  var noLimit = false

  /// Photos picked for the memories step: thumbnails in memory only, never saved or uploaded.
  var photoItems: [PhotosPickerItem] = []
  var photos: [UIImage] = []
  /// Every taste word Vision found; `brief.photoLabels` holds the ones the traveller kept.
  var photoAll: [String] = []
  var readingPhotos = false

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
    // Default: the 3rd of next month, 5 days. The traveller changes it on the calendar.
    let first = cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: 1, to: now)!))!
    let start = cal.date(byAdding: .day, value: 2, to: first)!
    brief = PlanBrief(start: start, end: cal.date(byAdding: .day, value: 4, to: start)!)
    if let template {
      brief.country = template.country
      brief.typed = "\(template.city), \(template.theme.lowercased())"
      brief.end = cal.date(byAdding: .day, value: max(0, template.days - 1), to: start)!
    }
  }

  var barIndex: Int {
    switch step {
    case .brief, .memories, .avoid: 0
    case .when, .destination, .days: 1
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

  /// Planning for a trip room (Figma 12 · screens 23–24): same steps, for everyone in the room;
  /// the last step shares the plan to the room.
  var room: TripRoom?

  init(template: PlanTemplate? = nil, room: TripRoom? = nil, onBooked: (() -> Void)? = nil, onClose: @escaping () -> Void) {
    self.onBooked = onBooked
    self.onClose = onClose
    self.room = room
    let session = PlanSession(template: template)
    if let room { session.brief.travelers = max(1, room.members.count) }
    _s = State(initialValue: session)
  }

  @Environment(SocialService.self) private var social
  @State private var keepMine = true
  @State private var sharing = false

  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var net
  @Environment(\.modelContext) private var context
  @Query private var vault: [VaultItem]
  @State private var s: PlanSession
  @State private var input = ""
  @FocusState private var inputFocused: Bool
  @State private var speech = SpeechInput()
  @State private var showAdd = false
  @State private var showCamera = false
  @State private var showFiles = false
  @State private var talking = false
  @State private var talkPhase: TalkSheet.Phase = .listening
  @State private var heard = ""
  @State private var spoken = ""

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
            ForEach(s.attachments.filter { $0.step == s.step }) { a in
              AttachmentTurn(a: a) { Task { await addBookings(a.id) } }
            }
            if s.loading {
              BlueTyping()
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
      .safeAreaInset(edge: .bottom) { bottomBar }
      .navigationTitle(s.idea.map { "\($0.city) · \(s.brief.days) days" } ?? "Plan a trip")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back", systemImage: "chevron.left") { back() }
        }
        ToolbarItem(placement: .topBarTrailing) { Button("Later") { onClose() } }
      }
      .sheet(isPresented: $s.showWhy) { WhyPlacesSheet() }
      .onChange(of: s.photoItems) { Task { await readPhotos() } }
      .sheet(item: $s.openDay) { d in DayPlanSheet(s: s, day: d.id) }
      .overlay(alignment: .bottom) {
        // "Add to chat": drawn here rather than as a system sheet, so its height and white
        // background stay exactly as designed (the embedded photo row confuses sheet sizing).
        if showAdd {
          ZStack(alignment: .bottom) {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { showAdd = false }
              .accessibilityLabel("Close").accessibilityAddTraits(.isButton)
            AddToChatSheet(photos: $s.photoItems,
                           onCamera: { showAdd = false; showCamera = true },
                           onFiles: { showAdd = false; showFiles = true },
                           onClose: { showAdd = false })
              .transition(.move(edge: .bottom))
          }
          .ignoresSafeArea(edges: .bottom)
        }
      }
      .animation(.snappy, value: showAdd)
      .fullScreenCover(isPresented: $showCamera) {
        CameraPicker { img in Task { await addImages([img]) } }.ignoresSafeArea()
      }
      .fileImporter(isPresented: $showFiles, allowedContentTypes: FileReader.types, allowsMultipleSelection: false) { result in
        if case let .success(urls) = result, let url = urls.first { Task { await addFile(url) } }
      }
      .sheet(isPresented: $talking, onDismiss: { stopTalking() }) {
        TalkSheet(phase: $talkPhase, heard: heard, reply: spoken) { talking = false }
      }
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
    case .avoid: avoidStep
    case .when: whenStep
    case .destination: destinationStep
    case .days: daysStep
    case .stay: stayStep
    case .eat: eatStep
    case .book: bookStep
    }
  }

  private var briefStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let room {
        HStack(spacing: 8) {
          MemberStack(initials: room.members.map(\.initial), size: 24)
          Text("For \(room.name) · \(room.members.count) \(room.members.count == 1 ? "person" : "people")").mta(.body2).fontWeight(.semibold)
            .foregroundStyle(MTA.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(MTA.raised, in: .capsule)
        ChatAI("Hi \(ListFormatter.localizedString(byJoining: room.members.map(\.name))))! Where would you like to go? Or shall I suggest a few places?")
      } else {
        ChatAI("Hi! Where would you like to go? Or shall I suggest a few places?")
      }
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
    }
  }

  private var memoriesStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Show me a trip you loved. Add a few photos and tell me what made it special.")
      photoStrip
      if s.readingPhotos {
        BlueTyping(caption: "Reading your photos on this iPhone")
      }
      if !s.photoAll.isEmpty {
        OutlineCard(stroke: MTA.border) {
          MTALabel(s.photos.isEmpty ? "What I see in your photos" : "What I see in your \(s.photos.count) photo\(s.photos.count == 1 ? "" : "s")")
          FlowLayout {
            ForEach(s.photoAll, id: \.self) { w in
              QuickChip(text: w, selected: s.brief.photoLabels.contains(w)) {
                if let i = s.brief.photoLabels.firstIndex(of: w) { s.brief.photoLabels.remove(at: i) } else { s.brief.photoLabels.append(w) }
                s.brief.tags = nil; s.avoidOptions = []
              }
            }
          }
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "iphone").foregroundStyle(MTA.text2)
            Text("Read on this iPhone. Photos never leave it; only these words go to the cloud.").mta(.body2).foregroundStyle(MTA.text2)
          }
        }
      }
      if s.brief.memory.isEmpty {
        Text("Type below too: a meal, a street, a moment.").mta(.body2).foregroundStyle(MTA.text2)
      } else {
        ChatYou(s.brief.memory)
      }
      if !s.brief.memory.isEmpty || !s.brief.photoLabels.isEmpty {
        ChatAI(s.brief.photoLabels.isEmpty ? "Lovely. What do you want this time?"
               : "You light up at \(s.brief.photoLabels.prefix(2).joined(separator: " and ").lowercased()). What do you want this time?")
        FlowLayout {
          ForEach(s.wantOptions, id: \.self) { w in
            QuickChip(text: w, selected: s.brief.want == w) { s.brief.want = s.brief.want == w ? nil : w; s.brief.tags = nil }
          }
        }
      }
    }
  }

  private var photoStrip: some View {
    HStack(spacing: 8) {
      ForEach(Array(s.photos.prefix(4).enumerated()), id: \.offset) { _, img in
        Image(uiImage: img).resizable().scaledToFill().frame(width: 62, height: 62).clipShape(.rect(cornerRadius: 12))
          .accessibilityHidden(true)
      }
      PhotosPicker(selection: $s.photoItems, maxSelectionCount: 6, matching: .images) {
        Image(systemName: s.photos.isEmpty ? "photo.badge.plus" : "plus").font(.system(size: 20, weight: .semibold))
          .foregroundStyle(MTA.accent).frame(width: 62, height: 62)
          .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 4])) }
      }
      .accessibilityLabel(s.photos.isEmpty ? "Add trip photos" : "Change photos")
    }
  }

  private var avoidStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI(s.brief.photoLabels.isEmpty && s.brief.memory.isEmpty
             ? "Anything you don't enjoy on a trip?"
             : "People who love what you love often dislike these. Any of them for you?")
      FlowLayout {
        ForEach(s.avoidOptions + s.brief.dislikes.filter { !s.avoidOptions.contains($0) }, id: \.self) { d in
          QuickChip(text: d, selected: s.brief.dislikes.contains(d)) {
            if let i = s.brief.dislikes.firstIndex(of: d) { s.brief.dislikes.remove(at: i) } else { s.brief.dislikes.append(d) }
            s.brief.tags = nil
          }
        }
        QuickChip(text: "+ Something else") { inputFocused = true }
      }
      if let t = s.brief.tags { rememberCard(t) }
      if s.brief.tags == nil && (!s.brief.memory.isEmpty || !s.brief.photoLabels.isEmpty || !s.brief.dislikes.isEmpty) {
        Button("Remember this") { Task { await remember() } }.buttonStyle(.mtaSecondary).disabled(s.loading)
      }
    }
  }

  private var whenStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("When are you going? Tap your first and last day.")
      RangeCalendar(start: $s.brief.start, end: $s.brief.end, from: AppClock.now)
      HStack(spacing: 8) {
        Text("\(s.brief.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) → \(s.brief.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
          .mta(.subheadNormal).foregroundStyle(MTA.text)
        Text("· \(s.brief.nights) night\(s.brief.nights == 1 ? "" : "s")").mta(.body1).foregroundStyle(MTA.text2)
      }
      FlowLayout {
        QuickChip(text: "My dates are flexible", selected: s.brief.flexible) { s.brief.flexible.toggle() }
      }
      ChatAI("How many people are going?")
      HStack {
        Text("\(s.brief.travelers) traveler\(s.brief.travelers == 1 ? "" : "s")").mta(.subheadNormal).foregroundStyle(MTA.text)
        Spacer()
        CountStepper(value: $s.brief.travelers, range: 1...9, label: "Travelers")
      }
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
      ChatAI("About how much for the whole trip, per person?")
      BudgetSlider(value: $s.budgetValue, range: PlanBudget.range, step: PlanBudget.step)
        .opacity(s.noLimit ? 0.35 : 1).disabled(s.noLimit)
      HStack {
        Text(s.noLimit ? "No limit" : s.brief.travelers == 1
             ? "Up to \(PlanBudget.label(Int(s.budgetValue))) per person"
             : "\(PlanBudget.label(Int(s.budgetValue))) each · \(PlanBudget.label(Int(s.budgetValue) * s.brief.travelers)) for \(s.brief.travelers)")
          .mta(.subheadNormal).foregroundStyle(MTA.text)
        Spacer()
        QuickChip(text: "No limit", selected: s.noLimit) { s.noLimit.toggle() }
      }
      if !s.ideas.isEmpty {
        ChatAI("\(s.ideas.count) ideas for \(s.brief.whenLabel)\(s.brief.budget.map { ", within \(PlanBudget.label($0))" } ?? ""):")
      }
      ForEach(s.ideas, id: \.city) { idea in
        VStack(alignment: .leading, spacing: 8) {
          CityPhotoView(city: idea.city, country: idea.country)
          OptionCard(label: "Destination · \(idea.country)", source: "Gemini", title: idea.city, why: idea.why,
                     badges: [ScoreBadge(label: "Typical", value: idea.weather)], facts: "Stay: \(idea.base)",
                     kept: s.idea == idea,
                     onKeep: { Task { await keep(idea) } },
                     onSwap: { Task { await swap(idea) } })
          costCard(idea)
        }
      }
    }
  }

  private func costCard(_ idea: DestinationIdea) -> some View {
    OutlineCard(stroke: MTA.subtle) {
      MTALabel("Rough cost per person")
      CostLine(label: "Flight · round trip", value: idea.flightCost)
      CostLine(label: "Stay · \(s.brief.nights) nights", value: idea.stayCost)
      CostLine(label: "Eat", value: idea.foodCost)
      CostLine(label: "See & get around", value: idea.seeCost)
      Rectangle().fill(MTA.subtle).frame(height: 1)
      CostLine(label: "Total", value: idea.totalCost, total: true)
      if let max = s.brief.budget, idea.totalHigh > max {
        Text("Over your \(PlanBudget.label(max)) budget").mta(.body2).foregroundStyle(MTA.urgent)
      }
      Text("Estimate from typical prices, not live fares.").mta(.body2).foregroundStyle(MTA.text2)
    }
  }

  private var daysStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Here is a rough shape. Tap a day to see its stops, times and map, and change anything.")
      ForEach(Array(s.outline.enumerated()), id: \.offset) { i, d in
        Button { s.openDay = DayIndex(id: i) } label: {
          HStack(spacing: 14) {
            Milestone(value: "\(i + 1)", state: s.dayStops[i] == nil ? .upcoming : .done)
            VStack(alignment: .leading, spacing: 2) {
              MTALabel(TripTimeline.dayTitle(s.dayDate(i)))
              Text(d.title).mta(.body1).foregroundStyle(MTA.text)
              if let stops = s.dayStops[i], !stops.isEmpty {
                Text("\(stops.count) stops · ~$\(stops.map(\.cost).reduce(0, +))").mta(.body2).foregroundStyle(MTA.text2)
              }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }
      if !s.outline.isEmpty {
        Text("Rough plan from Gemini. Places come next, from Google Maps.").mta(.body2).foregroundStyle(MTA.text2)
      }
    }
  }

  private var stayStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      ChatAI("Hotels near your day plans, from \(s.hotels.first?.source ?? "the map"):")
      ForEach(s.hotels) { p in placeCard(p, kept: s.hotel == p, keep: { s.hotel = p }, swap: { Task { await swapHotel(p) } }) }
      if !s.loading && s.hotels.isEmpty { Text("No hotels came back. Type below to try again.").mta(.body2).foregroundStyle(MTA.text2) }
      if s.hotel != nil {
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
    }
    .onChange(of: s.seeMode) { Task { await loadPlaces() } }
    .onChange(of: s.day) { Task { await loadPlaces() } }
  }

  /// A pasted confirmation in the Vault for this trip, if any.
  private func booking(_ kind: String) -> VaultItem? {
    guard let idea = s.idea else { return nil }
    // Same city, not just the same country: a Tokyo hotel isn't the booking for a Fukuoka trip.
    return vault.first { item in
      item.kind == kind && [item.destination, item.title, item.address].contains {
        ($0 ?? "").localizedCaseInsensitiveContains(idea.city)
      }
    }
  }

  private var bookStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let idea = s.idea {
        VStack(alignment: .leading, spacing: 4) {
          MTALabel("\(idea.city) · \(s.brief.whenLabel) · \(s.brief.nights) nights · \(s.brief.travelers) \(s.brief.travelers == 1 ? "traveler" : "travelers")")
          Text(idea.why).mta(.subheadNormal).foregroundStyle(MTA.text)
        }
        ChatAI("Your plan is ready. Book on the airline and hotel sites, then paste the confirmation emails: they become your receipts here.")
        let flight = booking("flight"), stay = booking("hotel")
        BookRow(systemImage: "airplane", title: "Flight to \(idea.city)",
                detail: flight.map { "Booked\($0.confirmationCode.map { " · Ref \($0)" } ?? "")" } ?? "Est. \(idea.flightCost) · Google Flights",
                url: PlanService.flightsURL(city: idea.city, start: s.brief.start, adults: s.brief.travelers), booked: flight != nil)
        BookRow(systemImage: "bed.double.fill", title: stay?.title ?? s.hotel?.name ?? "Hotel in \(idea.base)",
                detail: stay.map { "Booked\($0.confirmationCode.map { " · Ref \($0)" } ?? "")" } ?? "Est. \(idea.stayCost) · Booking.com",
                url: PlanService.hotelURL(name: s.hotel?.name ?? idea.base, city: idea.city, start: s.brief.start, end: s.brief.end,
                                          adults: s.brief.travelers),
                booked: stay != nil)
        BookRow(systemImage: "fork.knife", title: "\(s.kept.count) place\(s.kept.count == 1 ? "" : "s") to eat & see",
                detail: "Est. \(idea.foodCost) + \(idea.seeCost) · no booking needed", url: nil)
        OutlineCard(stroke: MTA.border) {
          CostLine(label: "Booked", value: "\([flight, stay].compactMap { $0 }.count) of 2")
          CostLine(label: s.brief.travelers == 1 ? "Trip total (est.)" : "Per person (est.)", value: idea.totalCost, total: true)
          if s.brief.travelers > 1 {
            CostLine(label: "For all \(s.brief.travelers) (est.)", value: "up to ~\(PlanBudget.label(idea.totalHigh * s.brief.travelers))")
          }
          if let max = s.brief.budget {
            Text(idea.totalHigh <= max ? "Within your \(PlanBudget.label(max)) budget" : "Over your \(PlanBudget.label(max)) budget")
              .mta(.body2).foregroundStyle(idea.totalHigh <= max ? MTA.onTrack : MTA.urgent)
          }
        }
      }
      NoticeCard(text: "Suggestions aren't bookings. Only pasted confirmations go into your Vault.")
      if let room {
        Toggle(isOn: $keepMine) { Text("Also add to my trip").mta(.body1).foregroundStyle(MTA.text) }
          .tint(MTA.onTrack)
        Text("Everyone in \(room.name) gets this plan and can change it. Your bookings and Vault stay on this iPhone.")
          .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      }
      if onBooked != nil && room == nil {
        Button("Book later") { Task { await save(); onClose() } }.buttonStyle(.mtaSecondary)
      }
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

  // MARK: Bottom: the step's main button, then the chat bar

  private struct StepAction { let title: String; var enabled = true; let run: () -> Void }

  /// Each step's main action, pinned above the chat bar so it's always in reach.
  private var primary: StepAction? {
    switch s.step {
    case .brief: return StepAction(title: "Next") { s.step = .memories }
    case .memories:
      return StepAction(title: s.brief.memory.isEmpty && s.brief.photoLabels.isEmpty ? "Skip" : "Next",
                        enabled: !s.loading && !s.readingPhotos) { Task { await suggestAvoid() } }
    case .avoid: return StepAction(title: "Next: pick dates", enabled: !s.loading) { s.step = .when }
    case .when: return StepAction(title: "Use these dates") { s.ideas = []; s.step = .destination }
    case .destination:
      return StepAction(title: s.ideas.isEmpty ? "Show me ideas" : "Update ideas", enabled: !s.loading && net.isOnline) {
        s.brief.budget = s.noLimit ? nil : Int(s.budgetValue)
        Task { await loadIdeas() }
      }
    case .days:
      return s.outline.isEmpty ? nil : StepAction(title: "Looks good, find a hotel", enabled: !s.loading) { Task { await loadHotels() } }
    case .stay:
      return s.hotel == nil ? nil : StepAction(title: "Next: eat & see") { s.step = .eat; Task { await loadPlaces() } }
    case .eat: return StepAction(title: "Done, book these", enabled: !s.loading) { s.step = .book }
    case .book:
      if room != nil {
        return StepAction(title: sharing ? "Sharing…" : "Share plan with the room", enabled: !sharing) { Task { await shareToRoom() } }
      }
      if let onBooked { return StepAction(title: "I've booked, paste confirmations") { Task { await save(); onBooked() } } }
      return StepAction(title: "Save to my trip") { Task { await save(); onClose() } }
    }
  }

  private var bottomBar: some View {
    VStack(spacing: 10) {
      if let p = primary {
        Button(p.title, action: p.run).buttonStyle(.mtaPrimary).disabled(!p.enabled)
      }
      PlanComposer(text: $input, placeholder: placeholder, focused: $inputFocused,
                   canSend: !s.loading, speech: speech, onSend: send,
                   onPlus: { inputFocused = false; showAdd = true },
                   onTalk: { startTalking() })
    }
    .padding(.horizontal, MTA.margin).padding(.top, 8).padding(.bottom, 8)
    .background(MTA.surface)
  }

  private var placeholder: String {
    switch s.step {
    case .brief: "Or type a place or idea…"
    case .memories: "A trip you loved…"
    case .avoid: "Anything else?"
    case .destination: "Somewhere warmer? Smaller towns?"
    case .days: "More food, a slower day 3…"
    case .stay: "Cheaper? Closer to the station?"
    case .when: "Message Blue…"
    case .book: "Message Blue…"
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
    case .memories: s.brief.memory = text; s.brief.tags = nil; s.avoidOptions = []
    case .avoid: if !s.brief.dislikes.contains(text) { s.brief.dislikes.append(text) }; s.brief.tags = nil
    case .when: s.brief.notes.append(text)
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

  /// Reads the picked photos on this iPhone with Vision and keeps only the taste words.
  private func readPhotos() async {
    let items = s.photoItems
    guard !items.isEmpty else { return }
    // Outside the memories step, photos come in as a chat message that Blue answers.
    if s.step != .memories {
      var images: [UIImage] = []
      for item in items {
        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
      }
      s.photoItems = []
      await addImages(images)
      return
    }
    s.readingPhotos = true
    defer { s.readingPhotos = false }
    let start = ContinuousClock.now
    var thumbs: [UIImage] = []
    var perPhoto: [[(String, Float)]] = []
    for item in items {
      guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
      thumbs.append(image.preparingThumbnail(of: CGSize(width: 200, height: 200)) ?? image)
      guard let cg = (image.preparingThumbnail(of: CGSize(width: 640, height: 640)) ?? image).cgImage else { continue }
      let labels = await Task.detached(priority: .userInitiated) { (try? PhotoTaste.labels(for: cg)) ?? [] }.value
      perPhoto.append(labels)
    }
    s.photos = thumbs
    s.photoAll = PhotoTaste.summarize(perPhoto)
    s.brief.photoLabels = s.photoAll
    s.brief.tags = nil; s.avoidOptions = []
    ai.logOnDevice("Plan · read photos", .survive,
                   reason: "Apple Vision on this iPhone · \(thumbs.count) photos · photos stay on the phone",
                   latencyMs: (ContinuousClock.now - start).milliseconds,
                   note: s.photoAll.isEmpty ? "Nothing recognised" : s.photoAll.joined(separator: " · "))
  }

  /// A photo from the camera (or any image): read on this iPhone like the picked photos.
  private func addImages(_ images: [UIImage]) async {
    guard !images.isEmpty else { return }
    let start = ContinuousClock.now
    var perPhoto: [[(String, Float)]] = []
    for image in images {
      guard let cg = (image.preparingThumbnail(of: CGSize(width: 640, height: 640)) ?? image).cgImage else { continue }
      perPhoto.append(await Task.detached(priority: .userInitiated) { (try? PhotoTaste.labels(for: cg)) ?? [] }.value)
    }
    let thumbs = images.map { $0.preparingThumbnail(of: CGSize(width: 200, height: 200)) ?? $0 }
    let words = PhotoTaste.summarize(perPhoto)
    s.photos += thumbs
    for w in words where !s.photoAll.contains(w) { s.photoAll.append(w); s.brief.photoLabels.append(w) }
    s.brief.tags = nil
    if s.step == .memories { s.avoidOptions = [] }   // later steps keep the dislikes already suggested
    if s.step != .memories {   // the memories step shows the photos card itself
      var a = PlanAttachment(step: s.step, thumbs: thumbs)
      a.reply = words.isEmpty ? "Got it. I couldn't tell much from that photo, but I'll keep it in mind."
        : "I see \(words.prefix(3).joined(separator: ", ").lowercased()). I'll keep that in mind."
      s.attachments.append(a)
    }
    ai.logOnDevice("Plan · read a photo", .survive, reason: "Apple Vision on this iPhone · photos stay on the phone",
                   latencyMs: (ContinuousClock.now - start).milliseconds, note: words.joined(separator: " · "))
  }

  /// A file added with +: read on this iPhone. A booking confirmation is offered for the Vault;
  /// anything else becomes a short gist Blue plans around (on-device model first).
  private func addFile(_ url: URL) async {
    if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { await addImages([img]) }
      return
    }
    var a = PlanAttachment(step: s.step, fileName: url.lastPathComponent)
    guard let (text, pages) = FileReader.read(url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      a.reply = "I couldn't read any text in that file. Try a PDF or a text document."
      s.attachments.append(a); return
    }
    a.pages = pages
    s.attachments.append(a)
    let id = a.id
    func update(_ change: (inout PlanAttachment) -> Void) {
      if let i = s.attachments.firstIndex(where: { $0.id == id }) { change(&s.attachments[i]) }
    }
    if FileReader.looksLikeBooking(text) {
      update { $0.bookingText = text; $0.reply = "This looks like a booking confirmation. Shall I add it to your bookings? Then it works offline on the trip." }
      return
    }
    do {
      let (g, meta) = try await ai.generate("Plan · read a file", kind: .survive,
                                            prompt: "A traveler shared this document while planning a trip:\n\(text.prefix(3000))",
                                            instructions: "Say what it tells you about their travel taste or plans. Use only what the document says.",
                                            as: FileGist.self)
      s.brief.notes.append(g.gist); s.brief.tags = nil
      update { $0.reply = (meta.source == .onDevice ? "I read it on this iPhone: " : "I read it: ") + g.gist + ". I'll plan around that." }
    } catch {
      s.brief.notes.append(String(text.prefix(300)))
      update { $0.reply = "I read it, and I'll keep it in mind." }
    }
  }

  private func addBookings(_ id: UUID) async {
    guard let i = s.attachments.firstIndex(where: { $0.id == id }), let text = s.attachments[i].bookingText else { return }
    await run {
      let (items, added) = try await PrepareService.saveBookings(from: text, ai: ai)
      if let j = s.attachments.firstIndex(where: { $0.id == id }) {
        s.attachments[j].added = true
        s.attachments[j].reply = items.isEmpty ? "I couldn't find a booking in it."
          : added == 0 ? "Those bookings are already in your Vault." : "Added \(added) booking\(added == 1 ? "" : "s") to your Vault."
      }
    }
  }

  // MARK: Talk

  private func startTalking() {
    inputFocused = false; heard = ""; spoken = ""
    talking = true
    Task { await talkLoop() }
  }

  private func stopTalking() {
    talking = false
    speech.stop()
    Speaker.shared.stop()
  }

  /// Listen → send what was said → wait for Blue → say Blue's answer → listen again.
  private func talkLoop() async {
    while talking {
      talkPhase = .listening; heard = ""
      let said: String = await withCheckedContinuation { c in
        Task { await speech.listenOnce(onText: { heard = $0 }, onDone: { c.resume(returning: $0) }) }
      }
      guard talking else { return }
      if speech.error != nil { talking = false; return }
      let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      talkPhase = .thinking
      input = text; send()
      try? await Task.sleep(for: .milliseconds(300))
      while s.loading && talking { try? await Task.sleep(for: .milliseconds(200)) }
      guard talking else { return }
      spoken = spokenReply
      talkPhase = .speaking
      Speaker.shared.toggle(spoken, languageCode: "en", id: "talk")
      while Speaker.shared.speakingID == "talk" && talking { try? await Task.sleep(for: .milliseconds(200)) }
    }
  }

  /// What Blue says out loud after you speak, from what's on screen now.
  private var spokenReply: String {
    if let e = s.error { return e }
    switch s.step {
    case .brief: return "Got it. Tap Next when you're ready, or tell me more."
    case .memories: return "Lovely. Anything else about that trip? Or tap Next."
    case .avoid: return "Noted, I'll avoid that. Anything else you don't enjoy?"
    case .when: return "Got it. Pick your dates on the calendar."
    case .destination:
      let names = s.ideas.map(\.city)
      return names.isEmpty ? "I couldn't find ideas for that yet." : "I found \(names.count) ideas: \(names.joined(separator: ", ")). Tap Keep on the one you like."
    case .days: return "Here's the new shape: " + s.outline.enumerated().map { "day \($0.offset + 1), \($0.element.title)" }.joined(separator: "; ") + "."
    case .stay: return s.hotels.isEmpty ? "No hotels came back for that." : "Here are hotels: " + s.hotels.prefix(3).map(\.name).joined(separator: ", ") + "."
    case .eat: return (s.places[s.key] ?? []).isEmpty ? "Nothing came back for that." : "Here are some places: " + (s.places[s.key] ?? []).prefix(3).map(\.name).joined(separator: ", ") + "."
    case .book: return "Your plan is ready. Book on the airline and hotel sites, then paste the emails."
    }
  }

  /// Dislikes guessed from the traveller's taste; a fixed list when there's nothing to go on or it fails.
  private func suggestAvoid() async {
    s.step = .avoid
    guard s.avoidOptions.isEmpty else { return }
    if s.brief.memory.isEmpty && s.brief.photoLabels.isEmpty { s.avoidOptions = PlanSession.fallbackDislikes; return }
    await run { s.avoidOptions = try await PlanService.suggestAvoid(s.brief, ai: ai) }
    if s.avoidOptions.isEmpty { s.avoidOptions = PlanSession.fallbackDislikes; s.error = nil }
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
    s.hotels = []; s.hotel = nil; s.places = [:]; s.kept = []; s.dayStops = [:]
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

  /// Shares the plan to the room (and keeps a copy in your own trip when the switch is on).
  private func shareToRoom() async {
    guard let room else { return }
    sharing = true; defer { sharing = false }
    let drafts = PlanService.sharedStops(brief: s.brief, outline: s.outline, stops: s.dayStops, hotel: s.hotel, kept: s.kept)
    guard await social.sharePlan(drafts, in: room) else { s.error = social.error ?? "Couldn't share the plan. Try again."; return }
    if keepMine { await save() }
    onClose()
  }

  private func save() async {
    guard let idea = s.idea else { return }
    await PlanService.save(brief: s.brief, idea: idea, outline: s.outline, stops: s.dayStops, hotel: s.hotel, kept: s.kept, context: context)
  }

  #if DEBUG
  /// `-planAuto`: answers the brief with sample data and runs every step, then stops at
  /// `-planStep brief|memories|avoid|when|destination|days|stay|eat|book` (default book). Simulator checks only.
  private func debugAuto() async {
    guard ProcessInfo.processInfo.arguments.contains("-planAuto") else { return }
    let target = UserDefaults.standard.string(forKey: "planStep") ?? "book"
    func at(_ name: String) -> Bool { target == name }
    try? await Task.sleep(for: .seconds(1))
    s.brief.country = s.countries.first
    if at("brief") { return }
    s.step = .memories
    s.brief.memory = "A 7am fish-market breakfast in Lisbon, and getting lost in tiny design shops in Copenhagen."
    s.photoAll = ["Street food", "Market", "Old town", "Design shop"]
    s.brief.photoLabels = s.photoAll
    s.brief.want = "More of that"
    if at("memories") { return }
    await suggestAvoid()
    s.brief.dislikes = Array(s.avoidOptions.prefix(2))
    await remember()
    if at("avoid") { return }
    s.step = .when
    s.brief.travelers = 2
    if at("when") { return }
    s.step = .destination
    s.budgetValue = 2500
    s.brief.budget = 2500
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
