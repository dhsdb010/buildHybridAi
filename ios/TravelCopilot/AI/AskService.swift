import Foundation
import FoundationModels

// MARK: - On-device classifier (Survive)

/// What the traveler typed into the Ask bar. The model only *classifies*:
/// booking facts always come from stored `VaultItem` fields (plan §2, trust rule).
@Generable
struct AskIntent {
  @Guide(description: "vault = a question about the traveler's own bookings (times, codes, address, phone, taxi). place = how far / how to get to a place on the map. other = anything else.",
         .anyOf(["vault", "place", "other"]))
  var intent: String
  @Guide(description: "For vault: the number of the booking from the list that the question is about. -1 if none.")
  var itemIndex: Int
  @Guide(description: "For vault: which stored field answers the question. taxi = the user wants to show the address to a driver.",
         .anyOf(VaultField.allCases.map(\.rawValue)))
  var field: String
  @Guide(description: "For place: the number of the place from the Places list. -1 if none.")
  var placeIndex: Int
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

// MARK: - Guard: the question must actually ask for what the model picked

/// The small on-device model always picks *some* booking and field, even for "Hello".
/// So a booking answer is shown only when the question has a word that asks for that field
/// (or a distance word for places). Otherwise it's small talk and gets the help reply.
enum AskGuard {
  static let fieldWords: [VaultField: [String]] = [
    .confirmationCode: ["code", "confirmation", "booking", "reservation", "ref", "pnr", "number", "reference"],
    .checkIn: ["check-in", "check in", "checkin", "arrive at the hotel", "get in", "room ready"],
    .checkOut: ["check-out", "check out", "checkout", "leave the hotel"],
    .departure: ["depart", "leave", "leaving", "board", "gate", "when", "time", "flight", "train"],
    .arrival: ["arrive", "arrival", "land", "get there", "when", "time"],
    .route: ["route", "from", "where", "fly", "going"],
    .address: ["address", "where", "location", "located"],
    .taxi: ["taxi", "driver", "cab", "uber", "show"],
    .phone: ["phone", "call", "contact", "number", "tel"],
  ]
  static let placeWords = ["far", "distance", "how long", "get to", "go to", "walk", "near", "close", "minutes", "km", "directions", "way to"]

  static func fits(_ question: String, field: VaultField) -> Bool {
    let q = question.lowercased()
    return fieldWords[field, default: []].contains { q.contains($0) }
  }

  static func fitsPlace(_ question: String) -> Bool {
    let q = question.lowercased()
    return placeWords.contains { q.contains($0) }
  }
}

// MARK: - Place answers (computed from saved coordinates, never generated)

struct PlaceAnswer: Equatable, Sendable {
  let text: String
  let distance: String
  let estimate: String
  let from: String
}

enum PlaceAnswerBuilder {
  /// Distance from the hotel (or from the traveler's GPS position when the place *is* the hotel).
  static func answer(_ place: Place, places: [Place], here: (lat: Double, lon: Double)?) -> PlaceAnswer? {
    let hotel = places.first { $0.kind == "hotel" }
    let origin: (lat: Double, lon: Double, name: String)?
    if let hotel, hotel !== place { origin = (hotel.latitude, hotel.longitude, hotel.name) }
    else if let here { origin = (here.lat, here.lon, "you") }
    else { origin = nil }
    guard let origin else { return nil }
    let m = PlaceFacts.meters(origin.lat, origin.lon, place.latitude, place.longitude)
    let d = PlaceFacts.distance(m), e = PlaceFacts.estimate(m)
    return PlaceAnswer(text: "\(place.name) is \(d) from \(origin.name) — \(e).", distance: d, estimate: e, from: origin.name)
  }
}

// MARK: - Prompts

extension Prompts {
  static let askInstructions = """
    You route a traveler's request in a travel app. Classify it; never answer it yourself. \
    Pick the booking number from the list and the field that answers the question, \
    or for distance and directions questions pick the place number.
    """

  /// Only booking titles go into the prompt (not their values): keeps the on-device prompt tiny.
  static func ask(_ question: String, items: [VaultItem], places: [Place] = []) -> String {
    let list = items.enumerated().map { "\($0.offset): \($0.element.kind) · \($0.element.title)" }
      .joined(separator: "\n")
    let placeList = places.enumerated().map { "\($0.offset): \($0.element.kind) · \($0.element.name)" }
      .joined(separator: "\n")
    return "Bookings:\n\(list.isEmpty ? "(none)" : list)\n\nPlaces:\n\(placeList.isEmpty ? "(none)" : placeList)\n\nRequest: \(question)"
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

/// What the local person (driver, clerk) reads on the reply screen, in their own language.
/// Static text written once (no AI), so it's right every time and works offline.
struct LocalReplyScreen: Equatable {
  let title: String
  let body: String
  let placeholder: String
  let send: String
  let handBack: String

  static let english = LocalReplyScreen(
    title: "Please type your reply",
    body: "This traveller is using a translation app. Type your reply below and tap Send. It will be translated into English.",
    placeholder: "Type here", send: "Send", handBack: "After sending, please hand the phone back.")

  static let byLanguage: [String: LocalReplyScreen] = [
    "ja": .init(title: "返信を入力してください",
                body: "このお客様は翻訳アプリを使っています。下に返信を入力して「送信」を押してください。英語に翻訳されます。",
                placeholder: "ここに入力", send: "送信", handBack: "送信したら、スマートフォンをお客様にお返しください。"),
    "ko": .init(title: "답변을 입력해 주세요",
                body: "이 손님은 번역 앱을 사용하고 있습니다. 아래에 답변을 입력하고 '보내기'를 눌러 주세요. 영어로 번역됩니다.",
                placeholder: "여기에 입력", send: "보내기", handBack: "보낸 후 휴대폰을 손님께 돌려주세요."),
    "zh": .init(title: "请输入您的回复",
                body: "这位客人正在使用翻译应用。请在下方输入回复，然后点击“发送”，内容会被翻译成英文。",
                placeholder: "在此输入", send: "发送", handBack: "发送后，请把手机还给客人。"),
    "fr": .init(title: "Veuillez écrire votre réponse",
                body: "Ce voyageur utilise une application de traduction. Écrivez votre réponse ci-dessous et appuyez sur « Envoyer » : elle sera traduite en anglais.",
                placeholder: "Écrivez ici", send: "Envoyer", handBack: "Après l'envoi, rendez le téléphone au voyageur."),
    "es": .init(title: "Escriba su respuesta, por favor",
                body: "Este viajero usa una aplicación de traducción. Escriba su respuesta abajo y pulse «Enviar»: se traducirá al inglés.",
                placeholder: "Escriba aquí", send: "Enviar", handBack: "Después de enviar, devuelva el teléfono al viajero."),
    "de": .init(title: "Bitte schreiben Sie Ihre Antwort",
                body: "Dieser Reisende nutzt eine Übersetzungs-App. Schreiben Sie Ihre Antwort unten und tippen Sie auf „Senden“. Sie wird ins Englische übersetzt.",
                placeholder: "Hier eingeben", send: "Senden", handBack: "Geben Sie das Telefon danach bitte zurück."),
    "it": .init(title: "Scriva la sua risposta, per favore",
                body: "Questo viaggiatore usa un'app di traduzione. Scriva la risposta qui sotto e tocchi «Invia»: verrà tradotta in inglese.",
                placeholder: "Scriva qui", send: "Invia", handBack: "Dopo l'invio, restituisca il telefono al viaggiatore."),
    "pt": .init(title: "Escreva sua resposta, por favor",
                body: "Este viajante está usando um app de tradução. Escreva sua resposta abaixo e toque em “Enviar”: ela será traduzida para o inglês.",
                placeholder: "Escreva aqui", send: "Enviar", handBack: "Depois de enviar, devolva o telefone ao viajante."),
    "th": .init(title: "กรุณาพิมพ์คำตอบของคุณ",
                body: "นักท่องเที่ยวท่านนี้ใช้แอปแปลภาษา กรุณาพิมพ์คำตอบด้านล่างแล้วกด “ส่ง” ข้อความจะถูกแปลเป็นภาษาอังกฤษ",
                placeholder: "พิมพ์ที่นี่", send: "ส่ง", handBack: "ส่งแล้วกรุณาคืนโทรศัพท์ให้นักท่องเที่ยว"),
    "vi": .init(title: "Vui lòng nhập câu trả lời",
                body: "Du khách này đang dùng ứng dụng dịch. Vui lòng nhập câu trả lời bên dưới và nhấn “Gửi”, nội dung sẽ được dịch sang tiếng Anh.",
                placeholder: "Nhập tại đây", send: "Gửi", handBack: "Gửi xong, vui lòng trả lại điện thoại cho du khách."),
  ]

  static func screen(for languageCode: String?) -> LocalReplyScreen {
    guard let code = languageCode?.prefix(2) else { return english }
    return byLanguage[String(code)] ?? english
  }
}

// MARK: - Runtime

enum AskOutcome {
  case vault(VaultAnswer, item: VaultItem, meta: AIMeta)
  /// Distance answer computed from saved map coordinates.
  case place(PlaceAnswer, place: Place, meta: AIMeta)
  /// The question was about bookings, but no stored field answers it.
  case notInVault(meta: AIMeta)
  case translation(TranslationEntry, meta: AIMeta)
  case other(meta: AIMeta)
}

extension AIService {
  /// Ask mode: on-device classification (Survive policy), then an answer built from stored fields.
  func ask(_ question: String, items: [VaultItem], pack: DestinationPack?,
           places: [Place] = [], here: (lat: Double, lon: Double)? = nil) async throws -> AskOutcome {
    let (intent, meta) = try await generate(
      "classifyAsk", kind: .survive, prompt: Prompts.ask(question, items: items, places: places),
      instructions: Prompts.askInstructions, as: AskIntent.self)

    switch intent.intent {
    case "vault":
      // Small talk ("Hello") gets the help reply, never a booking value.
      guard let field = VaultField(rawValue: intent.field), AskGuard.fits(question, field: field)
      else { return .other(meta: meta) }
      guard items.indices.contains(intent.itemIndex),
            let answer = VaultAnswerBuilder.answer(items[intent.itemIndex], field)
      else { return .notInVault(meta: meta) }
      return .vault(answer, item: items[intent.itemIndex], meta: meta)
    case "place":
      guard AskGuard.fitsPlace(question) else { return .other(meta: meta) }
      guard places.indices.contains(intent.placeIndex),
            let answer = PlaceAnswerBuilder.answer(places[intent.placeIndex], places: places, here: here)
      else { return .notInVault(meta: meta) }
      return .place(answer, place: places[intent.placeIndex], meta: meta)
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
  /// Easier for English speakers: glue polite endings, drop long-vowel doubling, tidy numbers.
  static func readable(_ s: String) -> String {
    var t = s
    for (a, b) in [(" - ", "-"), (" -", "-"), ("- ", "-"),
                   ("o negai", "onegai"), ("negai shi masu", "negaishimasu"), ("shi masu", "shimasu"),
                   ("de su", "desu"), ("ma su", "masu"), ("ma sen", "masen"), ("kudasa i", "kudasai")] {
      t = t.replacingOccurrences(of: a, with: b)
    }
    t = t.replacingOccurrences(of: "ou", with: "o").replacingOccurrences(of: "uu", with: "u")
    // "shinjuku ku" → "shinjuku-ku", "toukyou to" → "tokyo-to" (address suffixes)
    t = t.replacingOccurrences(of: #" (ku|to|shi|cho|machi)\b"#, with: "-$1", options: .regularExpression)
    return t.prefix(1).uppercased() + t.dropFirst()
  }

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
      let raw = merged.joined(separator: " ")
        .replacingOccurrences(of: "( ", with: "(").replacingOccurrences(of: " )", with: ")")
        .replacingOccurrences(of: " 。", with: ".").replacingOccurrences(of: "。", with: ".")
        .replacingOccurrences(of: " 、", with: ",").replacingOccurrences(of: " ？", with: "?")
      return readable(raw)
    }
    return (text.applyingTransform(.toLatin, reverse: false) ?? "")
      .applyingTransform(.stripDiacritics, reverse: false) ?? ""
  }
}
