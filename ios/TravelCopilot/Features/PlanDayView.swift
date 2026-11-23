import SwiftUI
import SwiftData

/// One trip day: bookings from the Vault plus the traveler's own plans, in time order.
struct PlanDayView: View {
  let day: Date
  @Environment(\.modelContext) private var context
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query(sort: \TripPlan.start) private var plans: [TripPlan]
  @Query private var packs: [DestinationPack]
  @AppStorage("planReminders") private var reminders = true
  @State private var adding = false
  @State private var editing: TripPlan?

  var body: some View {
    let all = TripTimeline.events(items: items, plans: plans)
    let range = TripTimeline.range(all)
    let dayEvents = TripTimeline.events(on: day, all)
    TimelineView(.periodic(from: .now, by: 30)) { _ in
    let now = AppClock.now
    let nextID = all.first { $0.date > now }?.id
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          MTALabel(dayLine(range))
          Spacer()
          let total = dayPlans.compactMap(\.cost).reduce(0, +)
          if total > 0 { Text("~$\(total) est.").mta(.button2).foregroundStyle(MTA.accent) }
        }
        Text("Plan your day").mta(.displayMedium).foregroundStyle(MTA.text)
        if dayEvents.isEmpty {
          Text("Nothing on this day yet. Add a place, a meal or a ticket.").mta(.body1).foregroundStyle(MTA.text2)
        }
        ForEach(Array(dayEvents.enumerated()), id: \.element.id) { i, e in
          let end = dayEvents.indices.contains(i + 1) ? dayEvents[i + 1].date : nil
          let plan = e.kind == .plan ? plans.first(where: { "plan-\($0.createdAt.timeIntervalSince1970)" == e.id }) : nil
          PlanCard(event: e, progress: TripProgress.of(start: e.date, end: end, now: now, isNext: e.id == nextID), now: now)
            .contentShape(.rect)
            .onTapGesture { if let plan { editing = plan } }
            .accessibilityAddTraits(plan == nil ? [] : .isButton)
            .accessibilityHint(plan == nil ? "" : "Shows the stop and lets you change it")
            .contextMenu {
              if e.kind == .plan, let p = plans.first(where: { "plan-\($0.createdAt.timeIntervalSince1970)" == e.id }) {
                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(p) }
              }
            }
        }
        MTAToggleRow(title: "Remind me with Live Activities", isOn: $reminders)
        Text("A notification 30 min before each plan, and the next one on your Lock Screen with a live countdown.")
          .mta(.body2).foregroundStyle(MTA.text2)
        NoticeCard(text: "Plans live on this iPhone and work offline. Suggestions need Wi-Fi and are labeled.")
        Button("Add a plan") { adding = true }.buttonStyle(.mtaPrimary).padding(.top, 4)
      }
      .mtaScreen().padding(.top, 8).padding(.bottom, 24)
    }
    }
    .scrollIndicators(.hidden)
    .background(MTA.surface)
    .navigationTitle(TripTimeline.dayTitle(day))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { Button("Add") { adding = true } }
    }
    .sheet(isPresented: $adding) { AddPlanSheet(day: day).presentationDetents([.medium]) }
    .sheet(item: $editing) { p in
      StopDetailView(stop: DayStop(time: p.start, kind: p.kind ?? "Plan", name: p.title, why: p.detail, address: "",
                                   latitude: p.latitude ?? 0, longitude: p.longitude ?? 0, cost: p.cost ?? 0, note: p.note),
                     onSave: { st in
                       p.start = st.time; p.title = st.name; p.cost = st.cost; p.note = st.note
                       try? context.save()
                     },
                     onRemove: { context.delete(p); try? context.save() })
    }
  }

  private var dayPlans: [TripPlan] {
    plans.filter { TripTimeline.calendar.isDate($0.start, inSameDayAs: day) }
  }

  private func dayLine(_ range: ClosedRange<Date>?) -> String {
    let place = packs.first?.countryName ?? "Trip"
    guard let range, range.contains(day) else { return place }
    let n = (TripTimeline.calendar.dateComponents([.day], from: range.lowerBound, to: day).day ?? 0) + 1
    return "Day \(n) of \(TripTimeline.days(in: range).count) · \(place)"
  }
}

/// Time + title card. The color shows progress (done / now / next / soon / later);
/// where the plan came from is a neutral chip, so color only ever means status.
struct PlanCard: View {
  let event: TripEvent
  var progress: TripProgress = .later
  var now: Date = AppClock.now

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(TripTimeline.time(event.date)).mta(.button1).monospacedDigit().foregroundStyle(fg)
        if progress == .done {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(MTA.text2)
        }
      }
      .frame(width: 62, alignment: .leading)
      VStack(alignment: .leading, spacing: 4) {
        Text(event.title).mta(.subheadNormal).foregroundStyle(fg).strikethrough(progress == .done, color: MTA.text2)
        if !event.detail.isEmpty { Text(event.detail).mta(.body2).foregroundStyle(fg2) }
        Chip(text: source.text, systemImage: source.symbol, color: fg2).fixedSize()
      }
      Spacer(minLength: 0)
      if let label = progress.label(start: event.date, now: now), progress != .done {
        Text(label.uppercased()).mta(.label).foregroundStyle(pillFG)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(pillBG, in: .capsule)
          .fixedSize()
      }
    }
    .padding(14)
    .background(progress == .now ? MTA.accent : .clear, in: .rect(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: progress == .soon ? 3 : 2) }
    .opacity(progress == .done ? 0.6 : 1)
    .accessibilityElement(children: .combine)
    .accessibilityValue(progress.label(start: event.date, now: now) ?? "")
  }

  private var stroke: Color {
    switch progress {
    case .done: MTA.subtle
    case .now: MTA.accent
    case .next: MTA.onTrack
    case .soon: MTA.urgent
    case .later: MTA.border
    }
  }
  private var fg: Color { progress == .now ? MTA.onColor : (progress == .done ? MTA.text2 : MTA.text) }
  private var fg2: Color { progress == .now ? MTA.onColor.opacity(0.85) : MTA.text2 }
  private var pillBG: Color {
    switch progress { case .now: MTA.onColor; case .next: MTA.onTrack; case .soon: MTA.urgent; default: .clear }
  }
  private var pillFG: Color { progress == .now ? MTA.accent : MTA.onColor }

  private var source: (text: String, symbol: String?) {
    switch event.planSource {
    case nil: ("From booking", event.symbol)
    case "suggested": ("Suggested", "icloud")
    default: ("You added", nil)
    }
  }
}

struct AddPlanSheet: View {
  let day: Date
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var detail = ""
  @State private var time: Date

  init(day: Date) {
    self.day = day
    _time = State(initialValue: TripTimeline.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        MTALabel(TripTimeline.dayTitle(day))
        TextField("What? e.g. teamLab Planets", text: $title).mta(.body1).padding(14)
          .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 2) }
        TextField("Note (optional)", text: $detail).mta(.body2).padding(14)
          .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.subtle, lineWidth: 1) }
        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).mta(.body1).tint(MTA.accent)
        Spacer()
        Button("Save plan") {
          context.insert(TripPlan(start: time, title: title, detail: detail))
          try? context.save()
          dismiss()
        }
        .buttonStyle(.mtaPrimary)
        .disabled(title.nilIfEmpty == nil)
      }
      .mtaScreen().padding(.top, 8).padding(.bottom, 16)
      .background(MTA.surface)
      .navigationTitle("New plan")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
    }
  }
}
