import Foundation
import FoundationModels

@Generable
struct EmergencyTranslations {
  @Guide(description: "One translation per input line, same order and same count.")
  var lines: [String]
}

/// Translates the traveler's own words on the card once, while online (cloud, for accuracy),
/// and keeps only translations that pass code checks. Labels and common items never go through AI.
@MainActor
enum EmergencyTranslator {
  enum Result: Equatable { case done(Int), nothingToDo, offline, failed(String) }

  static func translate(_ card: EmergencyCard, to language: String, languageName: String, ai: AIService) async -> Result {
    let items = EmergencyText.needsTranslation(card, language: language)
    guard !items.isEmpty else { card.translationLanguage = String(language.prefix(2)); return .nothingToDo }
    do {
      let medicineNames = Set(card.medicines.map(\.text))
      let (t, _) = try await ai.generate(
        "Emergency card · translate", kind: .prepare,
        prompt: items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
        instructions: """
          Translate each numbered line of a traveler's emergency medical card from English into \(languageName), \
          as a doctor in that country would write it. Keep every number, dose and unit exactly. \
          After every medicine name, add the English name in parentheses, e.g. イブプロフェン (ibuprofen). \
          Return one translation per line, same order, without the numbers.
          """,
        as: EmergencyTranslations.self)
      let code = String(language.prefix(2))
      if card.translationLanguage != code { card.translations = [:] }
      card.translationLanguage = code
      var kept = 0
      for (en, local) in zip(items, t.lines) {
        let clean = local.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSafe(en, clean, isMedicine: medicineNames.contains(en)) { card.translations[en] = clean; kept += 1 }
      }
      return .done(kept)
    } catch AIServiceError.blocked(_) {
      return .offline
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  /// Every number in the English must still be there (doses can't change). The only extra numbers
  /// allowed are small counts a language writes as digits ("twice a day" → 1日2回).
  /// A medicine keeps its English name, so a pharmacist can check it.
  static func isSafe(_ english: String, _ local: String, isMedicine: Bool) -> Bool {
    guard !local.isEmpty else { return false }
    var remaining = SafetyCheck.numbers(local)
    for n in SafetyCheck.numbers(english) {
      guard let i = remaining.firstIndex(of: n) else { return false }
      remaining.remove(at: i)
    }
    guard remaining.allSatisfy({ (Double($0) ?? 99) <= 12 }) else { return false }
    if isMedicine, let name = english.split(separator: " ").first?.lowercased(), name.count >= 3 {
      return local.lowercased().contains(name)
    }
    return true
  }
}
