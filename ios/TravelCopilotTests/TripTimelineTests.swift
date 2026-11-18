import Testing
import Foundation
@testable import TravelCopilot

@MainActor
struct TripTimelineTests {
  private func sample() -> [VaultItem] {
    let f = VaultItem(kind: "flight", title: "EA 061")
    f.startDate = "2026-12-02"; f.departureTime = "11:40"; f.endDate = "2026-12-03"; f.arrivalTime = "15:55"
    f.origin = "SFO"; f.destination = "HND"; f.confirmationCode = "QX7P2L"
    let h = VaultItem(kind: "hotel", title: "Hotel Hoshizora")
    h.startDate = "2026-12-03"; h.checkInTime = "15:00"; h.endDate = "2026-12-07"; h.checkOutTime = "11:00"
    return [f, h]
  }

  @Test func eventsComeOnlyFromStoredFieldsInOrder() {
    let e = TripTimeline.events(items: sample(), plans: [])
    #expect(e.map(\.kind) == [.depart, .checkIn, .arrive, .checkOut])
    #expect(TripTimeline.time(e[0].date) == "11:40")
    #expect(e[0].title == "SFO → HND")
  }

  @Test func rangeCoversFirstToLastBookedDay() throws {
    let e = TripTimeline.events(items: sample(), plans: [])
    let r = try #require(TripTimeline.range(e))
    #expect(TripTimeline.days(in: r).count == 6) // Dec 2 … Dec 7
  }

  @Test func plansJoinTheirDay() {
    let day = TripTimeline.date("2026-12-04", "13:00")!
    let e = TripTimeline.events(items: sample(), plans: [TripPlan(start: day, title: "teamLab")])
    #expect(TripTimeline.events(on: day, e).map(\.title) == ["teamLab"])
  }

  @Test func timeIsAlways24Hour() {
    #expect(TripTimeline.time(TripTimeline.date("2026-12-07", "23:05")!) == "23:05")
  }

  @Test func calendarWeekStartsMonday() {
    #expect(TripTimeline.calendar.firstWeekday == 2)
  }
}
