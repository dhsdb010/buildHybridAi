import Foundation
import FoundationModels

// MARK: - On-device classifier (Survive)

/// What the traveler typed into the Ask bar. The model only *classifies*:
/// booking facts always come from stored `VaultItem` fields (plan §2, trust rule).
@Generable
struct AskIntent {
  @Guide(description: "vault = a question about the traveler's own bookings (times, codes, address, phone, taxi). other = anything else.",
         .anyOf(["vault", "other"]))
  var intent: String
  @Guide(description: "For vault: the number of the booking from the list that the question is about. -1 if none.")
  var itemIndex: Int
  @Guide(description: "For vault: which stored field answers the question. taxi = the user wants to show the address to a driver.",
         .anyOf(VaultField.allCases.map(\.rawValue)))
  var field: String
}

@Generable
struct GeneratedTranslation {
  @Guide(description: "The translation in the target language's native script (e.g. kana/kanji for Japanese, never romaji)")
  var translation: String
  @Guide(description: "Optional short note IN ENGLISH for the traveler about politeness or culture. Empty if nothing useful.")
  var note: String
}

enum VaultField: String, CaseIterable, Sendable {
  case confirmationCode, checkIn, checkOut, departure, arrival, route, address, taxi, phone, none
}

// MARK: - Deterministic answers from stored fields

struct VaultAnswer: Equatable, Sendable {
  /// Sentence shown to the traveler, built from a template, never generated.
  let text: String
  /// The stored value(s) the answer quotes, highlighted on the source card.
  let value: String
  let showTaxiCard: Bool
}

enum VaultAnswerBuilder {
  /// Builds the answer purely from stored fields. Returns nil when the field is empty,
  /// so the UI says "not in your bookings" instead of guessing.
  static func answer(_ item: VaultItem, _ field: VaultField) -> VaultAnswer? {
    func join(_ parts: String?...) -> String? {
      let s = parts.compactMap { $0 }.joined(separator: " ")
      return s.isEmpty ? nil : s
    }
    let t = item.title
    switch field {
    case .confirmationCode:
      return item.confirmationCode.map { .init(text: "Your confirmation code for \(t) is \($0).", value: $0, showTaxiCard: false) }
    case .checkIn:
      return join(item.startDate, item.checkInTime).map { .init(text: "Check-in at \(t): \($0).", value: $0, showTaxiCard: false) }
    case .checkOut:
      return join(item.endDate, item.checkOutTime).map { .init(text: "Check-out at \(t): \($0).", value: $0, showTaxiCard: false) }
    case .departure:
      return join(item.startDate, item.departureTime).map { .init(text: "\(t) departs \($0)\(item.origin.map { " from \($0)" } ?? "").", value: $0, showTaxiCard: false) }
    case .arrival:
      return join(item.endDate ?? item.startDate, item.arrivalTime).map { .init(text: "\(t) arrives \($0)\(item.destination.map { " at \($0)" } ?? "").", value: $0, showTaxiCard: false) }
    case .route:
      guard let o = item.origin, let d = item.destination else { return nil }
      return .init(text: "\(t) flies \(o) → \(d).", value: "\(o) → \(d)", showTaxiCard: false)
    case .address:
      return item.address.map { .init(text: "\(t) is at \($0).", value: $0, showTaxiCard: item.addressLocal != nil) }
    case .taxi:
      guard let local = item.addressLocal ?? item.address else { return nil }
      return .init(text: "Show this to the driver: \(t).", value: local, showTaxiCard: true)
    case .phone:
      return item.phone.map { .init(text: "\(t) phone: \($0).", value: $0, showTaxiCard: false) }
    case .none:
      return nil
    }
  }
}

// MARK: - Prompts

extension Prompts {
  static let askInstructions = """
    You route a traveler's request in a travel app. Classify it; never answer it yourself. \
    Pick the booking number from the list and the field that answers the question.
    """

  /// Only booking titles go into the prompt (not their values): keeps the on-device prompt tiny.
  static func ask(_ question: String, items: [VaultItem]) -> String {
    let list = items.enumerated().map { "\($0.offset): \($0.element.kind) · \($0.element.title)" }
      .joined(separator: "\n")
    return "Bookings:\n\(list.isEmpty ? "(none)" : list)\n\nRequest: \(question)"
  }

  static func translateInstructions(to language: String, from source: String, context: TranslationContext) -> String {
    var lines = [
      "You translate short spoken sentences for a traveler from \(source) into \(language).",
      "Use natural, polite phrasing a local would use. Write \(language) in its native script.",
      "Keep every medical and safety fact exactly: allergies stay allergies (never 'I don't take'), medicines, doses and numbers unchanged.",
      "After every medicine or drug name, add the English name in parentheses, e.g. イブプロフェン (ibuprofen).",
      "Return the translation and an optional one-line note written in English.",
    ]
    if let hotel = context.hotel { lines.append("The traveler is staying at \(hotel).") }
    if let s = context.situation { lines.append("Situation: \(s).") }
    lines.append("If the text begins with a situation such as 'At the pharmacy:', use it as context and translate only the rest.")
    return lines.joined(separator: " ")
  }

  static func translate(_ text: String) -> String { "Translate: \(text)" }
}

struct TranslationContext: Sendable {
  var hotel: String?
  var situation: String?
}

// MARK: - Bilingual reply prompt for Flip mode (static, no AI)

enum ReplyPrompt {
  /// "Please type your reply here" in common destination languages.
  static let byLanguage: [String: String] = [
    "ja": "こちらにご返信を入力してください",
    "ko": "여기에 답변을 입력해 주세요",
    "zh": "请在这里输入您的回复",
    "th": "กรุณาพิมพ์คำตอบของคุณที่นี่",
    "vi": "Vui lòng nhập câu trả lời của bạn tại đây",
    "es": "Escriba su respuesta aquí, por favor",
    "fr": "Veuillez saisir votre réponse ici",
    "de": "Bitte geben Sie hier Ihre Antwort ein",
    "it": "Scriva qui la sua risposta, per favore",
  ]

  static func text(for languageCode: String?) -> String {
    guard let code = languageCode?.prefix(2) else { return "Type your reply here" }
    return byLanguage[String(code)] ?? "Type your reply here"
  }
}

// MARK: - Runtime

enum AskOutcome {
  case vault(VaultAnswer, item: VaultItem, meta: AIMeta)
  /// The question was about bookings, but no stored field answers it.
  case notInVault(meta: AIMeta)
  case translation(TranslationEntry, meta: AIMeta)
  case other(meta: AIMeta)
}

extension AIService {
  /// Ask mode: on-device classification (Survive policy), then an answer built from stored fields.
  func ask(_ question: String, items: [VaultItem], pack: DestinationPack?) async throws -> AskOutcome {
    let (intent, meta) = try await generate(
      "classifyAsk", kind: .survive, prompt: Prompts.ask(question, items: items),
      instructions: Prompts.askInstructions, as: AskIntent.self)

    switch intent.intent {
    case "vault":
      guard items.indices.contains(intent.itemIndex),
            let field = VaultField(rawValue: intent.field),
            let answer = VaultAnswerBuilder.answer(items[intent.itemIndex], field)
      else { return .notInVault(meta: meta) }
      return .vault(answer, item: items[intent.itemIndex], meta: meta)
    default:
      return .other(meta: meta)
    }
  }

  /// Say mode: translate straight away, no classification step.
  func say(_ text: String, items: [VaultItem], pack: DestinationPack?) async throws -> AskOutcome {
    let (entry, meta) = try await translate(text, direction: "out", pack: pack)
    return .translation(entry, meta: meta)
  }

  /// Context-aware translation. `out`: English → local language. `in`: a local's reply → English.
  func translate(_ text: String, direction: String, pack: DestinationPack?,
                 situation: String? = nil, hotel: String? = nil) async throws -> (TranslationEntry, AIMeta) {
    let local = pack?.languageName ?? "the local language"
    let (from, to) = direction == "out" ? ("English", local) : (local, "English")
    let (t, meta) = try await generate(
      direction == "out" ? "translate" : "translateReply", kind: .survive,
      prompt: Prompts.translate(text),
      instructions: Prompts.translateInstructions(
        to: to, from: from, context: .init(hotel: hotel, situation: situation)),
      as: GeneratedTranslation.self)
    let entry = TranslationEntry(
      sourceText: text, translation: t.translation, direction: direction,
      languageCode: pack?.languageCode ?? "", source: meta.source == .onDevice ? "onDevice" : "inCloud",
      isDraft: meta.source == .onDevice)
    // Pronunciation is computed on-device by the OS, not generated (works offline, no hallucinated romaji).
    entry.romanization = direction == "out" ? Romanizer.latin(t.translation, languageCode: pack?.languageCode) : ""
    entry.note = t.note
    entry.situation = situation
    entry.latencyMs = meta.latencyMs
    context.insert(entry)
    try? context.save()
    return (entry, meta)
  }
}

// MARK: - Deterministic romanization

enum Romanizer {
  /// Japanese: CFStringTokenizer transcription gives kanji readings (東京 → toukyou).
  /// Other non-Latin scripts: ICU Any-Latin. Returns "" for Latin-script text.
  static func latin(_ text: String, languageCode: String?) -> String {
    guard text.unicodeScalars.contains(where: { $0.value > 0x024F }) else { return "" }
    let code = String((languageCode ?? "").prefix(2))
    if code == "ja" {
      let cf = text as CFString
      let tokenizer = CFStringTokenizerCreate(nil, cf, CFRangeMake(0, CFStringGetLength(cf)),
                                              kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
      var parts: [String] = []
      let particles = ["は": "wa", "へ": "e", "を": "o"]
      while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let r0 = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let token = (text as NSString).substring(with: NSRange(location: r0.location, length: r0.length))
        if let p = particles[token] {
          parts.append(p)
        } else if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
          parts.append(latin)
        } else {
          let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
          parts.append((text as NSString).substring(with: NSRange(location: r.location, length: r.length)))
        }
      }
      // Attach a lone "n" (ん) to the previous syllable: "mase n" → "masen".
      var merged: [String] = []
      for p in parts {
        if p == "n", let last = merged.popLast() { merged.append(last + "n") } else { merged.append(p) }
      }
      return merged.joined(separator: " ")
        .replacingOccurrences(of: "( ", with: "(").replacingOccurrences(of: " )", with: ")")
        .replacingOccurrences(of: " 。", with: ".").replacingOccurrences(of: "。", with: ".")
        .replacingOccurrences(of: " 、", with: ",").replacingOccurrences(of: " ？", with: "?")
    }
    return (text.applyingTransform(.toLatin, reverse: false) ?? "")
      .applyingTransform(.stripDiacritics, reverse: false) ?? ""
  }
}
