import Foundation

/// How a step is traveled. Read from the booking kind or the words in the traveler's own plan.
enum JourneyMode: String, Hashable, Sendable {
  case train, bus, walk, cycle, taxi, ferry, flight, place, hotel

  /// SF Symbol for the vehicle that rides the track.
  var glyph: String {
    switch self {
    case .train: "tram.fill"
    case .bus: "bus.fill"
    case .walk: "figure.walk"
    case .cycle: "figure.outdoor.cycle"
    case .taxi: "car.fill"
    case .ferry: "ferry.fill"
    case .flight: "airplane"
    case .place: "mappin"
    case .hotel: "bed.double.fill"
    }
  }

  /// Bottom-left button: the one thing you need to show for this step.
  var card: (label: String, glyph: String, link: String) {
    switch self {
    case .train: ("Train ticket", "tram.card.fill", "travelcopilot://trip")
    case .bus: ("Bus card", "tram.card.fill", "travelcopilot://trip")
    case .ferry: ("Ferry ticket", "ticket.fill", "travelcopilot://trip")
    case .taxi: ("Taxi card", "car.fill", "travelcopilot://taxi")
    case .flight: ("Boarding info", "airplane", "travelcopilot://trip")
    case .walk, .cycle, .place: ("Open map", "map.fill", "travelcopilot://map")
    case .hotel: ("Show booking", "doc.text.fill", "travelcopilot://trip")
    }
  }

  static func of(_ e: TripEvent) -> JourneyMode {
    switch e.kind {
    case .depart, .arrive: return e.vehicle == "train" ? .train : .flight
    case .checkIn, .checkOut: return .hotel
    case .plan:
      let t = "\(e.title) \(e.detail)".lowercased()
      let words: [(JourneyMode, [String])] = [
        (.bus, ["bus"]), (.train, ["train", "metro", "subway", "line", "express", "shinkansen", "tram", "jr "]),
        (.taxi, ["taxi", "uber", "cab"]), (.cycle, ["bike", "cycle", "bicycle"]), (.ferry, ["ferry", "boat"]),
        (.walk, ["walk", "on foot"]),
      ]
      return words.first { $0.1.contains { t.contains($0) } }?.0 ?? .place
    }
  }
}

/// A trip to one goal (check-in, or a flight), split into the steps that lead there.
/// Built only from bookings and the traveler's own plans (no AI text).
struct Journey: Hashable {
  struct Step: Hashable {
    let event: TripEvent
    let mode: JourneyMode
    /// Where this step ends ("Shinjuku"), shown under its stop on the track.
    let to: String
  }

  let goal: TripEvent
  let steps: [Step]
  /// Start point plus each step's end; the last step always ends at the goal ("Hotel").
  /// So there's one track segment per step.
  let stops: [String]
  /// Index of the step you're on; `steps.count` = all steps done, arriving at the goal; nil once arrived.
  let current: Int?

  /// Steps lead up to a goal within this window.
  static let lookBack: TimeInterval = 6 * 3600
  /// The arrived card (room info) stays this long after the goal time.
  static let arrivedFor: TimeInterval = 2 * 3600
  /// A goal counts as reached this long after its time, even without a tap on Done.
  static let assumeArrived: TimeInterval = 30 * 60

  var all: [Step] { steps + [Step(event: goal, mode: JourneyMode.of(goal), to: stops.last ?? "")] }
  var currentStep: Step? { current.map { all[$0] } }

  static func isGoal(_ e: TripEvent) -> Bool { e.kind == .checkIn || (e.kind == .depart && e.vehicle != "train") }

  /// The journey to show now: the first goal ahead (or just reached) that has steps leading to it.
  static func current(_ events: [TripEvent], now: Date, done: Set<String>) -> Journey? {
    for (gi, goal) in events.enumerated() where isGoal(goal) {
      let reached = done.contains(goal.id) || now >= goal.date.addingTimeInterval(assumeArrived)
      if now >= goal.date.addingTimeInterval(arrivedFor) { continue }
      // Everything since the last goal, within the window; a landing is where the journey starts.
      let before = events[..<gi].filter { $0.date > goal.date.addingTimeInterval(-lookBack) }
      let lastGoal = before.lastIndex { isGoal($0) || $0.kind == .checkOut }
      var window = Array(before[(lastGoal.map { $0 + 1 } ?? before.startIndex)...])
      var start: String?
      if let land = window.lastIndex(where: { $0.kind == .arrive }) {
        start = place(window[land].title.replacingOccurrences(of: "Land at ", with: ""))
        window = Array(window[(land + 1)...])
      }
      let steps = window.map { Step(event: $0, mode: JourneyMode.of($0), to: to($0)) }
      guard !steps.isEmpty, steps.count <= 5 else { continue }
      let goalStop = goal.kind == .checkIn ? "Hotel" : place(ends(goal.title).from ?? "Airport")
      let first = start ?? ends(window[0].title).from.map(place) ?? "Now"
      let stops = [first] + steps.dropLast().map(\.to) + [goalStop]

      var cur: Int? = nil
      if !reached {
        cur = steps.count
        for (i, s) in steps.enumerated() {
          let next = i + 1 < steps.count ? steps[i + 1].event.date : goal.date
          if !done.contains(s.event.id) && now < next { cur = i; break }
        }
      }
      return Journey(goal: goal, steps: steps, stops: stops, current: cur)
    }
    return nil
  }

  /// "Narita → Shinjuku" → (Narita, Shinjuku).
  static func ends(_ title: String) -> (from: String?, to: String?) {
    let parts = title.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }
    return parts.count == 2 ? (parts[0], parts[1]) : (nil, nil)
  }

  static func to(_ e: TripEvent) -> String {
    if let t = ends(e.title).to { return place(t) }
    return place(e.title)
  }

  /// Short stop name for under the track ("Hotel Hoshizora Shinjuku" stays readable, cut at 14).
  static func place(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespaces)
    return t.count > 14 ? String(t.prefix(13)) + "…" : t
  }
}

/// Steps the traveler marked done (from the Live Activity, a notification, or the app).
enum JourneyDone {
  private static let key = "journeyDone"
  static var ids: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
  static func mark(_ id: String) {
    var s = ids; s.insert(id)
    UserDefaults.standard.set(Array(s.suffix(200)), forKey: key)
  }
}
