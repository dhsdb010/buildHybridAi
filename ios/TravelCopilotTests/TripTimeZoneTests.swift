import Foundation
import Testing
@testable import TravelCopilot

struct TripTimeZoneTests {
  @Test func airportsFromBookingText() {
    #expect(TripTimeZones.airport("San Francisco (SFO)") == "America/Los_Angeles")
    #expect(TripTimeZones.airport("Tokyo Haneda (HND)") == "Asia/Tokyo")
    #expect(TripTimeZones.airport("HND") == "Asia/Tokyo")
    #expect(TripTimeZones.airport("Somewhere") == nil)
    #expect(TripTimeZones.country("jp") == "Asia/Tokyo")
    #expect(TripTimeZones.country("US") == nil)   // several zones: left to the phone
  }

  @Test func arrivalIsTheRealMomentInTokyo() {
    let wall = TripTimeline.date("2026-12-03", "15:55")!
    let real = TripTimeZones.instant(wall, in: "Asia/Tokyo")
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    let c = utc.dateComponents([.day, .hour, .minute], from: real)
    #expect(c.day == 3 && c.hour == 6 && c.minute == 55)   // 15:55 JST = 06:55 UTC
  }

  @MainActor @Test func eventsKeepTheWrittenTimeForDisplay() {
    let f = VaultItem(kind: "flight", title: "EA 061")
    f.startDate = "2026-12-02"; f.departureTime = "11:40"; f.arrivalTime = "15:55"; f.endDate = "2026-12-03"
    f.origin = "San Francisco (SFO)"; f.destination = "Tokyo Haneda (HND)"
    let events = TripTimeline.events(items: [f], plans: [])
    let arr = events.first { $0.kind == .arrive }!
    #expect(arr.timeZone == "Asia/Tokyo")
    #expect(TripTimeline.time(arr.atInstant.clock) == "15:55")
    #expect(events.first { $0.kind == .depart }?.timeZone == "America/Los_Angeles")
  }
}
