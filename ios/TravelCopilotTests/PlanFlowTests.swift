import Foundation
import Testing
@testable import TravelCopilot

struct PlanFlowTests {
  func day(_ s: String) -> Date { TripTimeline.date(s, "00:00")! }

  @Test func tripLengthCountsArrivalAndDeparture() {
    let b = PlanBrief(start: day("2026-12-03"), end: day("2026-12-08"))
    #expect(b.days == 6)
    #expect(b.nights == 5)
    #expect(b.whenLabel == "Dec 3 – Dec 8")
  }

  @Test func flexibleDatesSayAround() {
    var b = PlanBrief(start: day("2026-12-03"), end: day("2026-12-08"))
    b.flexible = true
    #expect(b.whenLabel == "around December, flexible")
  }

  @Test func budgetLabel() {
    #expect(PlanBudget.label(2500) == "$2,500")
    #expect(PlanBudget.range.contains(2500))
  }

  @Test func photoWordsGoIntoTheTaste() {
    var b = PlanBrief(start: day("2026-12-03"), end: day("2026-12-08"))
    b.photoLabels = ["Street food", "Market"]
    b.want = "More of that"
    #expect(b.tasteLine.contains("Their trip photos show: Street food, Market"))
    #expect(b.tasteLine.contains("This time they want: More of that"))
  }

  @Test func photoLabelsMostCommonFirst() {
    let words = PhotoTaste.summarize([
      [("street_food", 0.9), ("market", 0.6)],
      [("market", 0.8), ("temple", 0.5)],
      [("market", 0.7), ("street_food", 0.4)],
    ])
    #expect(words.prefix(2) == ["Market", "Street food"])
    #expect(PhotoTaste.word("old_town") == "Old town")
  }

  @Test @MainActor func bookingLinksCarryTheGroupSize() {
    let start = day("2026-12-03"), end = day("2026-12-08")
    let hotel = PlanService.hotelURL(name: "Hotel X", city: "Tokyo", start: start, end: end, adults: 2)!.absoluteString
    #expect(hotel.contains("group_adults=2"))
    #expect(hotel.contains("checkin=2026-12-03"))
    #expect(PlanService.flightsURL(city: "Tokyo", start: start, adults: 2)!.absoluteString.contains("2%20adults"))
  }

  @Test @MainActor func stopTimesAndLegs() {
    let d = day("2026-12-04")
    let t = DayStops.at("14:30", on: d)
    #expect(TripTimeline.time(t) == "14:30")
    let a = DayStop(time: t, kind: "See", name: "A", why: "", address: "", latitude: 33.5902, longitude: 130.4017, cost: 7)
    var b = a; b.latitude = 33.5952                          // ~0.55 km north
    #expect(DayStops.leg(a, b).hasSuffix("min walk"))
    var c = a; c.latitude = 33.6302                          // ~4.4 km north
    #expect(DayStops.leg(a, c).hasSuffix("min by taxi"))
  }
}
