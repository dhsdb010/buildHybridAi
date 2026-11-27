import SwiftUI

/// The room's shared plan, in the same layout as Plan a day (Figma 09 · Day plan and Stop detail):
/// the day's stops on a map with numbered pins, timed rows with the walk between them and a
/// rough cost. Tap a stop for the stop detail (photo, time, cost, note); press and hold to move
/// it to another day. Every change shows in the chat.
struct SharedPlanView: View {
  let roomID: String
  /// Goes back to the room with "@Blue …" ready in the message box.
  var onAskBlue: (String) -> Void

  @Environment(SocialService.self) private var social
  @State private var stops: [SharedStop] = []
  @State private var stopListening: (() -> Void)?
  @State private var day: Date?
  @State private var editing: Pair?
  @State private var adding = false

  /// A shared stop shown as a Plan a day stop (the detail screen edits the `DayStop`).
  struct Pair: Identifiable { let shared: SharedStop; let stop: DayStop; var id: UUID { stop.id } }

  private var room: TripRoom? { social.rooms.first { $0.id == roomID } }
  private var days: [Date] { SharedPlan.days(stops) }
  private var selected: Date? { day.flatMap { d in days.first { TripTimeline.calendar.isDate($0, inSameDayAs: d) } } ?? days.first }
  private var pairs: [Pair] {
    guard let selected else { return [] }
    return SharedPlan.stops(on: selected, stops).map { s in Pair(shared: s, stop: s.dayStop(id: Self.uuid(s.id))) }
  }
  /// The city for Add a stop: "Tokyo · Dec 2–4" → "Tokyo", "Tokyo trip" → "Tokyo".
  private var city: String {
    let t = room?.tripTitle?.components(separatedBy: " · ").first ?? room?.name ?? ""
    return t.replacingOccurrences(of: " trip", with: "")
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        DayMap(stops: pairs.map(\.stop).filter { $0.latitude != 0 || $0.longitude != 0 })
          .frame(height: 230).id(pairs.map(\.shared.id))
        if let room { content(room) }
      }
      .padding(.bottom, 24)
    }
    .scrollIndicators(.hidden)
    .background(MTA.surface)
    .navigationTitle(selected.map { "\(city) · Day \((days.firstIndex(of: $0) ?? 0) + 1)" } ?? "Shared plan")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .sheet(item: $editing) { p in
      if let room {
        StopDetailView(stop: p.stop,
                       onSave: { edited in Task { await save(p.shared.applying(edited), was: p.shared, in: room) } },
                       onRemove: { Task { await social.removeStop(p.shared, in: room) } })
      }
    }
    .sheet(isPresented: $adding) {
      if let room, let selected {
        AddStopSheet(day: selected, city: city, near: pairs.first { $0.shared.hasCoordinate }?.stop.coordinate) { new in
          let s = SharedStop(id: "", date: new.time, title: new.name, detail: new.why, kind: new.kind,
                             latitude: new.latitude, longitude: new.longitude, addedBy: "", addedByName: "",
                             cost: new.cost, note: new.note, address: new.address)
          Task { await social.saveStop(s, in: room, note: "\(social.me?.name ?? "Someone") added \(new.name) on \(new.time.formatted(.dateTime.month(.abbreviated).day()))") }
        }
        .presentationDetents([.large])
      }
    }
    .onAppear {
      guard stopListening == nil, let room else { return }
      stopListening = social.plan(room) { stops = $0 }
    }
    .onDisappear { stopListening?(); stopListening = nil }
  }

  @ViewBuilder
  private func content(_ room: TripRoom) -> some View {
    let editable = social.canEditPlan(room)
    VStack(alignment: .leading, spacing: 12) {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(Array(days.enumerated()), id: \.element) { i, d in
            QuickChip(text: "Day \(i + 1)", selected: d == selected) { day = d }
          }
        }
      }
      .scrollIndicators(.hidden)
      if let selected {
        HStack {
          MTALabel(TripTimeline.dayTitle(selected))
          Spacer()
          let total = pairs.map(\.stop.cost).reduce(0, +)
          if total > 0 { Text("~$\(total) est.").mta(.button2).foregroundStyle(MTA.accent) }
        }
        ForEach(Array(pairs.enumerated()), id: \.element.id) { i, p in
          VStack(alignment: .leading, spacing: 4) {
            Button { if editable { editing = p } } label: { StopRow(number: i + 1, stop: p.stop) }
              .buttonStyle(.plain)
              .contextMenu { if editable { moveMenu(p.shared, room: room) } }
            if let by = byLine(p.shared, room: room) {
              Text(by).mta(.label).foregroundStyle(MTA.accent).padding(.leading, 40)
            }
          }
          if i + 1 < pairs.count, p.shared.hasCoordinate, pairs[i + 1].shared.hasCoordinate {
            Text("⋮  " + DayStops.leg(p.stop, pairs[i + 1].stop)).mta(.body2).foregroundStyle(MTA.text2).padding(.leading, 9)
          }
        }
        if editable { Button("Add a stop") { adding = true }.buttonStyle(.mtaSecondary).padding(.top, 4) }
        Button { onAskBlue("@Blue can you improve \(selected.formatted(.dateTime.month(.abbreviated).day()))? ") } label: {
          HStack(spacing: 10) {
            BlueBadge(size: 26)
            Text("Ask Blue to change Day \((days.firstIndex(of: selected) ?? 0) + 1)")
              .font(.system(size: 15, weight: .semibold)).foregroundStyle(MTA.accent)
            Spacer()
          }
          .padding(.horizontal, 14).frame(minHeight: 50)
          .background(MTA.raised, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
      } else {
        Text("No stops yet.").mta(.body1).foregroundStyle(MTA.text2)
      }
      Text(editable
           ? "Tap a stop to change its time, cost or note. Press and hold to move it to another day. Changes show in the chat."
           : "You can view this plan. Suggest changes in the chat.")
        .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, MTA.margin)
  }

  @ViewBuilder
  private func moveMenu(_ s: SharedStop, room: TripRoom) -> some View {
    Menu("Move to", systemImage: "calendar") {
      ForEach(Array(days.enumerated()), id: \.element) { i, d in
        if !TripTimeline.calendar.isDate(d, inSameDayAs: s.date) {
          Button("Day \(i + 1) · \(d.formatted(.dateTime.month(.abbreviated).day()))") { Task { await move(s, to: d, in: room) } }
        }
      }
    }
    Button("Remove", systemImage: "trash", role: .destructive) { Task { await social.removeStop(s, in: room) } }
  }

  private func move(_ s: SharedStop, to day: Date, in room: TripRoom) async {
    let cal = TripTimeline.calendar
    let hm = cal.dateComponents([.hour, .minute], from: s.date)
    var moved = s
    moved.date = cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: day) ?? day
    await social.saveStop(moved, in: room, note: "\(social.me?.name ?? "Someone") moved \(s.title) to \(day.formatted(.dateTime.month(.abbreviated).day()))")
  }

  private func save(_ s: SharedStop, was old: SharedStop, in room: TripRoom) async {
    guard s != old else { return }
    let name = social.me?.name ?? "Someone"
    let note = TripTimeline.calendar.isDate(s.date, equalTo: old.date, toGranularity: .minute) || s.title != old.title
      ? "\(name) changed \(s.title)" : "\(name) moved \(s.title) to \(TripTimeline.time(s.date))"
    await social.saveStop(s, in: room, note: note)
  }

  private func byLine(_ s: SharedStop, room: TripRoom) -> String? {
    if let e = s.editedByName { return "\(e) changed" }
    if s.addedBy != room.owner, !s.addedByName.isEmpty { return "\(s.addedByName) added" }
    return nil
  }

  /// A stable UUID for a stop id, so rows and the map keep their identity between updates.
  static func uuid(_ id: String) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    for (i, b) in id.utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &* 31 &+ b }
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }
}
