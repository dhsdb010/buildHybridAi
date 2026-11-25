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
  enum Kind: String, Sendable { case text, system }
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
