import CoreLocation
import Foundation
import FoundationModels
import MapKit

/// One timed stop in a day plan. The place itself (name, address, coordinates) comes from
/// Apple Maps; the model only proposes what to look for, when, why and a rough cost.
struct DayStop: Identifiable, Hashable, Sendable {
  var id = UUID()
  var time: Date
  var kind: String          // Market · Food · See · Shop · Café · Walk
  var name: String
  var why: String
  var address: String
  var latitude: Double
  var longitude: Double
  /// Rough cost per person in US dollars (an estimate, editable).
  var cost: Int
  var note = ""

  var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

@Generable
struct DayStopIdea: Sendable {
  @Guide(description: "Start time, 24-hour HH:mm, e.g. 10:00")
  var time: String
  @Guide(description: "One word: Market, Food, Café, See, Shop or Walk")
  var kind: String
  @Guide(description: "A real, well-known place to search for on a map, with its usual name, e.g. 'Yanagibashi Market'")
  var place: String
  @Guide(description: "Why it fits this traveler, max 14 words")
  var why: String
  @Guide(description: "Rough cost per person in US dollars as a whole number, 0 if free")
  var cost: Int
}

@Generable
struct DayStopIdeas: Sendable {
  @Guide(description: "3 or 4 stops in time order, close to each other", .count(4))
  var stops: [DayStopIdea]
}

@MainActor
enum DayStops {
  /// Timed stops for one day: Gemini proposes, Apple Maps finds the real place. Stops Maps
  /// can't find, or that are far from the city, are dropped rather than shown as made up.
  static func make(day: Int, title: String, area: String, city: String, date: Date,
                   near center: CLLocationCoordinate2D?, brief: PlanBrief, ai: AIService) async throws -> [DayStop] {
    let prompt = """
      Day \(day + 1) of a trip to \(city): "\(title)", around \(area).
      Plan 4 stops from morning to evening, close together, that fit this traveler. \(brief.tasteLine)
      Use places that really exist and are easy to find on a map.
      """
    let (ideas, _) = try await ai.generate("Plan · day \(day + 1) stops", kind: .prepare, prompt: prompt,
                                           instructions: PlanService.instructions, as: DayStopIdeas.self)
    var out: [DayStop] = []
    for idea in ideas.stops {
      // Search the place itself, not the neighbourhood (which Maps would return as a street).
      var found = await find("\(idea.place), \(city)", near: center, placesOnly: true)
      if found == nil { found = await find("\(idea.place) \(area)", near: center, placesOnly: true) }
      guard let hit = found else { continue }
      // The same real place twice is one stop.
      if out.contains(where: { PlaceFacts.meters($0.latitude, $0.longitude, hit.coordinate.latitude, hit.coordinate.longitude) < 60 }) { continue }
      out.append(DayStop(time: at(idea.time, on: date), kind: idea.kind.capitalized, name: hit.name ?? idea.place,
                         why: idea.why, address: hit.address, latitude: hit.coordinate.latitude,
                         longitude: hit.coordinate.longitude, cost: max(0, idea.cost)))
    }
    return out.sorted { $0.time < $1.time }
  }

  /// A real place from Apple Maps, within 40 km of the city.
  static func find(_ query: String, near center: CLLocationCoordinate2D?, placesOnly: Bool = false) async -> (name: String?, address: String, coordinate: CLLocationCoordinate2D)? {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    if placesOnly { request.resultTypes = .pointOfInterest }
    if let center { request.region = MKCoordinateRegion(center: center, latitudinalMeters: 30_000, longitudinalMeters: 30_000) }
    guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
    let c = item.location.coordinate
    if let center, PlaceFacts.meters(center.latitude, center.longitude, c.latitude, c.longitude) > 40_000 { return nil }
    return (item.name, item.address?.shortAddress ?? item.address?.fullAddress ?? "", c)
  }

  /// One Apple Maps search result for Add a stop.
  struct Hit: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let symbol: String   // SF Symbol for the kind of place
    let kind: String     // "Food", "See", "Stay", "Shop" or "Stop"
    let label: String    // "Landmark", "Hotel", "Café"…
    var item: MKMapItem? = nil
    static func == (a: Hit, b: Hit) -> Bool { a.id == b.id }
  }

  /// Up to 8 places matching what's typed, near the day's stops (or in the city), like Apple Maps search.
  static func search(_ query: String, city: String, near center: CLLocationCoordinate2D?) async -> [Hit] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 2 else { return [] }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = center == nil && !city.isEmpty ? "\(q), \(city)" : q
    request.resultTypes = [.pointOfInterest, .address]
    if let center { request.region = MKCoordinateRegion(center: center, latitudinalMeters: 30_000, longitudinalMeters: 30_000) }
    guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
    return items.compactMap { item -> Hit? in
      let c = item.location.coordinate
      if let center, PlaceFacts.meters(center.latitude, center.longitude, c.latitude, c.longitude) > 40_000 { return nil }
      let (symbol, kind, label) = style(item.pointOfInterestCategory)
      return Hit(name: item.name ?? q, address: item.address?.shortAddress ?? item.address?.fullAddress ?? "",
                 coordinate: c, symbol: symbol, kind: kind, label: label, item: item)
    }
    .prefix(8).map { $0 }
  }

  /// An icon, a stop kind and a plain label for an Apple Maps category.
  static func style(_ c: MKPointOfInterestCategory?) -> (symbol: String, kind: String, label: String) {
    switch c {
    case .restaurant?: return ("fork.knife", "Food", "Restaurant")
    case .foodMarket?: return ("basket", "Food", "Food market")
    case .bakery?: return ("birthday.cake", "Food", "Bakery")
    case .cafe?: return ("cup.and.saucer", "Food", "Café")
    case .nightlife?, .brewery?, .winery?: return ("wineglass", "Food", "Bar")
    case .hotel?: return ("bed.double", "Stay", "Hotel")
    case .museum?: return ("building.columns", "See", "Museum")
    case .library?: return ("books.vertical", "See", "Library")
    case .park?, .nationalPark?: return ("tree", "See", "Park")
    case .beach?: return ("beach.umbrella", "See", "Beach")
    case .amusementPark?: return ("ticket", "See", "Amusement park")
    case .aquarium?: return ("fish", "See", "Aquarium")
    case .zoo?: return ("pawprint", "See", "Zoo")
    case .theater?, .movieTheater?: return ("theatermasks", "See", "Theater")
    case .stadium?: return ("sportscourt", "See", "Stadium")
    case .landmark?, .castle?, .fortress?: return ("building.2", "See", "Landmark")
    case .store?: return ("bag", "Shop", "Shop")
    case .airport?: return ("airplane", "Stop", "Airport")
    case .publicTransport?: return ("tram", "Stop", "Station")
    case nil: return ("mappin", "Stop", "Place")
    default: return ("mappin", "Stop", "Place")
    }
  }

  /// "400 m", "1.2 km".
  static func distance(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> String? {
    guard let a else { return nil }
    let m = PlaceFacts.meters(a.latitude, a.longitude, b.latitude, b.longitude)
    return m < 1000 ? "\(max(50, Int((m / 50).rounded()) * 50)) m" : String(format: "%.1f km", m / 1000)
  }

  static func at(_ hhmm: String, on day: Date) -> Date {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    let cal = TripTimeline.calendar
    return cal.date(bySettingHour: min(max(parts.first ?? 10, 6), 23), minute: parts.count > 1 ? parts[1] : 0,
                    second: 0, of: day) ?? day
  }

  /// "0.9 km · 12 min walk", or by taxi when it's further than a comfortable walk.
  static func leg(_ a: DayStop, _ b: DayStop) -> String {
    let m = PlaceFacts.meters(a.latitude, a.longitude, b.latitude, b.longitude) * 1.3   // streets aren't straight
    let km = m / 1000
    let dist = km < 1 ? "\(Int((m / 50).rounded()) * 50) m" : String(format: "%.1f km", km)
    if km <= 1.5 { return "\(dist) · \(max(1, Int((km / 4.5 * 60).rounded()))) min walk" }
    return "\(dist) · \(max(3, Int((km / 22 * 60).rounded()))) min by taxi"
  }
}

/// A photo for a destination: the lead image of its English Wikipedia article (no key needed).
/// Only the city name is sent.
@MainActor
enum CityPhoto {
  private static var cache: [String: URL] = [:]

  @MainActor
  static func url(for city: String, country: String) async -> URL? {
    if let u = cache[city] { return u }
    for title in [city, "\(city), \(country)"] {
      let path = title.replacingOccurrences(of: " ", with: "_")
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
      guard let api = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)") else { continue }
      struct Summary: Decodable { struct Img: Decodable { let source: String }; let thumbnail: Img?; let originalimage: Img? }
      guard let (data, r) = try? await URLSession.shared.data(from: api), (r as? HTTPURLResponse)?.statusCode == 200,
            let s = try? JSONDecoder().decode(Summary.self, from: data),
            let src = (s.thumbnail ?? s.originalimage)?.source, let u = URL(string: src.replacingOccurrences(of: "/320px-", with: "/800px-")) else { continue }
      cache[city] = u
      return u
    }
    return nil
  }
}
