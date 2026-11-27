import Foundation
import FoundationModels

/// @Blue in a trip room (Figma 12 · screen 5). Blue answers only when someone writes @Blue, and
/// sees only this room: its name, trip title and recent messages. Never the Vault, receipts,
/// medical card or private chats with Blue. The asker's iPhone asks and posts the reply.
enum BlueInRoom {
  /// "@Blue", "@blue", "@BLUE," … as a word, not inside an email or another @ID.
  static func mentions(_ text: String) -> Bool {
    text.range(of: #"(^|[^A-Za-z0-9_@.])@blue\b"#, options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// The question without the mention: "@blue can you suggest…" → "can you suggest…".
  static func question(_ text: String) -> String {
    text.replacingOccurrences(of: #"@blue\b[,:]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static let instructions = """
    You are Blue, the travel copilot inside a group chat where friends plan a trip together.
    Answer the latest @Blue question for the whole group, in the same language they used.
    Be concrete and short, plain text, no markdown symbols.
    For a day-by-day plan, write one line per day, each starting with the day ("Dec 3 · …"), at most
    two stops per line, separated by line breaks; keep the whole plan under 140 words.
    Otherwise answer in at most 90 words.
    Use the room name, trip title, the group's shared plan and the chat below, plus general travel knowledge (typical opening
    hours, neighbourhoods, how to get around, what's good at that time of year). Give hours and
    prices as "usually …"; if you mention them, end with one short line: "Check official sites for exact
    hours." Don't refuse just because it isn't live.
    You can't see anyone's bookings, receipts or personal details; if the question needs them, say so
    briefly. Never make up a booking. If the trip's city isn't clear, ask which city in one short sentence.
    """

  /// The room, the last few messages (oldest first) and the question.
  static func prompt(room: TripRoom, messages: [RoomMessage], question: String, asker: String, plan: [SharedStop] = []) -> String {
    let recent = messages.filter { $0.kind != .system }.suffix(15).map { m in
      "\(m.kind == .blue ? "Blue" : m.authorName): \(m.text.prefix(300))"
    }
    return """
      Room: \(room.name)\(room.tripTitle.map { " · trip: \($0)" } ?? "")
      People: \(room.members.map(\.name).joined(separator: ", "))
      Shared plan: \(plan.isEmpty ? "none yet" : "\n" + SharedPlan.lines(plan).prefix(60).joined(separator: "\n"))
      Recent chat:
      \(recent.isEmpty ? "(none yet)" : recent.joined(separator: "\n"))
      Question from \(asker): \(question.isEmpty ? "Can you help us plan?" : question)
      """
  }
}

@Generable
struct BlueGroupReply: Sendable {
  @Guide(description: "Blue's answer to the group in plain text. A day-by-day plan has one line per day, separated by newlines.")
  var text: String
}
