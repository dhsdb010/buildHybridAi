import Foundation

/// A card in Home's Up next deck: the next things to do, from the trip timeline and the clock.
struct UpNextCard: Identifiable, Equatable {
  enum Action: Equatable { case taxi, planDay(Date), spend, none }
  let id: String
  let label: String
  let title: String
  let detail: String
  let symbol: String
  let action: Action
}

/// Builds the Up next deck (Figma: 08 · Home · Next steps). The first card is always the next thing
/// to do; steps you finished (Done on the journey Live Activity) and moments already past drop off.
enum UpNext {
  /// A moment stays on the deck this long after its time (you may still be on your way).
  static let grace: TimeInterval = 30 * 60
  static let maxCards = 4

  static func cards(_ events: [TripEvent], now: Date, done: Set<String>, language: String?) -> [UpNextCard] {
    let cal = TripTimeline.calendar
    let ahead = events.filter { $0.date > now.addingTimeInterval(-grace) && !done.contains($0.id) }.prefix(maxCards)
    return ahead.enumerated().map { i, e in
      let time = TripTimeline.time(e.clock)
      let when = cal.isDate(e.date, inSameDayAs: now) ? (i == 0 ? "Next" : "Then")
        : cal.isDate(e.date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: now)!) ? "Tomorrow"
        : e.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
      switch e.kind {
      case .depart:
        let from = Journey.ends(e.title).from ?? "the airport"
        return UpNextCard(id: e.id, label: "\(when) · \(e.vehicle == "train" ? "train" : "flight") \(time)",
                          title: e.vehicle == "train" ? "Train from \(from)" : "Leave for \(from)",
                          detail: e.vehicle == "train" ? e.detail : "\(e.detail) · be there 2 h before",
                          symbol: e.vehicle == "train" ? "tram" : "airplane.departure", action: .none)
      case .arrive:
        return UpNextCard(id: e.id, label: "\(when) · land \(time)", title: e.title,
                          detail: "Then your way to the hotel, step by step", symbol: "airplane.arrival", action: .none)
      case .checkIn:
        return UpNextCard(id: e.id, label: "\(when) · check-in \(time)", title: "Taxi card",
                          detail: "Hotel address in \(language ?? "the local language") · works offline",
                          symbol: "car", action: .taxi)
      case .checkOut:
        return UpNextCard(id: e.id, label: "\(when) · check-out \(time)", title: "Check out",
                          detail: "\(hotel(e.title)) · taxi card ready", symbol: "car", action: .taxi)
      case .plan:
        return UpNextCard(id: e.id, label: "\(when) · \(time)", title: e.title,
                          detail: e.detail.isEmpty ? "Saved offline" : e.detail, symbol: symbol(plan: e.title + " " + e.detail),
                          action: .planDay(cal.startOfDay(for: e.date)))
      }
    }
  }

  /// "Check out · Hotel X" → "Hotel X".
  static func hotel(_ title: String) -> String { title.components(separatedBy: " · ").last ?? title }

  /// A symbol for a day-plan stop from its words.
  static func symbol(plan text: String) -> String {
    let t = text.lowercased()
    if ["dinner", "lunch", "breakfast", "ramen", "sushi", "food", "eat", "café", "cafe", "market"].contains(where: t.contains) { return "fork.knife" }
    if ["ferry", "boat", "cruise"].contains(where: t.contains) { return "ferry" }
    if ["bus"].contains(where: t.contains) { return "bus" }
    if ["subway", "metro"].contains(where: t.contains) { return "tram.fill.tunnel" }
    if ["train", "line", "station"].contains(where: t.contains) { return "tram" }
    if ["bike", "cycling"].contains(where: t.contains) { return "bicycle" }
    if ["walk"].contains(where: t.contains) { return "figure.walk" }
    if ["museum", "temple", "shrine", "gallery", "park", "-ji", "jingu"].contains(where: t.contains) { return "building.columns" }
    if ["shop", "shopping", "market", "quijote"].contains(where: t.contains) { return "bag" }
    return "mappin.and.ellipse"
  }
}
