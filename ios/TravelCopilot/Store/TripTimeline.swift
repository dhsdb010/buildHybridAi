import Foundation

/// A dated moment in the trip, built only from stored Vault fields and the traveler's own plans.
struct TripEvent: Identifiable, Hashable {
  enum Kind: Hashable { case depart, arrive, checkIn, checkOut, plan }
  let id: String
  let date: Date
  let kind: Kind
  let title: String
  let detail: String
  let itemID: PersistentIdentifierBox?
  let planSource: String?

  var symbol: String {
    switch kind {
    case .depart, .arrive: "airplane"
    case .checkIn, .checkOut: "bed.double.fill"
    case .plan: "mappin.and.ellipse"
    }
  }

  var label: String {
    switch kind {
    case .depart: "Depart"
    case .arrive: "Land"
    case .checkIn: "Check-in"
    case .checkOut: "Check-out"
    case .plan: "Plan"
    }
  }
}

/// Hashable wrapper so events can carry a reference back to their VaultItem.
struct PersistentIdentifierBox: Hashable {
  let title: String
}

enum TripTimeline {
  static var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.firstWeekday = 2 // Monday-first, like the MTA calendar reference
    return c
  }

  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
  }()

  /// "2026-12-03" + "15:00" → Date (device time zone; booking times are local to the trip).
  static func date(_ day: String?, _ time: String?, defaultTime: String = "12:00") -> Date? {
    guard let day else { return nil }
    return dayFormatter.date(from: "\(day) \(time ?? defaultTime)")
  }

  static func events(items: [VaultItem], plans: [TripPlan]) -> [TripEvent] {
    var out: [TripEvent] = []
    for item in items {
      let box = PersistentIdentifierBox(title: item.title)
      switch item.kind {
      case "flight", "train":
        let route = [item.origin, item.destination].compactMap { $0 }.joined(separator: " → ")
        if let d = date(item.startDate, item.departureTime) {
          out.append(.init(id: "\(item.title)-dep", date: d, kind: .depart, title: route.isEmpty ? item.title : route,
                           detail: [item.title, item.confirmationCode].compactMap { $0 }.joined(separator: " · "), itemID: box, planSource: nil))
        }
        if let d = date(item.endDate ?? item.startDate, item.arrivalTime) {
          out.append(.init(id: "\(item.title)-arr", date: d, kind: .arrive, title: "Land at \(item.destination ?? "destination")",
                           detail: item.title, itemID: box, planSource: nil))
        }
      case "hotel":
        if let d = date(item.startDate, item.checkInTime, defaultTime: "15:00") {
          out.append(.init(id: "\(item.title)-in", date: d, kind: .checkIn, title: "Check in · \(item.title)",
                           detail: item.confirmationCode.map { "Ref \($0)" } ?? "", itemID: box, planSource: nil))
        }
        if let d = date(item.endDate, item.checkOutTime, defaultTime: "11:00") {
          out.append(.init(id: "\(item.title)-out", date: d, kind: .checkOut, title: "Check out · \(item.title)",
                           detail: item.confirmationCode.map { "Ref \($0)" } ?? "", itemID: box, planSource: nil))
        }
      default: break
      }
    }
    for p in plans {
      out.append(.init(id: "plan-\(p.createdAt.timeIntervalSince1970)", date: p.start, kind: .plan, title: p.title,
                       detail: p.detail, itemID: nil, planSource: p.source))
    }
    return out.sorted { $0.date < $1.date }
  }

  /// First to last day touched by a booking.
  static func range(_ events: [TripEvent]) -> ClosedRange<Date>? {
    let booked = events.filter { $0.kind != .plan }
    guard let first = booked.first?.date, let last = booked.last?.date else { return nil }
    return calendar.startOfDay(for: first)...calendar.startOfDay(for: last)
  }

  static func days(in range: ClosedRange<Date>) -> [Date] {
    var days: [Date] = []
    var d = range.lowerBound
    while d <= range.upperBound { days.append(d); d = calendar.date(byAdding: .day, value: 1, to: d)! }
    return days
  }

  static func events(on day: Date, _ events: [TripEvent]) -> [TripEvent] {
    events.filter { calendar.isDate($0.date, inSameDayAs: day) }
  }

  private static let hhmm: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
  }()
  /// Always 24-hour "15:00" (DESIGN.md: times are 24h with tabular figures).
  static func time(_ d: Date) -> String { hhmm.string(from: d) }
  static func dayTitle(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}
