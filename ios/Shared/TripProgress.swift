import Foundation

/// Where a trip moment stands right now. Color always means status (DESIGN.md):
/// done = gray ✓ · now = New Blue · next = green (on track) · soon = red (under 30 min) · later = plain outline.
/// Shared by the app (plan cards, reminders) and the Live Activity widget.
enum TripProgress: String, Codable, Hashable, Sendable {
  case done, now, next, soon, later

  /// `end` defaults to one hour after `start`. `isNext` = the first moment that hasn't started yet.
  static func of(start: Date, end: Date? = nil, now: Date, isNext: Bool) -> TripProgress {
    // Lasts until the next moment starts, but never under 15 min or over 2 h.
    let end = max(min(end ?? start.addingTimeInterval(3600), start.addingTimeInterval(2 * 3600)), start.addingTimeInterval(15 * 60))
    if now >= end { return .done }
    if now >= start { return .now }
    let minutes = start.timeIntervalSince(now) / 60
    if minutes <= 30 { return .soon }
    if isNext && minutes <= 180 { return .next }
    return .later
  }

  /// "in 25 min" · "in 1 h 20 min" · "in 3 h".
  static func countdown(to start: Date, now: Date) -> String {
    let minutes = max(0, Int((start.timeIntervalSince(now) / 60).rounded(.up)))
    if minutes < 60 { return "in \(minutes) min" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
  }

  /// Short status for a card or a notification.
  func label(start: Date, now: Date) -> String? {
    switch self {
    case .done: "Done"
    case .now: "Now"
    case .next: "Next · " + Self.countdown(to: start, now: now)
    case .soon: { let c = Self.countdown(to: start, now: now); return c.prefix(1).uppercased() + c.dropFirst() }()
    case .later: nil
    }
  }
}
