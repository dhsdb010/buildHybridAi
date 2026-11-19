import ActivityKit
import Foundation
import UserNotifications

/// Keeps the trip "taken care of": a notification before each moment, and the next moment
/// as a Live Activity on the Lock Screen / Dynamic Island. Everything is local (works offline);
/// the countdown uses the system timer, so it keeps running with the app closed.
@MainActor
enum TripReminders {
  /// Notification this long before a plan / check-in / check-out; flights get a leave-for-airport alert.
  static let lead: TimeInterval = 30 * 60
  static let airportLead: TimeInterval = 3 * 3600
  /// A Live Activity covers one moment and starts up to 8 hours before it (DESIGN.md rule 5).
  static let window: TimeInterval = 8 * 3600
  /// Debug only (`-liveDemoStep far`): show a journey that's days away, to check the date display.
  static var ignoreWindow = false

  /// Last input, so Done (from the Live Activity or a notification) can move the journey on.
  private static var last: (events: [TripEvent], place: String, enabled: Bool)?

  static func sync(events: [TripEvent], place: String, enabled: Bool, now: Date = AppClock.now) async {
    last = (events, place, enabled)
    // Live Activity first: the notification permission prompt waits for the user.
    await updateActivity(events, place: place, enabled: enabled, now: now)
    await scheduleNotifications(events, enabled: enabled, now: now)
  }

  /// A step was marked done: remember it and show the next step.
  static func markDone(_ id: String) async {
    JourneyDone.mark(id)
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["trip-\(id)"])
    guard let last else { return }
    await updateActivity(last.events, place: last.place, enabled: last.enabled, now: AppClock.now)
  }

  // MARK: Notifications

  private static func scheduleNotifications(_ events: [TripEvent], enabled: Bool, now: Date) async {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("trip-") }
    center.removePendingNotificationRequests(withIdentifiers: pending)
    guard enabled else { return }
    guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }

    center.setNotificationCategories(categories)
    let journeyIDs = journeyMembers(events, now: now)
    let done = JourneyDone.ids
    for e in events where e.date > now && !done.contains(e.id) {
      let leadTime = e.kind == .depart && e.vehicle != "train" ? airportLead : lead
      let fire = e.date.addingTimeInterval(-leadTime)
      guard fire > now else { continue }
      let content = UNMutableNotificationContent()
      content.title = e.kind == .depart ? "Leave for the airport" : "\(e.label) in \(Int(leadTime / 60)) min"
      content.body = "\(title(e)) · \(e.detail)".trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "·")))
      content.sound = .default
      content.interruptionLevel = e.kind == .depart || e.kind == .checkOut ? .timeSensitive : .active
      if let (j, i, n) = journeyIDs[e.id] {
        // One step at a time: "Step 2 of 3 · Bus 61", with Show card · Done · Ask on long-press.
        let mode = JourneyMode.of(e)
        content.title = i < n ? "Step \(i + 1) of \(n) · \(title(e))" : title(e)
        content.body = [e.detail, "To \(j.stops.last ?? "goal")."].filter { !$0.isEmpty }.joined(separator: " · ")
        content.categoryIdentifier = "journey-\(mode.rawValue)"
        content.userInfo = ["stepID": e.id, "card": mode.card.link, "ask": "About \(title(e)): "]
      }
      let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
      let request = UNNotificationRequest(identifier: "trip-\(e.id)", content: content,
                                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
      try? await center.add(request)
    }
  }

  /// Long-press actions on a journey notification, one category per way of traveling.
  static var categories: Set<UNNotificationCategory> {
    let modes: [JourneyMode] = [.train, .bus, .walk, .cycle, .taxi, .ferry, .flight, .place, .hotel]
    return Set(modes.map { m in
      UNNotificationCategory(identifier: "journey-\(m.rawValue)", actions: [
        UNNotificationAction(identifier: "card", title: m == .hotel ? "Show booking" : "Show \(m.card.label.lowercased())",
                             options: .foreground, icon: .init(systemImageName: m.card.glyph)),
        UNNotificationAction(identifier: "done", title: m == .hotel ? "Done · I'm here" : "Done · I'm on it",
                             options: [], icon: .init(systemImageName: "checkmark")),
        UNNotificationAction(identifier: "ask", title: "Ask Travel Copilot", options: .foreground,
                             icon: .init(systemImageName: "asterisk")),
      ], intentIdentifiers: [])
    })
  }

  /// Event id → (journey, step index, step count) for every event that's part of an upcoming journey.
  private static func journeyMembers(_ events: [TripEvent], now: Date) -> [String: (Journey, Int, Int)] {
    var out: [String: (Journey, Int, Int)] = [:]
    // Look at each goal's journey as it will be just before its first step.
    for goal in events where Journey.isGoal(goal) && goal.date > now {
      let probe = max(now, goal.date.addingTimeInterval(-Journey.lookBack))
      guard let j = Journey.current(events.filter { $0.date <= goal.date }, now: probe, done: []), j.goal.id == goal.id else { continue }
      for (i, s) in j.all.enumerated() { out[s.event.id] = (j, i, j.steps.count) }
    }
    return out
  }

  // MARK: Live Activity

  /// The moment to show: one that's happening now, else the next one within 8 hours.
  static func current(_ events: [TripEvent], now: Date) -> (TripEvent, TripProgress)? {
    let nextID = events.first { $0.date > now }?.id
    for (i, e) in events.enumerated() {
      let end = events.indices.contains(i + 1) ? events[i + 1].date : nil
      let p = TripProgress.of(start: e.date, end: end, now: now, isNext: e.id == nextID)
      if p == .now { return (e, p) }
      if e.date > now { return e.date.timeIntervalSince(now) <= window ? (e, p == .later ? .next : p) : nil }
    }
    return nil
  }

  private static func updateActivity(_ events: [TripEvent], place: String, enabled: Bool, now: Date) async {
    #if DEBUG
      NSLog("Live Activity sync: %@", " enabled=\(enabled) allowed=\(ActivityAuthorizationInfo().areActivitiesEnabled) moment=\(current(events, now: now).map { $0.0.title } ?? "none")")
    #endif
    if enabled, ActivityAuthorizationInfo().areActivitiesEnabled,
       let j = Journey.current(events, now: now, done: JourneyDone.ids),
       ignoreWindow || j.steps[0].event.date.timeIntervalSince(now) <= window {
      let content = ActivityContent(state: journeyState(j, place: place, now: now, events: events),
                                    staleDate: j.goal.date.addingTimeInterval(Journey.arrivedFor),
                                    relevanceScore: 100)
      await apply(eventID: j.goal.id, content: content)
      return
    }
    guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let (e, progress) = current(events, now: now) else {
      await apply(eventID: nil, content: nil)
      return
    }
    let state = TripActivityAttributes.ContentState(
      title: title(e), label: label(e, place: place), detail: detail(e),
      glyph: glyph(e), progress: progress, start: e.date, since: min(now, e.date.addingTimeInterval(-window)),
      ref: ref(e), from: ends(e).from, to: ends(e).to, action: action(e))
    // Stale after the moment ends, so the system dims it if the app can't update it.
    let content = ActivityContent(state: state, staleDate: e.date.addingTimeInterval(3600),
                                  relevanceScore: progress == .soon || progress == .now ? 100 : 50)
    await apply(eventID: e.id, content: content)
  }

  /// ActivityKit work off the main actor: update the activity for this moment, or end the others and start it.
  /// `nil` ends every trip activity.
  nonisolated private static func apply(eventID: String?, content: ActivityContent<TripActivityAttributes.ContentState>?) async {
    // Only live ones: an ended or dismissed activity can't be updated.
    let live = Activity<TripActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    for a in live {
      if let eventID, let content, a.attributes.eventID == eventID { await a.update(content); return }
    }
    for a in live { await a.end(nil, dismissalPolicy: .immediate) }
    if let eventID, let content {
      do { _ = try Activity.request(attributes: TripActivityAttributes(eventID: eventID), content: content) }
      catch { NSLog("Live Activity request failed: %@", String(describing: error)) }
    }
  }

  /// The Live Activity for the step you're on (or the arrived card).
  static func journeyState(_ j: Journey, place: String, now: Date, events: [TripEvent] = []) -> TripActivityAttributes.ContentState {
    let goalRef = ref(j.goal)
    guard let i = j.current, let s = j.currentStep else {
      // Arrived: the booking details right on the Lock Screen.
      let checkOut = events.first { $0.kind == .checkOut && $0.itemID == j.goal.itemID }
      // Ref is already top-right; this line is the hotel and when you leave.
      let out = checkOut.map { "Out \($0.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \(TripTimeline.time($0.date))" } ?? ""
      return .init(title: j.goal.kind == .checkIn ? "You're checked in" : "At the airport", label: label(j.goal, place: place),
                   detail: detail(j.goal), glyph: JourneyMode.of(j.goal).glyph, progress: .done, start: j.goal.date, since: j.goal.date,
                   ref: goalRef, from: j.stops.first ?? "", to: j.stops.last ?? "", action: "Room info",
                   stops: j.stops, segment: j.stops.count - 1, along: 1, step: j.steps.count + 1, steps: j.steps.count + 1,
                   arrived: true, info: out.isEmpty ? detail(j.goal) : "\(detail(j.goal)) · \(out)",
                   cardLabel: j.goal.kind == .checkIn ? "Room info" : "Boarding info",
                   cardGlyph: j.goal.kind == .checkIn ? "key.fill" : "airplane", cardLink: "travelcopilot://trip",
                   goalGlyph: JourneyMode.of(j.goal).glyph, stepID: j.goal.id)
    }
    let n = j.steps.count
    let arriving = i == n
    let seg = min(i, n - 1)
    let next = arriving || i + 1 == n ? j.goal.date : j.steps[i + 1].event.date
    let begin = i == 0 ? min(now, s.event.date) : j.steps[i - 1].event.date
    let progress = TripProgress.of(start: s.event.date, end: next, now: now, isNext: true)
    // The vehicle sits on this step's segment and moves along as its time comes and goes.
    let span = max(next.timeIntervalSince(begin), 60)
    let along = arriving ? 0.92 : min(max(now.timeIntervalSince(begin) / span, 0.06), 0.9)
    let card = arriving ? JourneyMode.hotel.card : s.mode.card
    let goalWord = j.goal.kind == .checkIn ? "Check-in" : "Depart"
    return .init(title: arriving ? goalWord : stepTitle(s),
                 label: arriving ? "To \(j.stops.last ?? "goal") · Arriving" : "To \(j.stops.last ?? "goal") · Step \(i + 1) of \(n)",
                 detail: arriving ? detail(j.goal) : stepDetail(s, from: j.stops[seg], to: j.stops[seg + 1]),
                 glyph: arriving ? j.steps[n - 1].mode.glyph : s.mode.glyph, progress: progress == .later ? .next : progress,
                 start: s.event.date, since: begin, ref: goalRef, from: j.stops[seg], to: j.stops[seg + 1], action: card.label,
                 stops: j.stops, segment: seg, along: along, step: min(i + 1, n), steps: n,
                 cardLabel: card.label, cardGlyph: card.glyph, cardLink: card.link,
                 goalGlyph: JourneyMode.of(j.goal).glyph, stepID: s.event.id)
  }

  /// One line under the step title, without repeating it ("Platform 1 · Car 8", or "Narita → Shinjuku").
  static func stepDetail(_ s: Journey.Step, from: String, to: String) -> String {
    let title = stepTitle(s)
    let parts = s.event.detail.components(separatedBy: " · ").filter { !$0.isEmpty && $0 != title }
    return parts.isEmpty ? "\(from) → \(to)" : parts.joined(separator: " · ")
  }

  /// "Narita → Shinjuku" for a train reads better as the train's name.
  static func stepTitle(_ s: Journey.Step) -> String {
    if s.event.kind == .depart, let name = s.event.detail.components(separatedBy: " · ").first, !name.isEmpty { return name }
    // "Bus 61 → Nishi-Shinjuku" → "Bus 61"
    return Journey.ends(s.event.title).from ?? s.event.title
  }

  // MARK: Station-sign copy (noun + time)

  static func title(_ e: TripEvent) -> String {
    let time = TripTimeline.time(e.date)
    switch e.kind {
    case .depart: return "Depart \(time)"
    case .arrive: return "Land \(time)"
    case .checkIn: return "Check-in \(time)"
    case .checkOut: return "Check-out \(time)"
    case .plan: return "\(e.title) \(time)"
    }
  }

  static func label(_ e: TripEvent, place: String) -> String {
    switch e.kind {
    case .depart, .arrive: "Flight · \(e.title)"
    case .checkIn, .checkOut: "Hotel · \(place)"
    case .plan: "Plan · \(place)"
    }
  }

  /// One line under the title, without the ref (that sits top-right).
  static func detail(_ e: TripEvent) -> String {
    switch e.kind {
    case .checkIn, .checkOut: e.title.components(separatedBy: " · ").last ?? e.title
    case .depart, .arrive: e.detail.components(separatedBy: " · ").first ?? e.title
    case .plan: e.detail.isEmpty ? "Your plan" : e.detail
    }
  }

  static func ref(_ e: TripEvent) -> String {
    guard e.kind != .plan, let last = e.detail.components(separatedBy: " · ").last else { return "" }
    return last.replacingOccurrences(of: "Ref ", with: "")
  }

  static func ends(_ e: TripEvent) -> (from: String, to: String) {
    let parts = e.title.components(separatedBy: " → ")
    if e.kind == .depart, parts.count == 2 { return (parts[0], parts[1]) }
    return ("Now", TripTimeline.time(e.date))
  }

  static func action(_ e: TripEvent) -> String {
    switch e.kind {
    case .depart, .arrive: "Open flight"
    case .checkIn: "Show taxi card"
    case .checkOut: "Show booking"
    case .plan: "Open today's plan"
    }
  }

  static func glyph(_ e: TripEvent) -> String {
    switch e.kind {
    case .depart, .arrive: "airplane"
    case .checkIn, .checkOut: "bed.double.fill"
    case .plan: "mappin"
    }
  }
}
