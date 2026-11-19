import Foundation
import MapKit
import SwiftData
import UIKit

/// Online, once: find coordinates for trip places and save map snapshots for offline use.
/// Offline: everything here is read from SwiftData; distances are computed, never generated.
@MainActor
enum MapService {
  enum MapError: LocalizedError {
    case noPlaces
    var errorDescription: String? { "No places with coordinates yet. Locate your hotel first (needs internet)." }
  }

  // MARK: Locate (needs internet)

  /// Looks up coordinates for the hotel(s), airports and plans that don't have a Place yet.
  @discardableResult
  static func locate(items: [VaultItem], plans: [TripPlan], context: ModelContext) async -> [Place] {
    let existing = (try? context.fetch(FetchDescriptor<Place>())) ?? []
    var known = Set(existing.map(\.name))
    var added: [Place] = []

    func add(_ name: String, kind: String, queries: [String], source: String) async {
      guard !known.contains(name) else { return }
      for q in queries where !q.isEmpty {
        if let hit = await search(q) {
          let p = Place(name: name, kind: kind, latitude: hit.latitude, longitude: hit.longitude, address: q, source: source)
          context.insert(p); added.append(p); known.insert(name)
          return
        }
      }
    }

    for item in items where item.kind == "hotel" {
      await add(item.title, kind: "hotel", queries: hotelQueries(item), source: "booking")
    }
    // Anchor = the hotel, else the trip's arrival airport. Home airports are left off the trip map.
    var anchor: CLLocationCoordinate2D? = (existing + added).first { $0.kind == "hotel" }.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    let flights = items.filter { $0.kind == "flight" }
    if anchor == nil, let arrival = flights.first?.destination, let hit = await search("\(arrival) airport") { anchor = hit }
    for item in flights {
      for code in [item.origin, item.destination].compactMap({ $0 }) where !known.contains(code) {
        guard let hit = await search("\(code) airport") else { continue }
        if let anchor, PlaceFacts.meters(anchor.latitude, anchor.longitude, hit.latitude, hit.longitude) > 100_000 { continue }
        let p = Place(name: code, kind: "airport", latitude: hit.latitude, longitude: hit.longitude, address: code, source: "booking")
        context.insert(p); added.append(p); known.insert(code)
      }
    }
    // Drop places saved earlier that are far from the trip (e.g. a home airport from an older run).
    if let anchor {
      for old in existing where PlaceFacts.meters(anchor.latitude, anchor.longitude, old.latitude, old.longitude) > 100_000 {
        context.delete(old)
      }
    }
    let hotel = (existing + added).first { $0.kind == "hotel" && !$0.isDeleted }
    for plan in plans where !plan.title.isEmpty {
      let city = hotel.map { " near \($0.address)" } ?? ""
      await add(plan.title, kind: "plan", queries: [plan.title + city, plan.title], source: "you")
    }
    try? context.save()
    return added
  }

  /// Most precise first: local-script address, English address, its neighborhood, then the hotel name.
  static func hotelQueries(_ item: VaultItem) -> [String] {
    let english = (item.address ?? "").replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
    // "4-99-1 Nishi-Shinjuku, …" → "Nishi-Shinjuku, …" (drop the street number, keep the area).
    let neighborhood = english.replacingOccurrences(of: #"^[\d\-–]+\s*"#, with: "", options: .regularExpression)
    return [item.addressLocal ?? "", english, neighborhood, item.title]
  }

  static func search(_ query: String) async -> CLLocationCoordinate2D? {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    guard let response = try? await MKLocalSearch(request: request).start(),
          let item = response.mapItems.first else { return nil }
    return item.location.coordinate
  }

  // MARK: Download (needs internet)

  /// Saves two areas — around the hotel and the whole trip — in Day and Night.
  static func download(places: [Place], context: ModelContext) async throws -> [MapPack] {
    guard !places.isEmpty else { throw MapError.noPlaces }
    for old in (try? context.fetch(FetchDescriptor<MapPack>())) ?? [] { context.delete(old) }

    var areas: [(String, MKCoordinateRegion)] = []
    if let hotel = places.first(where: { $0.kind == "hotel" }) {
      areas.append(("Around your hotel", MKCoordinateRegion(
        center: .init(latitude: hotel.latitude, longitude: hotel.longitude),
        latitudinalMeters: 3000, longitudinalMeters: 3000)))
    }
    let anchor = places.first { $0.kind == "hotel" } ?? places[0]
    let local = places.filter { PlaceFacts.meters(anchor.latitude, anchor.longitude, $0.latitude, $0.longitude) < 60_000 }
    if local.count > 1 || areas.isEmpty { areas.append(("Whole trip", region(fitting: local))) }

    var packs: [MapPack] = []
    for (name, region) in areas {
      let day = try await snapshot(region, style: .light)
      let night = try await snapshot(region, style: .dark)
      // Store the span the snapshot really covers (MapKit widens it to fit the square image).
      let pack = MapPack(name: name, centerLatitude: region.center.latitude, centerLongitude: region.center.longitude,
                         spanLatitude: day.spanLat, spanLongitude: day.spanLon)
      pack.dayImage = day.data
      pack.nightImage = night.data
      context.insert(pack); packs.append(pack)
    }
    try? context.save()
    return packs
  }

  static func region(fitting places: [Place]) -> MKCoordinateRegion {
    let lats = places.map(\.latitude), lons = places.map(\.longitude)
    let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
    // Clamp to a valid, city-sized region (MapKit throws on invalid spans).
    let span = MKCoordinateSpan(latitudeDelta: min(1.5, max(0.03, (lats.max()! - lats.min()!) * 1.4)),
                                longitudeDelta: min(1.5, max(0.03, (lons.max()! - lons.min()!) * 1.4)))
    return MKCoordinateRegion(center: center, span: span)
  }

  private static func snapshot(_ region: MKCoordinateRegion, style: UIUserInterfaceStyle) async throws
    -> (data: Data?, spanLat: Double, spanLon: Double) {
    let o = MKMapSnapshotter.Options()
    o.region = region
    o.size = CGSize(width: 700, height: 700)
    o.traitCollection = UITraitCollection(userInterfaceStyle: style)
    o.pointOfInterestFilter = .includingAll
    let shot = try await MKMapSnapshotter(options: o).start()
    // Measure pixels per degree around the center to recover the exact covered span.
    let c = region.center, d = 0.005
    let w = shot.point(for: .init(latitude: c.latitude, longitude: c.longitude - d))
    let e = shot.point(for: .init(latitude: c.latitude, longitude: c.longitude + d))
    let n = shot.point(for: .init(latitude: c.latitude + d, longitude: c.longitude))
    let s = shot.point(for: .init(latitude: c.latitude - d, longitude: c.longitude))
    let spanLon = o.size.width / ((e.x - w.x) / (2 * d))
    let spanLat = o.size.height / ((s.y - n.y) / (2 * d))
    return (shot.image.jpegData(compressionQuality: 0.8), spanLat, spanLon)
  }
}

// MARK: - Offline math (pure, testable)

enum MapProjection {
  /// Position of a coordinate inside a snapshot of `size` (equirectangular, fine for city-sized areas).
  static func point(lat: Double, lon: Double, centerLat: Double, centerLon: Double,
                    spanLat: Double, spanLon: Double, size: CGSize) -> CGPoint {
    let x = (lon - (centerLon - spanLon / 2)) / spanLon * size.width
    let y = ((centerLat + spanLat / 2) - lat) / spanLat * size.height
    return CGPoint(x: x, y: y)
  }

  static func contains(lat: Double, lon: Double, centerLat: Double, centerLon: Double, spanLat: Double, spanLon: Double) -> Bool {
    abs(lat - centerLat) <= spanLat / 2 && abs(lon - centerLon) <= spanLon / 2
  }
}

/// Distance and a rough travel time between two points. Computed, never generated.
enum PlaceFacts {
  static func meters(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
    CLLocation(latitude: aLat, longitude: aLon).distance(from: CLLocation(latitude: bLat, longitude: bLon))
  }

  static func distance(_ m: Double) -> String {
    m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000)
  }

  /// Walk under 1.5 km (80 m/min, straight-line × 1.3); otherwise taxi at ~20 km/h in the city.
  static func estimate(_ m: Double) -> String {
    let road = m * 1.3
    if m < 1500 { return "about \(max(1, Int((road / 80).rounded()))) min walk" }
    return "about \(max(5, Int((road / 1000 / 20 * 60).rounded()))) min by taxi"
  }
}
