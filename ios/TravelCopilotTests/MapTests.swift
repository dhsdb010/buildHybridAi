import Testing
import Foundation
import CoreGraphics
@testable import TravelCopilot

struct MapProjectionTests {
  @Test func centerMapsToMiddleAndCornersToEdges() {
    let size = CGSize(width: 700, height: 700)
    let c = MapProjection.point(lat: 35.69, lon: 139.69, centerLat: 35.69, centerLon: 139.69, spanLat: 0.02, spanLon: 0.03, size: size)
    #expect(abs(c.x - 350) < 0.01 && abs(c.y - 350) < 0.01)
    let nw = MapProjection.point(lat: 35.70, lon: 139.675, centerLat: 35.69, centerLon: 139.69, spanLat: 0.02, spanLon: 0.03, size: size)
    #expect(abs(nw.x) < 0.01 && abs(nw.y) < 0.01) // north-west corner = top-left
  }

  @Test func containsOnlyInsideRegion() {
    #expect(MapProjection.contains(lat: 35.695, lon: 139.70, centerLat: 35.69, centerLon: 139.69, spanLat: 0.02, spanLon: 0.03))
    #expect(!MapProjection.contains(lat: 35.75, lon: 139.69, centerLat: 35.69, centerLon: 139.69, spanLat: 0.02, spanLon: 0.03))
  }
}

struct PlaceFactsTests {
  @Test func shortDistancesAreWalks() {
    #expect(PlaceFacts.distance(643) == "640 m")
    #expect(PlaceFacts.estimate(643) == "about 10 min walk")
  }

  @Test func longDistancesAreTaxiRides() {
    #expect(PlaceFacts.distance(6100) == "6.1 km")
    #expect(PlaceFacts.estimate(6100) == "about 24 min by taxi")
  }
}

@MainActor
struct PlaceAnswerTests {
  @Test func distanceIsFromHotelAndComputed() throws {
    let hotel = Place(name: "Hotel Hoshizora", kind: "hotel", latitude: 35.6895, longitude: 139.6917)
    let plan = Place(name: "teamLab Planets", kind: "plan", latitude: 35.6491, longitude: 139.7898, source: "you")
    let a = try #require(PlaceAnswerBuilder.answer(plan, places: [hotel, plan], here: nil))
    #expect(a.from == "Hotel Hoshizora")
    #expect(a.distance.hasSuffix("km"))
    #expect(a.text.contains("teamLab Planets") && a.text.contains("taxi"))
  }

  @Test func hotelDistanceNeedsYourPosition() {
    let hotel = Place(name: "Hotel Hoshizora", kind: "hotel", latitude: 35.6895, longitude: 139.6917)
    #expect(PlaceAnswerBuilder.answer(hotel, places: [hotel], here: nil) == nil)
    #expect(PlaceAnswerBuilder.answer(hotel, places: [hotel], here: (35.6900, 139.6950))?.from == "you")
  }
}

@MainActor
struct MapRegionTests {
  @Test func farApartPlacesStillGiveAValidRegion() {
    let sfo = Place(name: "SFO", kind: "airport", latitude: 37.62, longitude: -122.38)
    let hnd = Place(name: "HND", kind: "airport", latitude: 35.55, longitude: 139.78)
    let r = MapService.region(fitting: [sfo, hnd])
    #expect(r.span.latitudeDelta <= 1.5 && r.span.longitudeDelta <= 1.5) // MapKit rejects spans > 180°
  }
}

@MainActor
struct HotelQueryTests {
  @Test func fallsBackFromExactAddressToNeighborhood() {
    let h = VaultItem(kind: "hotel", title: "Hotel Hoshizora Shinjuku")
    h.address = "4-99-1 Nishi-Shinjuku, Shinjuku-ku, Tokyo 160-0023, Japan (fictional)"
    h.addressLocal = "東京都新宿区西新宿4-99-1"
    #expect(MapService.hotelQueries(h) == [
      "東京都新宿区西新宿4-99-1",
      "4-99-1 Nishi-Shinjuku, Shinjuku-ku, Tokyo 160-0023, Japan",
      "Nishi-Shinjuku, Shinjuku-ku, Tokyo 160-0023, Japan",
      "Hotel Hoshizora Shinjuku",
    ])
  }
}
