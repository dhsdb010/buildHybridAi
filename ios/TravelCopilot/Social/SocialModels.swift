import Foundation

/// A person on Travel Copilot, as friends see them: name, initial and @ID. Never email or photo.
struct SocialUser: Identifiable, Hashable, Sendable {
  let id: String        // Firebase uid
  var handle: String    // without "@"
  var name: String
  var initial: String { String((name.isEmpty ? handle : name).prefix(1)).uppercased() }
}

/// "Sora wants to be friends." Stored at friendRequests/{from}_{to}.
struct FriendRequest: Identifiable, Hashable, Sendable {
  let from: SocialUser
  let to: SocialUser
  let createdAt: Date
  var id: String { FriendRequest.docID(from: from.id, to: to.id) }
  static func docID(from: String, to: String) -> String { "\(from)_\(to)" }
}

/// One room per shared trip. Only friends of whoever adds them can join.
struct TripRoom: Identifiable, Hashable, Sendable {
  struct Member: Hashable, Sendable {
    let id: String
    var name: String
    var handle: String
    var role: Role
    var initial: String { String((name.isEmpty ? handle : name).prefix(1)).uppercased() }
  }
  enum Role: String, Sendable { case owner, editor, viewer
    var title: String { switch self { case .owner: "Owner"; case .editor: "Can edit"; case .viewer: "Can view" } }
  }

  let id: String
  var name: String
  var owner: String
  var members: [Member]
  var tripTitle: String?
  var friendsCanEdit: Bool
  var createdAt: Date
  var lastText: String?
  var lastAt: Date?

  var memberIDs: [String] { members.map(\.id) }
  func member(_ uid: String) -> Member? { members.first { $0.id == uid } }
  /// "You, Mina, Jun"
  func membersText(me: String) -> String {
    (members.filter { $0.id == me }.map { _ in "You" } + members.filter { $0.id != me }.map(\.name)).joined(separator: ", ")
  }
  var sortDate: Date { lastAt ?? createdAt }
}

struct RoomMessage: Identifiable, Hashable, Sendable {
  enum Kind: String, Sendable { case text, system, blue }
  let id: String
  var author: String
  var authorName: String
  var text: String
  var sentAt: Date?
  var kind: Kind
  /// Written on this iPhone but not on the server yet ("Sends when you're back online").
  var pending: Bool
}

/// Rules for @IDs, invite codes and message text. Pure, so they're unit-tested.
enum Handle {
  static let minLength = 3, maxLength = 20

  /// "@Alex_K " → "alex_k". Lowercase letters, numbers and _ only.
  static func normalize(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if t.hasPrefix("@") { t.removeFirst() }
    return t
  }

  enum Problem: Equatable { case tooShort, tooLong, badCharacters, reserved }

  static func problem(_ raw: String) -> Problem? {
    let h = normalize(raw)
    if h.count < minLength { return .tooShort }
    if h.count > maxLength { return .tooLong }
    if h.range(of: "^[a-z0-9_]+$", options: .regularExpression) == nil { return .badCharacters }
    if reserved.contains(h) { return .reserved }
    return nil
  }
  static func isValid(_ raw: String) -> Bool { problem(raw) == nil }

  static func message(_ p: Problem) -> String {
    switch p {
    case .tooShort: "At least \(minLength) characters."
    case .tooLong: "At most \(maxLength) characters."
    case .badCharacters: "Use lowercase letters, numbers or _."
    case .reserved: "That ID is reserved."
    }
  }

  /// A starting suggestion from the person's name: "Alex Kim" → "alex_kim".
  static func suggestion(name: String) -> String {
    let base = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
      .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    let cut = String(base.prefix(maxLength))
    return cut.count >= minLength ? cut : ""
  }

  static let reserved: Set<String> = ["blue", "admin", "support", "travelcopilot", "travel_copilot", "help", "team", "official"]
}

/// Friend invite codes: 8 letters/numbers without look-alikes (no 0/O, 1/I/L). Shown as "K7Q4 MZ2H".
enum InviteCode {
  static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
  static let length = 8
  static let lifetime: TimeInterval = 7 * 24 * 3600

  static func make() -> String {
    var g = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in alphabet.randomElement(using: &g)! })
  }

  /// Accepts "k7q4 mz2h", "K7Q4-MZ2H" or a full link; nil if it isn't a code.
  static func parse(_ s: String) -> String? {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: t), url.scheme != nil {
      let parts = url.pathComponents.filter { $0 != "/" }
      if url.scheme == "travelcopilot", url.host() == "i", let last = parts.last { t = last }
      else if let i = parts.firstIndex(of: "i"), i + 1 < parts.count { t = parts[i + 1] }
      else { return nil }
    }
    let code = t.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    guard code.count == length, code.allSatisfy({ alphabet.contains($0) }) else { return nil }
    return code
  }

  static func display(_ code: String) -> String { "\(code.prefix(4)) \(code.dropFirst(4))" }

  /// https://<project>.web.app/i/CODE when Firebase is set up; the app's own link otherwise.
  static func link(_ code: String, projectID: String?) -> URL {
    if let p = projectID, !p.isEmpty { return URL(string: "https://\(p).web.app/i/\(code)")! }
    return URL(string: "travelcopilot://i/\(code)")!
  }

  static func isExpired(createdAt: Date, now: Date = Date()) -> Bool { now.timeIntervalSince(createdAt) > lifetime }
}

/// A light filter before a message is posted (App Store guideline 1.2). Reports catch the rest.
enum MessageFilter {
  static let maxLength = 2000
  private static let blocked = ["fuck", "shit", "bitch", "cunt", "nigger", "faggot", "retard"]

  static func clean(_ s: String) -> String {
    var out = s
    for w in blocked {
      out = out.replacingOccurrences(of: "\\b\(w)\\w*", with: String(repeating: "•", count: w.count),
                                     options: [.regularExpression, .caseInsensitive])
    }
    return String(out.prefix(maxLength))
  }
}

/// One stop in a room's shared plan (Figma 12 · screens 24–26). Stored at rooms/{id}/plan/{stopID}.
struct SharedStop: Identifiable, Hashable, Sendable {
  var id: String
  var date: Date
  var title: String
  var detail: String
  var kind: String
  var latitude: Double?
  var longitude: Double?
  var addedBy: String
  var addedByName: String
  /// Set when someone other than the adder changed it ("Mina changed").
  var editedByName: String?
  /// Rough cost per person in US dollars, a note and the address, as in Plan a day.
  var cost = 0
  var note = ""
  var address = ""

  /// What the planner hands over before ids and authors exist.
  struct Draft: Hashable, Sendable {
    var date: Date
    var title: String
    var detail: String
    var kind: String
    var latitude: Double?
    var longitude: Double?
    var cost = 0
    var note = ""
    var address = ""
  }
}

/// The shared plan grouped by day, for the room's pinned bar and the edit screen.
enum SharedPlan {
  static func days(_ stops: [SharedStop]) -> [Date] {
    let cal = TripTimeline.calendar
    return Array(Set(stops.map { cal.startOfDay(for: $0.date) })).sorted()
  }

  static func stops(on day: Date, _ stops: [SharedStop]) -> [SharedStop] {
    stops.filter { TripTimeline.calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
  }

  /// "Dec 2–7 · 6 days · 14 stops"
  static func summary(_ stops: [SharedStop]) -> String {
    let d = days(stops)
    guard let first = d.first, let last = d.last else { return "No stops yet" }
    let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
    let range = first == last ? first.formatted(f)
      : TripTimeline.calendar.isDate(first, equalTo: last, toGranularity: .month)
        ? "\(first.formatted(f))–\(last.formatted(.dateTime.day()))" : "\(first.formatted(f)) – \(last.formatted(f))"
    return "\(range) · \(d.count) day\(d.count == 1 ? "" : "s") · \(stops.count) stop\(stops.count == 1 ? "" : "s")"
  }

  /// Short lines for Blue: "Dec 3 10:00 teamLab Planets (See)".
  static func lines(_ stops: [SharedStop]) -> [String] {
    stops.sorted { $0.date < $1.date }.map {
      "\($0.date.formatted(.dateTime.month(.abbreviated).day())) \(TripTimeline.time($0.date)) \($0.title)\($0.kind.isEmpty ? "" : " (\($0.kind))")"
    }
  }
}

extension SharedStop {
  var hasCoordinate: Bool { (latitude ?? 0) != 0 || (longitude ?? 0) != 0 }

  /// As a Plan a day stop, so the shared plan uses the same map, rows and stop detail.
  func dayStop(id: UUID) -> DayStop {
    DayStop(id: id, time: date, kind: kind.isEmpty ? "Stop" : kind, name: title, why: detail, address: address,
            latitude: latitude ?? 0, longitude: longitude ?? 0, cost: cost, note: note)
  }

  /// Takes the edits from the stop detail screen.
  func applying(_ d: DayStop) -> SharedStop {
    var s = self
    s.date = d.time; s.title = d.name; s.detail = d.why; s.kind = d.kind == "Stop" ? kind : d.kind
    s.cost = d.cost; s.note = d.note; s.address = d.address
    if d.latitude != 0 || d.longitude != 0 { s.latitude = d.latitude; s.longitude = d.longitude }
    return s
  }
}
