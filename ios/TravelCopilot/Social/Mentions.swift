import Foundation

/// @ mentions in a trip room (Figma 12 · screens 19–21): typing @ suggests Blue first, then the
/// people in this room by name and @ID. Pure, so it's unit-tested.
enum Mentions {
  struct Suggestion: Identifiable, Equatable {
    let id: String          // "blue" or the member's uid
    let title: String       // "Blue", "Mina"
    let subtitle: String    // "Ask for the group · answers online", "@mina"
    let insert: String      // "Blue", "Mina" (inserted as "@Mina ")
    let initial: String
    var isBlue: Bool { id == "blue" }
  }

  /// What's typed after a trailing "@" ("Saturday works. @mi" → "mi"), or nil when the text doesn't
  /// end in a mention being typed. "@" must start a word, so an email like a@b doesn't count.
  static func activeQuery(in text: String) -> String? {
    guard let at = text.lastIndex(of: "@") else { return nil }
    if at > text.startIndex {
      let before = text[text.index(before: at)]
      guard before.isWhitespace || before.isPunctuation && before != "@" && before != "." else { return nil }
    }
    let typed = text[text.index(after: at)...]
    guard typed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), typed.count <= 20 else { return nil }
    return String(typed).lowercased()
  }

  /// The word people insert for someone: their first name without spaces ("Mina Park" → "Mina").
  static func word(for name: String, handle: String) -> String {
    let first = name.split(separator: " ").first.map(String.init) ?? ""
    let clean = first.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    return clean.isEmpty ? handle : clean
  }

  /// Blue first (when it matches), then the other people in the room whose name or @ID starts
  /// with what's typed. Never yourself, never anyone outside the room.
  static func suggestions(query q: String, room: TripRoom, me: String) -> [Suggestion] {
    var out: [Suggestion] = []
    if q.isEmpty || "blue".hasPrefix(q) {
      out.append(.init(id: "blue", title: "Blue", subtitle: "Ask for the group · answers online", insert: "Blue", initial: ""))
    }
    for m in room.members where m.id != me {
      let w = word(for: m.name, handle: m.handle)
      let names = [w.lowercased(), m.name.lowercased(), m.handle.lowercased()]
      guard q.isEmpty || names.contains(where: { $0.hasPrefix(q) }) else { continue }
      out.append(.init(id: m.id, title: m.name.isEmpty ? "@\(m.handle)" : m.name, subtitle: "@\(m.handle)", insert: w, initial: m.initial))
    }
    return out
  }

  /// Replaces the "@mi" being typed with "@Mina ".
  static func insert(_ s: Suggestion, into text: String) -> String {
    guard let at = text.lastIndex(of: "@") else { return text + "@\(s.insert) " }
    return String(text[..<at]) + "@\(s.insert) "
  }

  /// Ranges of "@Word" that name Blue or someone in the room, for bold text in bubbles.
  static func ranges(in text: String, room: TripRoom) -> [Range<String.Index>] {
    let known = Set(["blue"] + room.members.flatMap { [word(for: $0.name, handle: $0.handle).lowercased(), $0.handle.lowercased()] })
    var out: [Range<String.Index>] = []
    var search = text.startIndex..<text.endIndex
    while let r = text.range(of: #"(?<![\w@.])@[A-Za-z0-9_]+"#, options: .regularExpression, range: search) {
      if known.contains(text[text.index(after: r.lowerBound)..<r.upperBound].lowercased()) { out.append(r) }
      search = r.upperBound..<text.endIndex
    }
    return out
  }

  /// The text with known mentions in bold.
  static func attributed(_ text: String, room: TripRoom) -> AttributedString {
    var a = AttributedString(text)
    for r in ranges(in: text, room: room) {
      if let lo = AttributedString.Index(r.lowerBound, within: a), let hi = AttributedString.Index(r.upperBound, within: a) {
        a[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
      }
    }
    return a
  }
}
