import SwiftUI
import SwiftData

/// Trip: the whole trip as a list or a month calendar. Everything is local and works offline.
struct TripView: View {
  @Environment(\.modelContext) private var context
  @Environment(AppRouter.self) private var router
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query private var packs: [DestinationPack]
  @Query(sort: \TripPlan.start) private var plans: [TripPlan]
  @State private var mode: Int = {
    #if DEBUG
      if UserDefaults.standard.string(forKey: "tripMode") == "calendar" { return 1 }
    #endif
    return 0
  }()
  @State private var selectedDay: Date?
  @State private var planDay: Date?
  @State private var taxiItem: VaultItem?

  private var pack: DestinationPack? { packs.first }
  private var place: String { pack?.countryName ?? "Your" }

  var body: some View {
    let events = TripTimeline.events(items: items, plans: plans)
    let range = TripTimeline.range(events)
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          MTASegmented(options: ["List", "Calendar"], selection: $mode)
          if items.isEmpty {
            emptyState
          } else if mode == 0 {
            listContent(events: events, range: range)
          } else {
            calendarContent(events: events, range: range)
          }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .navigationTitle("Trip")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(item: $planDay) { PlanDayView(day: $0) }
      #if DEBUG
      .task {
        // `-planDay 2026-12-04` opens Plan a day directly (simulator checks).
        if let s = UserDefaults.standard.string(forKey: "planDay"), let d = TripTimeline.date(s, "00:00") { planDay = d }
      }
      #endif
      .fullScreenCover(item: $taxiItem) { item in
        BigCardView(item: item, pack: packs.first { $0.countryCode == item.countryCode } ?? pack)
      }
    }
  }

  // MARK: - List

  @ViewBuilder
  private func listContent(events: [TripEvent], range: ClosedRange<Date>?) -> some View {
    if let range {
      MTALabel(rangeTitle(range))
      Text("\(place) trip").mta(.displayMedium).foregroundStyle(MTA.text)
      dayStrip(range: range)
    }
    MTALabel(todayTitle(range: range))
    ForEach(items) { item in
      VaultCardView(item: item, status: status(of: item)) { taxiItem = item }
        .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) } }
    }
    if let pack, !pack.phrases.isEmpty {
      MTALabel("\(pack.languageName) phrases").padding(.top, 8)
      VStack(spacing: 0) {
        ForEach(pack.phrases, id: \.self) { p in
          VStack(alignment: .leading, spacing: 2) {
            Text(p.local).mta(.subheadNormal).foregroundStyle(MTA.text)
            if !p.romanization.isEmpty { Text(p.romanization).mta(.body2).foregroundStyle(MTA.text2) }
            Text(p.english).mta(.body2).foregroundStyle(MTA.text)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 10)
          .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle).frame(height: 1) }
        }
      }
    }
  }

  private func dayStrip(range: ClosedRange<Date>) -> some View {
    let days = TripTimeline.days(in: range)
    return HStack(spacing: 0) {
      ForEach(days, id: \.self) { d in
        Button { planDay = d } label: {
          VStack(spacing: 6) {
            Milestone(value: dayNumber(d), state: dayState(d, range: range))
            MTALabel(d.formatted(.dateTime.weekday(.abbreviated)), color: labelColor(d, range: range))
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Plan \(TripTimeline.dayTitle(d))")
      }
    }
  }

  // MARK: - Calendar

  @ViewBuilder
  private func calendarContent(events: [TripEvent], range: ClosedRange<Date>?) -> some View {
    if let range {
      TripPoster(place: place, events: events, days: TripTimeline.days(in: range).count)
      ForEach(months(in: range), id: \.self) { month in
        MonthCard(month: month, range: range, selected: selectedDay ?? defaultSelection(range),
                  state: { dayState($0, range: range) }) { selectedDay = $0 }
      }
      let day = selectedDay ?? defaultSelection(range)
      let dayEvents = TripTimeline.events(on: day, events)
      VStack(alignment: .leading, spacing: 8) {
        MTALabel(TripTimeline.dayTitle(day) + (TripTimeline.calendar.isDate(day, inSameDayAs: AppClock.now) ? " · today" : ""),
                 color: MTA.accent)
        if dayEvents.isEmpty {
          Text("Nothing planned yet.").mta(.body1).foregroundStyle(MTA.text2)
        }
        ForEach(dayEvents) { e in
          HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(TripTimeline.time(e.date)).mta(.subheadNormal).monospacedDigit().foregroundStyle(MTA.text).frame(width: 52, alignment: .leading)
            Text(e.title).mta(.body1).foregroundStyle(MTA.text)
          }
        }
        Button("Plan this day") { planDay = day }.buttonStyle(.mtaSecondary(height: 44)).padding(.top, 6)
      }
    }
  }

  private func months(in range: ClosedRange<Date>) -> [Date] {
    let cal = TripTimeline.calendar
    var out: [Date] = []
    var m = cal.date(from: cal.dateComponents([.year, .month], from: range.lowerBound))!
    while m <= range.upperBound { out.append(m); m = cal.date(byAdding: .month, value: 1, to: m)! }
    return out
  }

  private func defaultSelection(_ range: ClosedRange<Date>) -> Date {
    let today = TripTimeline.calendar.startOfDay(for: AppClock.now)
    return range.contains(today) ? today : range.lowerBound
  }

  // MARK: - States (color = status)

  private func dayState(_ d: Date, range: ClosedRange<Date>) -> Milestone.State {
    let cal = TripTimeline.calendar
    let today = cal.startOfDay(for: AppClock.now)
    guard range.contains(d) else { return .off }
    if cal.isDate(d, inSameDayAs: today) { return .today }
    if d < today { return .done }
    if cal.isDate(d, inSameDayAs: range.upperBound) { return .deadline }
    return .upcoming
  }

  private func labelColor(_ d: Date, range: ClosedRange<Date>) -> Color {
    switch dayState(d, range: range) { case .today: MTA.accent; case .deadline: MTA.urgent; default: MTA.text2 }
  }

  private func status(of item: VaultItem) -> MTAStatus {
    let end = TripTimeline.date(item.endDate ?? item.startDate, item.checkOutTime ?? item.arrivalTime, defaultTime: "23:59")
    if let end, end < AppClock.now { return .onTrack }
    return .accent
  }

  private func dayNumber(_ d: Date) -> String { "\(TripTimeline.calendar.component(.day, from: d))" }

  private func rangeTitle(_ r: ClosedRange<Date>) -> String {
    "\(r.lowerBound.formatted(.dateTime.month(.abbreviated).day())) – \(r.upperBound.formatted(.dateTime.month(.abbreviated).day())) · \(place)"
  }

  private func todayTitle(range: ClosedRange<Date>?) -> String {
    guard let range, range.contains(TripTimeline.calendar.startOfDay(for: AppClock.now)) else { return "Bookings" }
    return "Today · \(TripTimeline.dayTitle(AppClock.now))"
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("No trip yet").mta(.displayMedium).foregroundStyle(MTA.text)
      Text("Paste your booking confirmations in Prepare while you're online.").mta(.body1).foregroundStyle(MTA.text2)
      Button("Go to Prepare") { router.tab = .prepare }.buttonStyle(.mtaPrimary)
    }
    .padding(.top, 8)
  }
}

// MARK: - Vault card

struct VaultCardView: View {
  let item: VaultItem
  var status: MTAStatus = .accent
  var showTaxi: () -> Void

  var body: some View {
    OutlineCard(stroke: status == .onTrack ? MTA.subtle : MTA.border) {
      HStack(spacing: 10) {
        TripBullet(systemName: status == .onTrack ? "checkmark" : symbol, status: status, size: 24)
        Text(item.title).mta(.subheadMedium).foregroundStyle(MTA.text).lineLimit(3)
      }
      if item.kind == "hotel" {
        if let s = item.startDate { FieldRow(label: "Check-in", value: [s, item.checkInTime].compactMap { $0 }.joined(separator: " · ")) }
        if let e = item.endDate { FieldRow(label: "Check-out", value: [e, item.checkOutTime].compactMap { $0 }.joined(separator: " · ")) }
      } else {
        if let s = item.startDate { FieldRow(label: "Departs", value: [s, item.departureTime].compactMap { $0 }.joined(separator: " · ")) }
        if let e = item.endDate ?? item.startDate, item.arrivalTime != nil { FieldRow(label: "Arrives", value: [e, item.arrivalTime].compactMap { $0 }.joined(separator: " · ")) }
      }
      if let code = item.confirmationCode { FieldRow(label: "Ref", value: code) }
      if let a = item.address { FieldRow(label: "Address", value: a) }
      if item.addressLocal != nil {
        Button("Show to taxi driver", action: showTaxi).buttonStyle(.mtaSecondary(height: 44))
      }
    }
  }

  private var symbol: String {
    switch item.kind { case "flight": "airplane"; case "hotel": "bed.double.fill"; case "train": "tram.fill"; default: "doc.text.fill" }
  }
}

// MARK: - Poster (MTA lifestyle: blue card, yellow starburst, badges)

struct TripPoster: View {
  let place: String
  let events: [TripEvent]
  let days: Int

  var body: some View {
    let flights = events.filter { $0.kind == .depart }
    let nights = max(0, days - 1)
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 20).fill(MTA.accent)
      StarBurst(points: 18, innerRatio: 0.84)
        .fill(MTA.notice)
        .frame(width: 118, height: 118)
        .overlay { Text(place.uppercased()).mta(.headline).foregroundStyle(MTA.onNotice).lineLimit(1).minimumScaleFactor(0.5).padding(18) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
      if let first = flights.first {
        badge(first.date.formatted(.dateTime.month(.abbreviated).day()), "airplane", .onTrack).rotationEffect(.degrees(8))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 30).padding(.top, 28)
      }
      badge("× \(nights)", "bed.double.fill", .onTrack).rotationEffect(.degrees(-10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.trailing, 26).padding(.top, 22)
      if flights.count > 1, let last = flights.last {
        badge(last.date.formatted(.dateTime.month(.abbreviated).day()), "airplane", .urgent).rotationEffect(.degrees(8))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.trailing, 22).padding(.top, 84)
      }
      MTALabel("\(days) days · \(flights.count) \(flights.count == 1 ? "flight" : "flights") · \(nights) \(nights == 1 ? "night" : "nights")",
               color: MTA.onColor).padding(16)
    }
    .frame(height: 150)
    .accessibilityElement(children: .combine)
  }

  private func badge(_ text: String, _ symbol: String, _ s: MTAStatus) -> some View {
    HStack(spacing: 4) { Image(systemName: symbol).font(.system(size: 10, weight: .bold)); Text(text).mta(.label) }
      .foregroundStyle(s.foreground)
      .padding(.horizontal, 12).padding(.vertical, 6)
      .background(s.color, in: .capsule)
      .overlay { Capsule().strokeBorder(.white, lineWidth: 2) }
  }
}

struct StarBurst: Shape {
  let points: Int
  let innerRatio: CGFloat
  func path(in rect: CGRect) -> Path {
    let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
    var p = Path()
    for i in 0..<(points * 2) {
      let a = Double(i) * .pi / Double(points) - .pi / 2
      let rr = i.isMultiple(of: 2) ? r : r * innerRatio
      let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
      i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
  }
}

// MARK: - Month card (Monday-first, equal cells)

struct MonthCard: View {
  let month: Date
  let range: ClosedRange<Date>
  let selected: Date
  let state: (Date) -> Milestone.State
  let onSelect: (Date) -> Void

  var body: some View {
    let cal = TripTimeline.calendar
    let days = cal.range(of: .day, in: .month, for: month)!.map { cal.date(byAdding: .day, value: $0 - 1, to: month)! }
    let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
    let cells: [Date?] = Array(repeating: nil, count: lead) + days + Array(repeating: nil, count: (7 - (lead + days.count) % 7) % 7)
    let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(month.formatted(.dateTime.month(.wide))).mta(.subheadNormal)
        Spacer()
        Text(month.formatted(.dateTime.year())).mta(.subheadNormal)
      }
      .foregroundStyle(MTA.text)
      LazyVGrid(columns: cols, spacing: 7) {
        ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
          Milestone(value: ["M", "T", "W", "T", "F", "S", "S"][i], state: .header, size: 36)
        }
        ForEach(cells.indices, id: \.self) { i in
          if let d = cells[i] {
            Button { onSelect(d) } label: {
              Milestone(value: "\(cal.component(.day, from: d))", state: state(d), size: 36)
                .overlay { if cal.isDate(d, inSameDayAs: selected) { Circle().strokeBorder(MTA.text, lineWidth: 1).padding(-3) } }
            }
            .buttonStyle(.plain)
            .disabled(!range.contains(d))
            .accessibilityLabel(TripTimeline.dayTitle(d))
          } else {
            Milestone(value: " ", state: .off, size: 36)
          }
        }
      }
      HStack(spacing: 10) {
        legend(MTA.onTrack, "done"); legend(MTA.accent, "today"); legend(MTA.border, "planned"); legend(MTA.urgent, "check-out"); legend(MTA.raised, "off")
      }
    }
    .padding(16)
    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MTA.subtle, lineWidth: 1) }
  }

  private func legend(_ c: Color, _ t: String) -> some View {
    HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t).mta(.body2).foregroundStyle(MTA.text2).lineLimit(1) }
  }
}
