import Foundation
import HealthKit

/// After the trip: what you did, day by day, built only from what's saved on this iPhone
/// (bookings, day plans, receipts). Nothing is tracked. Figma: 09 · After the trip.
struct TripSummary {
  struct Stop: Identifiable, Equatable {
    let id: String
    let date: Date
    let title: String
    let detail: String
    let symbol: String
    var latitude: Double?
    var longitude: Double?
    /// Counts toward "Places" (a plan stop, the hotel, or a shop or sight you paid at).
    var isPlace = false
    var hasCoordinate: Bool { latitude != nil && longitude != nil }
  }

  struct Day: Identifiable, Equatable {
    let day: Date
    var stops: [Stop]
    var id: Date { day }
  }

  let range: ClosedRange<Date>
  let days: [Day]

  var dayCount: Int { TripTimeline.days(in: range).count }
  /// Stops with a place on the map, in time order (the route).
  var route: [Stop] { days.flatMap(\.stops).filter(\.hasCoordinate) }
  func route(on day: Date?) -> [Stop] {
    guard let day else { return route }
    return route.filter { TripTimeline.calendar.isDate($0.date, inSameDayAs: day) }
  }
  var places: Int { Set(days.flatMap(\.stops).filter(\.isPlace).map { $0.title.lowercased() }).count }

  /// "Dec 2 – Dec 7 · 6 days"
  var dates: String {
    let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
    return "\(range.lowerBound.formatted(f)) – \(range.upperBound.formatted(f)) · \(dayCount) days"
  }

  struct Plan { let start: Date; let title: String; let detail: String; let kind: String?; let latitude: Double?; let longitude: Double? }
  struct Spot { let name: String; let kind: String; let latitude: Double; let longitude: Double }
  struct Spent { let date: Date; let merchant: String; let amount: Double; let currency: String; let category: ExpenseCategory }

  /// Bookings and plans (as `TripEvent`s), with coordinates from the plans and saved places, and
  /// receipts. A receipt at a planned stop is shown on that stop ("Senso-ji · ¥1,000").
  static func build(events: [TripEvent], plans: [Plan], places: [Spot], expenses: [Spent]) -> TripSummary? {
    guard let range = TripTimeline.range(events) else { return nil }
    let cal = TripTimeline.calendar
    var used = Set<Int>()
    func spent(matching title: String, on date: Date) -> Spent? {
      let t = title.lowercased()
      guard let i = expenses.indices.first(where: { i in
        !used.contains(i) && cal.isDate(expenses[i].date, inSameDayAs: date)
          && (t.contains(expenses[i].merchant.lowercased()) || expenses[i].merchant.lowercased().contains(t))
      }) else { return nil }
      used.insert(i)
      return expenses[i]
    }
    let hotel = places.first { $0.kind == "hotel" }

    var stops: [Stop] = []
    for e in events {
      switch e.kind {
      case .depart:
        stops.append(Stop(id: e.id, date: e.date, title: e.title,
                          detail: [flightNumber(e.detail), TripTimeline.time(e.clock)].compactMap { $0 }.joined(separator: " · "),
                          symbol: e.vehicle == "train" ? "tram" : "airplane.departure"))
      case .arrive:
        let title = e.title.hasPrefix("Land at ") ? "Landed at " + e.title.dropFirst(8) : e.title
        stops.append(Stop(id: e.id, date: e.date, title: title, detail: TripTimeline.time(e.clock),
                          symbol: e.vehicle == "train" ? "tram" : "airplane.arrival"))
      case .checkIn:
        stops.append(Stop(id: e.id, date: e.date, title: e.title.replacingOccurrences(of: "Check in", with: "Checked in"),
                          detail: TripTimeline.time(e.clock), symbol: "bed.double",
                          latitude: hotel?.latitude, longitude: hotel?.longitude, isPlace: true))
      case .checkOut:
        stops.append(Stop(id: e.id, date: e.date, title: "Checked out", detail: TripTimeline.time(e.clock), symbol: "bed.double"))
      case .plan:
        let p = plans.first { $0.title == e.title && $0.start == e.date }
        let paid = spent(matching: e.title, on: e.date)
        let words = [p?.kind ?? (e.detail.isEmpty ? nil : e.detail), paid.map { Spend.money($0.amount, $0.currency) }].compactMap { $0 }
        stops.append(Stop(id: e.id, date: e.date, title: e.title, detail: words.joined(separator: " · "),
                          symbol: paid?.category.symbol ?? UpNext.symbol(plan: e.title + " " + e.detail + " " + (p?.kind ?? "")),
                          latitude: p?.latitude, longitude: p?.longitude, isPlace: true))
      }
    }
    for (i, x) in expenses.enumerated() where !used.contains(i) {
      stops.append(Stop(id: "spent-\(i)-\(x.date.timeIntervalSince1970)", date: x.date, title: x.merchant,
                        detail: "\(x.category.title) · \(Spend.money(x.amount, x.currency))", symbol: x.category.symbol,
                        isPlace: x.category != .transport && x.category != .other))
    }
    let grouped = Dictionary(grouping: stops) { cal.startOfDay(for: $0.date) }
    // You check in after you land (and after the ride from the airport), even when the hotel's
    // check-in opens earlier.
    func key(_ s: Stop) -> Date {
      guard s.title.hasPrefix("Checked in"),
            let land = stops.first(where: { $0.title.hasPrefix("Landed") && cal.isDate($0.date, inSameDayAs: s.date) }),
            land.date > s.date else { return s.date }
      let ride = stops.filter { $0.symbol == ExpenseCategory.transport.symbol && $0.date > land.date
        && $0.date < land.date.addingTimeInterval(3 * 3600) }.map(\.date).max()
      return (ride ?? land.date).addingTimeInterval(1)
    }
    let days = grouped.keys.sorted().map { d in
      Day(day: d, stops: grouped[d]!.sorted { key($0) < key($1) }.map { s in
        // Moved after landing: the hotel's time is when check-in opened.
        key(s) == s.date ? s : Stop(id: s.id, date: s.date, title: s.title, detail: "from \(s.detail)", symbol: s.symbol,
                                    latitude: s.latitude, longitude: s.longitude, isPlace: s.isPlace)
      })
    }
    return TripSummary(range: range, days: days)
  }

  /// "Tokyo Haneda" → "Tokyo"; an airport code ("HND") → its city from the time zone ("Asia/Tokyo").
  static func city(destination: String?) -> String? {
    guard let d = destination?.trimmingCharacters(in: .whitespaces), !d.isEmpty else { return nil }
    if let zone = TripTimeZones.airport(d), let last = zone.split(separator: "/").last {
      return last.replacingOccurrences(of: "_", with: " ")
    }
    guard let first = d.split(separator: " ").first.map(String.init), d.contains(" ") else { return nil }
    return first
  }

  /// "EA 061 San Francisco to Tokyo" → "EA 061".
  static func flightNumber(_ text: String) -> String? {
    guard let r = text.range(of: #"^[A-Z0-9]{2} ?\d{1,4}\b"#, options: .regularExpression) else { return nil }
    return String(text[r])
  }

  /// Plain text for Share summary.
  func shareText(place: String, steps: Int?) -> String {
    var lines = ["\(place), done. \(dates)", "\(places) places"]
    for d in days {
      lines.append("")
      lines.append(d.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
      lines += d.stops.map { "· \($0.title)" }
    }
    if let steps { lines += ["", "\(steps.formatted()) steps · \(Steps.kmText(steps))"] }
    lines += ["", "Made with Travel Copilot"]
    return lines.joined(separator: "\n")
  }
}

/// The step-count easter egg: steps walked during the trip, read from Health on this iPhone, only
/// after the traveler taps to allow it. Read only; the count is saved for this trip on the phone.
@MainActor
enum Steps {
  nonisolated static let metersPerStep = 0.72
  nonisolated static let fuji = 3.776 // km

  nonisolated static func km(_ steps: Int) -> Double { Double(steps) * metersPerStep / 1000 }
  nonisolated static func kmText(_ steps: Int) -> String { "about \(Int(km(steps).rounded())) km on foot" }
  /// How many times you climbed Mt. Fuji's height, walking the same distance.
  nonisolated static func fujis(_ steps: Int) -> Int { Int((km(steps) / fuji).rounded()) }

  private static func key(_ range: ClosedRange<Date>) -> String { "tripSteps-\(Int(range.lowerBound.timeIntervalSince1970))" }

  /// The saved count for this trip (nil until the traveler asks).
  static func saved(_ range: ClosedRange<Date>) -> Int? {
    #if DEBUG
      // `-sampleSteps 84210`: the simulator has no steps in Health.
      if let n = UserDefaults.standard.object(forKey: "sampleSteps") as? Int { return n }
      if let s = UserDefaults.standard.string(forKey: "sampleSteps"), let n = Int(s) { return n }
    #endif
    return UserDefaults.standard.object(forKey: key(range)) as? Int
  }

  /// Asks Health (once, by the traveler's tap) and adds up the steps from the first to the last day.
  static func count(_ range: ClosedRange<Date>) async -> Int? {
    if let n = saved(range) { return n }
    guard HKHealthStore.isHealthDataAvailable(), let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
    let store = HKHealthStore()
    do { try await store.requestAuthorization(toShare: [], read: [type]) } catch { return nil }
    let end = TripTimeline.calendar.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
    let predicate = HKQuery.predicateForSamples(withStart: range.lowerBound, end: end)
    let query = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum)
    guard let sum = try? await query.result(for: store)?.sumQuantity()?.doubleValue(for: .count()) else { return nil }
    let n = Int(sum)
    // iOS hides a "no" as zero steps; don't save it so the traveler can try again.
    if n > 0 { UserDefaults.standard.set(n, forKey: key(range)) }
    return n > 0 ? n : nil
  }
}

/// The traveler's name for Home ("Welcome back, Alex"): the profile name, else the account's first name.
enum Profile {
  static var name: String? {
    if let n = UserDefaults.standard.string(forKey: "profileName"), !n.isEmpty { return n }
    return nil
  }
  static func firstName(account: String?) -> String? {
    if let name { return name }
    guard let a = account?.split(separator: " ").first, !a.isEmpty else { return nil }
    return String(a)
  }
}
