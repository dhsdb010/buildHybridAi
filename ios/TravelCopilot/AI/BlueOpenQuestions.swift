import Foundation
import FoundationModels
import SwiftData

@Generable
struct OpenAnswer {
  @Guide(description: "A short, practical answer for the traveler, at most 80 words, in plain English.")
  var answer: String
}

extension AskGuard {
  /// Greetings and thanks get Blue's help reply right away; they don't need a cloud answer.
  static func isSmallTalk(_ question: String) -> Bool {
    let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    let phrases = ["hi", "hello", "hey", "yo", "thanks", "thank you", "thx", "good morning", "good evening",
                   "good night", "ok", "okay", "cool", "nice", "bye", "goodbye", "hi blue", "hello blue", "hey blue"]
    if phrases.contains(q) { return true }
    let words = q.split(separator: " ")
    let starts = ["thanks", "thank", "hi", "hello", "hey", "i love", "love", "great", "awesome", "nice"]
    return words.count <= 4 && !q.contains("?") && starts.contains(where: { q.hasPrefix($0) })
  }
}

extension Prompts {
  static let openInstructions = """
    You are Blue, a calm travel assistant inside a travel app. Answer the traveler's question briefly and practically. \
    Do not invent specific business names, addresses, prices, opening hours or schedules. Give general guidance \
    (what kind of place, what to look for, what to say) and suggest the app's Map tab for nearby places. \
    For booking facts (times, codes, addresses) say they're in the traveler's saved bookings.
    """

  /// Trip context without codes or personal details: where and when, and the hotel's area.
  static func open(_ question: String, items: [VaultItem], pack: DestinationPack?) -> String {
    var lines: [String] = []
    if let country = pack?.countryName { lines.append("Trip: \(country)") }
    if let hotel = items.first(where: { $0.kind == "hotel" }) {
      lines.append("Staying at: \(hotel.title)\(hotel.address.map { ", \($0)" } ?? "")")
      if let start = hotel.startDate, let end = hotel.endDate { lines.append("Dates: \(start) to \(end)") }
    }
    lines.append("Question: \(question)")
    return lines.joined(separator: "\n")
  }
}

extension AIService {
  /// An open question, answered by Gemini in the cloud. Throws `deferred` when offline.
  func openAnswer(_ question: String, items: [VaultItem], pack: DestinationPack?) async throws -> (String, AIMeta) {
    let (a, meta) = try await generate("Blue · open question", kind: .open,
                                       prompt: Prompts.open(question, items: items, pack: pack),
                                       instructions: Prompts.openInstructions, as: OpenAnswer.self)
    return (a.answer.trimmingCharacters(in: .whitespacesAndNewlines), meta)
  }
}
