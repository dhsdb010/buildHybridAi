import Foundation
import Testing
@testable import TravelCopilot

struct JourneyTests {
  let t0 = Date(timeIntervalSince1970: 2_000_000)
  func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

  var events: [TripEvent] {
    [
      TripEvent(id: "land", date: at(-40), kind: .arrive, title: "Land at Narita", detail: "", itemID: nil, planSource: nil, vehicle: "flight"),
      TripEvent(id: "train", date: at(18), kind: .depart, title: "Narita → Shinjuku", detail: "Narita Express · Car 8",
                itemID: nil, planSource: nil, vehicle: "train"),
      TripEvent(id: "bus", date: at(42), kind: .plan, title: "Bus 61 → Nishi-Shinjuku", detail: "", itemID: nil, planSource: "user"),
      TripEvent(id: "walk", date: at(64), kind: .plan, title: "Walk to the hotel", detail: "", itemID: nil, planSource: "user"),
      TripEvent(id: "in", date: at(72), kind: .checkIn, title: "Check in · Hotel", detail: "Ref HSZ-48213", itemID: nil, planSource: nil),
    ]
  }

  @Test func stepsLeadToTheGoal() throws {
    let j = try #require(Journey.current(events, now: t0, done: []))
    #expect(j.goal.id == "in")
    #expect(j.steps.map(\.mode) == [.train, .bus, .walk])
    // One segment per step; the last step ends at the goal.
    #expect(j.stops == ["Narita", "Shinjuku", "Nishi-Shinjuku", "Hotel"])
    #expect(j.current == 0)
  }

  @Test func moveOnByTimeOrDone() throws {
    #expect(Journey.current(events, now: at(45), done: [])?.current == 1)          // train time passed → bus
    #expect(Journey.current(events, now: at(5), done: ["train"])?.current == 1)    // Done tapped
    #expect(Journey.current(events, now: at(68), done: [])?.current == 2)          // walking: lasts until check-in
    #expect(Journey.current(events, now: at(68), done: ["walk"])?.current == 3)    // walk done → arriving
    #expect(Journey.current(events, now: at(110), done: [])?.current == nil)       // arrived card
    #expect(Journey.current(events, now: at(72 + 130), done: []) == nil)           // gone after 2 h
  }

  @Test func modesFromPlanWords() {
    func plan(_ t: String) -> TripEvent { TripEvent(id: t, date: t0, kind: .plan, title: t, detail: "", itemID: nil, planSource: "user") }
    #expect(JourneyMode.of(plan("Bike to the park")) == .cycle)
    #expect(JourneyMode.of(plan("Taxi to dinner")) == .taxi)
    #expect(JourneyMode.of(plan("Ramen lunch")) == .place)
    #expect(JourneyMode.train.card.glyph == "tram.card.fill")
  }

  @Test @MainActor func liveActivityStateForBusStep() throws {
    let j = try #require(Journey.current(events, now: at(45), done: []))
    let s = TripReminders.journeyState(j, place: "Tokyo", now: at(45), events: events)
    #expect(s.title == "Bus 61")
    #expect(s.label == "To Hotel · Step 2 of 3")
    #expect(s.segment == 1 && s.glyph == "bus.fill" && s.cardLabel == "Bus card")
    #expect(s.ref == "HSZ-48213")
  }
}
