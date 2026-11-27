import CoreLocation
import FirebaseAILogic
import FirebaseCore
import Foundation
import FoundationModels
import MapKit
import SwiftData

// MARK: - Destinations the on-device model can help with

/// A country we can suggest, with the language the on-device model must speak for offline help there.
struct PlanCountry: Hashable, Identifiable, Sendable {
  let name: String
  let code: String        // ISO 3166 region
  let language: String    // ISO 639 language
  var id: String { code }
}

enum PlanLanguages {
  /// Order = order of the chips. Only countries whose language the on-device model supports are shown.
  static let catalog: [PlanCountry] = [
    .init(name: "Japan", code: "JP", language: "ja"), .init(name: "Korea", code: "KR", language: "ko"),
    .init(name: "France", code: "FR", language: "fr"), .init(name: "Spain", code: "ES", language: "es"),
    .init(name: "Italy", code: "IT", language: "it"), .init(name: "Germany", code: "DE", language: "de"),
    .init(name: "Portugal", code: "PT", language: "pt"), .init(name: "Taiwan", code: "TW", language: "zh"),
    .init(name: "Mexico", code: "MX", language: "es"), .init(name: "Brazil", code: "BR", language: "pt"),
    .init(name: "Netherlands", code: "NL", language: "nl"), .init(name: "Sweden", code: "SE", language: "sv"),
    .init(name: "Denmark", code: "DK", language: "da"), .init(name: "Norway", code: "NO", language: "nb"),
    .init(name: "Turkey", code: "TR", language: "tr"), .init(name: "Vietnam", code: "VN", language: "vi"),
  ]

  /// Languages confirmed for the first on-device model, used if the system can't report its own list.
  static let fallback: Set<String> = ["ja", "ko", "zh", "fr", "de", "it", "es", "pt"]

  /// Read at runtime, so the list grows when Apple adds languages to the on-device model.
  static var supported: Set<String> {
    let codes = Set(FoundationModels.SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier })
    return codes.isEmpty ? fallback : codes
  }

  static func countries(_ supported: Set<String> = supported) -> [PlanCountry] {
    catalog.filter { supported.contains($0.language) }
  }

  /// "Japanese · Korean · …" for the info sheet.
  static func languageNames(_ supported: Set<String> = supported) -> [String] {
    let en = Locale(identifier: "en")
    return supported.filter { $0 != "en" }.sorted()
      .compactMap { en.localizedString(forLanguageCode: $0) }
  }
}

// MARK: - Brief & generated shapes

struct PlanBrief: Sendable {
  var country: PlanCountry?          // nil = "Suggest for me"
  var typed: String = ""             // free text ("somewhere warm", a city…)
  var start: Date
  /// Last day of the trip (the day you fly home). Picked on the calendar.
  var end: Date
  /// "My dates are flexible": the dates are a rough window, not fixed.
  var flexible = false
  /// How many people are going (1–9). Costs stay per person; the group total is shown too.
  var travelers = 1
  var memory: String = ""
  /// Taste words read from trip photos on this iPhone (Vision); the photos themselves never leave it.
  var photoLabels: [String] = []
  /// What the traveller wants this time ("More of that", "Something new"…).
  var want: String?
  /// What the traveler's own files say about their taste (a short gist, made from a file they added).
  var notes: [String] = []
  var dislikes: [String] = []
  var tags: MemoryTags?
  /// Most the traveller wants to spend per person for the whole trip, in US dollars. nil = no limit.
  var budget: Int?

  /// Trip length in days, counting arrival and departure days (Dec 3 → Dec 8 = 6).
  var days: Int { max(1, (TripTimeline.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1) }
  var nights: Int { max(0, days - 1) }

  /// "Dec 3 – Dec 8" or "around early Jan, flexible".
  var whenLabel: String {
    let f = Date.FormatStyle().month(.abbreviated).day()
    return flexible
      ? "around \(start.formatted(.dateTime.month(.wide))), flexible"
      : "\(start.formatted(f)) – \(end.formatted(f))"
  }

  var tasteLine: String {
    var parts: [String] = []
    if let t = tags {
      if !t.loves.isEmpty { parts.append("Loves: " + t.loves.joined(separator: ", ")) }
      if !t.avoid.isEmpty { parts.append("Avoid: " + t.avoid.joined(separator: ", ")) }
      parts.append("Pace: " + t.pace)
    } else {
      if !photoLabels.isEmpty { parts.append("Their trip photos show: " + photoLabels.joined(separator: ", ")) }
      if !dislikes.isEmpty { parts.append("Avoid: " + dislikes.joined(separator: ", ")) }
    }
    if let want { parts.append("This time they want: \(want)") }
    if !notes.isEmpty { parts.append("From their own notes: " + notes.joined(separator: "; ")) }
    let profile = Profile.tasteLine
    if !profile.isEmpty { parts.append("From their profile: " + profile) }
    return parts.joined(separator: ". ")
  }
}

/// Budget slider range, per person for the whole trip, in US dollars.
enum PlanBudget {
  static let range: ClosedRange<Double> = 500...6000
  static let step: Double = 100
  /// "$2,500"
  static func label(_ dollars: Int) -> String { "$" + dollars.formatted() }
}

@Generable
struct AvoidIdeas: Sendable {
  @Guide(description: "Exactly 5 situations this traveller would probably not enjoy on a trip, each 1 to 4 words, e.g. 'Packed tourist spots'", .count(5))
  var items: [String]
}

@Generable
struct MemoryTags: Sendable, Equatable {
  @Guide(description: "2 to 4 things the traveller loved, each 2 to 5 words, e.g. 'market breakfasts'")
  var loves: [String]
  @Guide(description: "Things to avoid, each 1 to 4 words, e.g. 'long queues'. Empty if none.")
  var avoid: [String]
  @Guide(description: "Travel pace in a few words, e.g. 'Relaxed, 2–3 stops a day'")
  var pace: String
}

@Generable
struct DestinationIdea: Sendable, Equatable {
  @Guide(description: "City name in English")
  var city: String
  @Guide(description: "Country name in English")
  var country: String
  @Guide(description: "ISO 3166-1 alpha-2 country code, e.g. JP")
  var countryCode: String
  @Guide(description: "Why it fits this traveller, max 14 words")
  var why: String
  @Guide(description: "Best neighbourhood(s) to stay in, max 6 words")
  var base: String
  @Guide(description: "Typical daytime temperature range for the travel month, like '7–14 °C'")
  var weather: String
  @Guide(description: "Rough round-trip economy flight cost per person in US dollars from the traveller's home country, as a range like '~$950–1,200'")
  var flightCost: String
  @Guide(description: "Rough cost per person of a mid-range hotel for all nights, sharing a room when there are 2 or more travelers, in US dollars, like '~$700'")
  var stayCost: String
  @Guide(description: "Rough cost of food for the whole trip per person in US dollars, like '~$300'")
  var foodCost: String
  @Guide(description: "Rough cost of sights and local transport for the whole trip in US dollars, like '~$250'")
  var seeCost: String
  @Guide(description: "Sum of the four per-person estimates as a range in US dollars, like '~$2,200–2,450'")
  var totalCost: String
  @Guide(description: "Upper end of totalCost as a whole number of US dollars, e.g. 2450")
  var totalHigh: Int
}

@Generable
struct DestinationIdeas: Sendable {
  @Guide(description: "Exactly 3 different destinations", .count(3))
  var ideas: [DestinationIdea]
}

@Generable
struct DayIdea: Sendable, Equatable {
  @Guide(description: "Short theme for the day, e.g. 'Design: Roppongi museums'")
  var title: String
  @Guide(description: "The neighbourhood the day centres on")
  var area: String
}

@Generable
struct DayOutline: Sendable {
  var days: [DayIdea]
}

// MARK: - Places (always from Google Maps grounding)

enum PlanPlaceKind: String, Sendable, CaseIterable {
  case hotel, food, sight
  var prompt: String {
    switch self {
    case .hotel: "hotels"
    case .food: "restaurants or cafés that locals rate highly"
    case .sight: "things to see or do"
    }
  }
  /// Apple Maps search words and categories (fallback when Google Maps grounding isn't available).
  var search: String {
    switch self { case .hotel: "hotel"; case .food: "restaurant"; case .sight: "sightseeing" }
  }
  var categories: [MKPointOfInterestCategory] {
    switch self {
    case .hotel: [.hotel]
    case .food: [.restaurant, .cafe, .bakery]
    case .sight: [.museum, .park, .nationalPark, .aquarium, .zoo, .theater, .amusementPark]
    }
  }
}

struct PlanPlace: Identifiable, Hashable, Sendable {
  var id: String { placeID ?? name }
  let kind: PlanPlaceKind
  let name: String
  let area: String
  let why: String
  let mapsURL: URL?
  let placeID: String?
  var day: Int?
  var rating: Double?
  var ratingCount: Int?
  var price: String?
  var latitude: Double?
  var longitude: Double?
  /// Where the place came from: "Google Maps" (grounding) or "Apple Maps" (fallback).
  var source = "Google Maps"

  var googleScore: String? {
    guard let rating else { return nil }
    let count = ratingCount.map { $0 >= 1000 ? String(format: " · %.1fk", Double($0) / 1000) : " · \($0)" } ?? ""
    return String(format: "★ %.1f", rating) + count
  }
}

/// Ratings, price and location for a Maps place ID, from the Places API (New), with the app's
/// Firebase API key. Returns nil if the Places API isn't enabled for the project; the card then
/// links to Google Maps for reviews instead of showing a score.
enum PlacesClient {
  struct Details: Decodable, Sendable {
    struct Loc: Decodable, Sendable { let latitude: Double; let longitude: Double }
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
    let location: Loc?
  }

  static func details(_ placeID: String) async -> Details? {
    let id = placeID.hasPrefix("places/") ? String(placeID.dropFirst(7)) : placeID
    guard let key = FirebaseApp.app()?.options.apiKey,
          let url = URL(string: "https://places.googleapis.com/v1/places/\(id)") else { return nil }
    var request = URLRequest(url: url)
    request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
    request.setValue("rating,userRatingCount,priceLevel,location", forHTTPHeaderField: "X-Goog-FieldMask")
    request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return try? JSONDecoder().decode(Details.self, from: data)
  }

  static func price(_ level: String?) -> String? {
    switch level {
    case "PRICE_LEVEL_INEXPENSIVE": "¥"
    case "PRICE_LEVEL_MODERATE": "¥¥"
    case "PRICE_LEVEL_EXPENSIVE": "¥¥¥"
    case "PRICE_LEVEL_VERY_EXPENSIVE": "¥¥¥¥"
    default: nil
    }
  }
}

/// The country's own review site. We have no licensed API for these scores, so we never show or
/// estimate one: the badge links to the site's search instead ("Check on Tabelog ↗").
enum LocalReviews {
  static func site(country code: String, kind: PlanPlaceKind) -> String? {
    switch (code, kind) {
    case ("JP", .food): "Tabelog"
    case ("KR", _): "Naver Map"
    case ("US", _): "Yelp"
    default: nil
    }
  }

  static func url(country code: String, kind: PlanPlaceKind, name: String, city: String) -> URL? {
    let q = "\(name) \(city)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    switch (code, kind) {
    case ("JP", .food): return URL(string: "https://tabelog.com/en/rstLst/?sw=\(q)")
    case ("KR", _): return URL(string: "https://map.naver.com/p/search/\(q)")
    case ("US", _): return URL(string: "https://www.yelp.com/search?find_desc=\(q)")
    default: return nil
    }
  }
}

// MARK: - Service

@MainActor
enum PlanService {
  static let instructions = """
    You are a travel planner. Be concise and practical. Never invent exact prices, opening hours or ratings.
    When asked for costs, give rough typical ranges, always written with "~".
    """

  /// On-device first (private): turns a memory into Loves / Avoid / Pace tags.
  static func remember(_ brief: PlanBrief, ai: AIService) async throws -> (MemoryTags, AIMeta) {
    let prompt = """
      A traveller described a trip they loved: "\(brief.memory.isEmpty ? "(no words, only photos)" : brief.memory)"
      Their trip photos show: \(brief.photoLabels.isEmpty ? "no photos given" : brief.photoLabels.joined(separator: ", ")).
      Things they did not enjoy: \(brief.dislikes.isEmpty ? "none given" : brief.dislikes.joined(separator: ", ")).
      Summarize their taste.
      """
    return try await ai.generate("Plan · remember a trip", kind: .survive, prompt: prompt,
                                 instructions: "Extract travel preferences. Use only what the traveller said and what their photos show.",
                                 as: MemoryTags.self)
  }

  /// Things this traveller would probably not enjoy, guessed from what they love (on-device first).
  /// They are only suggestions: the traveller picks, and can add their own.
  static func suggestAvoid(_ brief: PlanBrief, ai: AIService) async throws -> [String] {
    let loves = ([brief.memory] + brief.photoLabels).filter { !$0.isEmpty }.joined(separator: ", ")
    let prompt = """
      A traveller loves: \(loves.isEmpty ? "relaxed city trips" : loves).
      Suggest 5 common trip annoyances that clash with this taste, like "Packed tourist spots",
      "Long queues", "Big chains", "Early starts" or "Too much walking". Plain, everyday phrases.
      """
    let (ideas, _) = try await ai.generate("Plan · suggest dislikes", kind: .survive, prompt: prompt,
                                           instructions: "Suggest likely dislikes from someone's travel taste. Short phrases only.",
                                           as: AvoidIdeas.self)
    return ideas.items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  static func destinations(_ brief: PlanBrief, avoid: [String] = [], ai: AIService) async throws -> [DestinationIdea] {
    let allowed = PlanLanguages.countries()
    let scope: String
    if let c = brief.country {
      scope = "Suggest 3 different cities or regions in \(c.name) (country code \(c.code))."
        + (brief.typed.isEmpty ? "" : " The traveller is thinking of: \"\(brief.typed)\". Make that the first idea.")
    } else if !brief.typed.isEmpty {
      scope = "The traveller asked for: \"\(brief.typed)\". Suggest 3 matching destinations, only in these countries: \(allowed.map(\.name).joined(separator: ", "))."
    } else {
      scope = "Suggest 3 destinations in different countries, only from: \(allowed.map(\.name).joined(separator: ", "))."
    }
    let prompt = """
      \(scope)
      Trip: \(brief.days) days (\(brief.nights) nights), \(brief.whenLabel), \(brief.travelers) \(brief.travelers == 1 ? "traveler" : "travelers"). \(brief.tasteLine)
      Flying from: \(homeCountry). Budget per person for the whole trip: \(brief.budget.map(PlanBudget.label) ?? "no limit").
      \(brief.budget.map { "Only suggest places whose rough total fits under $\($0)." } ?? "")
      Estimate rough typical costs for each idea (flight, hotel, food, sights and transport).
      \(avoid.isEmpty ? "" : "Not these: \(avoid.joined(separator: ", ")).")
      """
    let (ideas, _) = try await ai.generate("Plan · destination ideas", kind: .prepare, prompt: prompt,
                                           instructions: instructions, as: DestinationIdeas.self)
    let codes = Set(allowed.map(\.code))
    return ideas.ideas.filter { codes.contains($0.countryCode.uppercased()) }
  }

  static func outline(_ brief: PlanBrief, idea: DestinationIdea, note: String = "", ai: AIService) async throws -> [DayIdea] {
    let prompt = """
      Make a rough \(brief.days)-day plan for \(idea.city), \(idea.country), \(brief.whenLabel).
      One line per day: a short theme and the neighbourhood it centres on. Day 1 is arrival, the last day is departure.
      Keep each day in one or two nearby areas. \(brief.tasteLine)
      \(note.isEmpty ? "" : "Change request: \(note)")
      Return exactly \(brief.days) days.
      """
    let (outline, _) = try await ai.generate("Plan · day outline", kind: .prepare, prompt: prompt,
                                             instructions: instructions, as: DayOutline.self)
    return Array(outline.days.prefix(brief.days))
  }

  /// Real places for a step. Google Maps grounding first; if the project can't use it (free tier:
  /// HTTP 429 / permission), Apple Maps search finds the places and Gemini only picks and explains.
  /// Either way the place itself comes from a map service, never from the model.
  static func places(_ kind: PlanPlaceKind, area: String, city: String, near: CLLocationCoordinate2D?,
                     brief: PlanBrief, avoid: [String] = [], note: String = "", day: Int? = nil,
                     ai: AIService) async throws -> [PlanPlace] {
    if groundingAvailable {
      do {
        return try await groundedPlaces(kind, area: area, city: city, near: near, brief: brief, avoid: avoid, note: note, day: day, ai: ai)
      } catch let e as GenerateContentError where Self.isUnavailable(e) {
        groundingAvailable = false   // don't retry for the rest of this run
      }
    }
    return try await mapKitPlaces(kind, area: area, city: city, near: near, brief: brief, avoid: avoid, note: note, day: day, ai: ai)
  }

  /// False after Google Maps grounding was refused once (quota / plan), so we go straight to Apple Maps.
  static var groundingAvailable = true

  static func isUnavailable(_ error: GenerateContentError) -> Bool {
    let text = String(describing: error)
    return text.contains("429") || text.contains("resourceExhausted") || text.contains("permissionDenied") || text.contains("403")
  }

  /// "near Omicho Market" → "Omicho Market", so log labels don't read "near near".
  static func trimNear(_ area: String) -> String {
    let t = area.trimmingCharacters(in: .whitespaces)
    return t.lowercased().hasPrefix("near ") ? String(t.dropFirst(5)) : t
  }

  static func groundedPlaces(_ kind: PlanPlaceKind, area: String, city: String, near: CLLocationCoordinate2D?,
                             brief: PlanBrief, avoid: [String], note: String, day: Int?,
                             ai: AIService) async throws -> [PlanPlace] {
    let prompt = """
      Find 3 \(kind.prompt) in or near \(area), \(city). \(brief.tasteLine)
      \(avoid.isEmpty ? "" : "Not these: \(avoid.joined(separator: ", ")).") \(note.isEmpty ? "" : "Request: \(note).")
      Answer with exactly 3 lines and nothing else. Each line: NAME | NEIGHBOURHOOD | why it fits, max 14 words
      """
    let (text, chunks, _) = try await ai.grounded("Plan · \(kind.rawValue) near \(Self.trimNear(area))", prompt: prompt,
                                                   instructions: instructions, near: near)
    var out: [PlanPlace] = []
    for line in text.split(separator: "\n") {
      let cols = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "*-•0123456789."))) }
      guard cols.count >= 2, let chunk = match(cols[0], in: chunks), let title = chunk.title,
            !out.contains(where: { $0.name == title }) else { continue }
      out.append(PlanPlace(kind: kind, name: title, area: cols.count > 2 ? cols[1] : area,
                           why: cols.count > 2 ? cols[2] : cols[1], mapsURL: chunk.url, placeID: chunk.placeID, day: day))
    }
    // The model answered in another format: still show the grounded places, without a "why".
    if out.isEmpty {
      for chunk in chunks.prefix(3) {
        guard let title = chunk.title, !out.contains(where: { $0.name == title }) else { continue }
        out.append(PlanPlace(kind: kind, name: title, area: area, why: "", mapsURL: chunk.url, placeID: chunk.placeID, day: day))
      }
    }
    // Scores and coordinates from the Places API, when it's enabled.
    for i in out.indices {
      guard let id = out[i].placeID, let d = await PlacesClient.details(id) else { continue }
      out[i].rating = d.rating; out[i].ratingCount = d.userRatingCount
      out[i].price = PlacesClient.price(d.priceLevel)
      out[i].latitude = d.location?.latitude; out[i].longitude = d.location?.longitude
    }
    return out
  }

  // MARK: Apple Maps fallback

  @Generable
  struct Pick: Sendable {
    @Guide(description: "Number of the place in the list")
    var number: Int
    @Guide(description: "Why it fits this traveller, max 14 words")
    var why: String
  }

  @Generable
  struct Picks: Sendable {
    @Guide(description: "The 3 best places, best first", .count(3))
    var picks: [Pick]
  }

  static func mapKitPlaces(_ kind: PlanPlaceKind, area: String, city: String, near: CLLocationCoordinate2D?,
                           brief: PlanBrief, avoid: [String], note: String, day: Int?,
                           ai: AIService) async throws -> [PlanPlace] {
    // Most specific first: the day's area, then the whole city, then without the category filter.
    let attempts: [(String, Bool)] = [("\(kind.search) \(area)", true), ("\(kind.search) \(city)", true), ("\(kind.search) \(city)", false)]
    var candidates: [MKMapItem] = []
    for (query, filtered) in attempts where candidates.count < 3 {
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = note.isEmpty ? query : "\(note) \(query)"
      request.resultTypes = .pointOfInterest
      if filtered { request.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories) }
      if let near { request.region = MKCoordinateRegion(center: near, latitudinalMeters: 20_000, longitudinalMeters: 20_000) }
      let found = ((try? await MKLocalSearch(request: request).start())?.mapItems ?? [])
        .filter { item in
          let name = item.name ?? ""
          return !name.isEmpty && !avoid.contains(name) && !candidates.contains { $0.name == name }
        }
      candidates += found
    }
    candidates = Array(candidates.prefix(12))
    guard !candidates.isEmpty else { return [] }
    let list = candidates.enumerated().map { "\($0.offset + 1). \($0.element.name ?? "")" }.joined(separator: "\n")
    let prompt = """
      Places in or near \(area), \(city) (\(kind.prompt)):
      \(list)
      Pick the 3 that best fit this traveller. \(brief.tasteLine) \(note.isEmpty ? "" : "Request: \(note).")
      """
    let (picks, _) = try await ai.generate("Plan · \(kind.rawValue) near \(area)", kind: .prepare, prompt: prompt,
                                           instructions: instructions + " Choose only from the numbered list.",
                                           as: Picks.self)
    var out: [PlanPlace] = []
    for pick in picks.picks {
      guard candidates.indices.contains(pick.number - 1) else { continue }
      let item = candidates[pick.number - 1]
      let name = item.name ?? ""
      guard !out.contains(where: { $0.name == name }) else { continue }
      out.append(PlanPlace(kind: kind, name: name, area: area, why: pick.why, mapsURL: googleMapsSearch(name, city),
                           placeID: nil, day: day, latitude: item.location.coordinate.latitude,
                           longitude: item.location.coordinate.longitude, source: "Apple Maps"))
    }
    return out
  }

  /// Opens the place in Google Maps (where its reviews are).
  static func googleMapsSearch(_ name: String, _ city: String) -> URL? {
    let q = "\(name) \(city)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    return URL(string: "https://www.google.com/maps/search/?api=1&query=\(q)")
  }

  static func match(_ name: String, in chunks: [GoogleMapsGroundingChunk]) -> GoogleMapsGroundingChunk? {
    let n = normalize(name)
    guard !n.isEmpty else { return nil }
    return chunks.first { normalize($0.title ?? "") == n }
      ?? chunks.first { let t = normalize($0.title ?? ""); return !t.isEmpty && (t.contains(n) || n.contains(t)) }
  }

  static func normalize(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
      .filter { $0.isLetter || $0.isNumber }
  }

  // MARK: Hand-off

  /// The traveller's home country, from the iPhone's region (for flight estimates).
  static var homeCountry: String {
    let code = Locale.current.region?.identifier ?? "US"
    return Locale(identifier: "en").localizedString(forRegionCode: code) ?? code
  }

  /// Booking.com search for a hotel and the trip dates; the traveller books there.
  static func hotelURL(name: String, city: String, start: Date, end: Date, adults: Int = 1) -> URL? {
    var c = URLComponents(string: "https://www.booking.com/searchresults.html")
    let day = Date.ISO8601FormatStyle().year().month().day()
    c?.queryItems = [.init(name: "ss", value: "\(name), \(city)"),
                     .init(name: "checkin", value: start.formatted(day)), .init(name: "checkout", value: end.formatted(day)),
                     .init(name: "group_adults", value: "\(adults)"), .init(name: "no_rooms", value: "1")]
    return c?.url
  }

  static func flightsURL(city: String, start: Date, adults: Int = 1) -> URL? {
    let day = start.formatted(.iso8601.year().month().day())
    let q = "Flights to \(city) on \(day) for \(adults) adult\(adults == 1 ? "" : "s")".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    return URL(string: "https://www.google.com/travel/flights?q=\(q)")
  }

  /// Saves the kept plan as suggested calendar items and map places. Suggestions never become
  /// Vault bookings; only pasted confirmations do.
  static func save(brief: PlanBrief, idea: DestinationIdea, outline: [DayIdea], stops: [Int: [DayStop]] = [:],
                   hotel: PlanPlace?, kept: [PlanPlace], context: ModelContext) async {
    let cal = TripTimeline.calendar
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
      let d = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: brief.start)) ?? brief.start
      return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
    }
    for (i, d) in outline.enumerated() {
      // A day with timed stops saves each stop; otherwise its theme at 9:00.
      guard let dayStops = stops[i], !dayStops.isEmpty else {
        context.insert(TripPlan(start: at(i, 9), title: d.title, detail: d.area, source: "suggested"))
        continue
      }
      for st in dayStops {
        let p = TripPlan(start: st.time, title: st.name, detail: st.why, source: "suggested")
        p.kind = st.kind; p.cost = st.cost; p.note = st.note; p.latitude = st.latitude; p.longitude = st.longitude
        context.insert(p)
        context.insert(Place(name: st.name, kind: "plan", latitude: st.latitude, longitude: st.longitude, address: st.address, source: "suggested"))
      }
    }
    var foodSlot: [Int: Int] = [:]
    for p in kept {
      let day = p.day ?? 0
      let date: Date
      if p.kind == .food { let n = foodSlot[day, default: 0]; foodSlot[day] = n + 1; date = n == 0 ? at(day, 12, 30) : at(day, 19) }
      else { date = at(day, 10 + 3 * kept.filter { $0.kind == .sight && $0.day == day }.firstIndex(of: p)!) }
      context.insert(TripPlan(start: date, title: p.name, detail: p.why, source: "suggested"))
    }
    let existing = Set(((try? context.fetch(FetchDescriptor<Place>())) ?? []).map(\.name))
    for p in ([hotel].compactMap { $0 } + kept) where !existing.contains(p.name) {
      var lat = p.latitude, lon = p.longitude
      if lat == nil, let hit = await MapService.search("\(p.name) \(idea.city)") { lat = hit.latitude; lon = hit.longitude }
      guard let lat, let lon else { continue }
      context.insert(Place(name: p.name, kind: "plan", latitude: lat, longitude: lon, address: p.area, source: "suggested"))
    }
    try? context.save()
  }
}

extension PlanService {
  /// The plan as shared stops for a trip room, with the same days, times and order as `save`:
  /// timed stops when a day has them, otherwise the day's theme at 9:00, then kept food (12:30,
  /// 19:00) and sights (10:00, 13:00…), and the hotel on day 1 at 15:00.
  static func sharedStops(brief: PlanBrief, outline: [DayIdea], stops: [Int: [DayStop]] = [:],
                          hotel: PlanPlace?, kept: [PlanPlace]) -> [SharedStop.Draft] {
    let cal = TripTimeline.calendar
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
      let d = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: brief.start)) ?? brief.start
      return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
    }
    var out: [SharedStop.Draft] = []
    if let hotel { out.append(.init(date: at(0, 15), title: hotel.name, detail: "Check in · \(hotel.area)", kind: "Stay",
                                    latitude: hotel.latitude, longitude: hotel.longitude)) }
    for (i, d) in outline.enumerated() {
      guard let dayStops = stops[i], !dayStops.isEmpty else {
        out.append(.init(date: at(i, 9), title: d.title, detail: d.area, kind: ""))
        continue
      }
      for st in dayStops {
        out.append(.init(date: st.time, title: st.name, detail: st.why, kind: st.kind, latitude: st.latitude, longitude: st.longitude,
                         cost: st.cost, note: st.note, address: st.address))
      }
    }
    var foodSlot: [Int: Int] = [:]
    for p in kept {
      let day = p.day ?? 0
      let date: Date
      if p.kind == .food { let n = foodSlot[day, default: 0]; foodSlot[day] = n + 1; date = n == 0 ? at(day, 12, 30) : at(day, 19) }
      else { date = at(day, 10 + 3 * (kept.filter { $0.kind == .sight && $0.day == day }.firstIndex(of: p) ?? 0)) }
      out.append(.init(date: date, title: p.name, detail: p.why, kind: p.kind == .food ? "Food" : "See",
                       latitude: p.latitude, longitude: p.longitude))
    }
    return out.sorted { $0.date < $1.date }
  }
}
