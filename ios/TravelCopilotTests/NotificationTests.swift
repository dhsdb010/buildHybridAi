import Foundation
import Testing
@testable import TravelCopilot

@MainActor
struct NotificationTests {
  let t0 = Date(timeIntervalSince1970: 2_000_000)
  func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

  var events: [TripEvent] {
    [
      TripEvent(id: "land", date: at(-40), kind: .arrive, title: "Land at Narita", detail: "", itemID: nil, planSource: nil, vehicle: "flight"),
      TripEvent(id: "train", date: at(18), kind: .depart, title: "Narita → Shinjuku", detail: "Narita Express · Car 8",
                itemID: nil, planSource: nil, vehicle: "train"),
      TripEvent(id: "bus", date: at(42), kind: .plan, title: "Bus 61 → Nishi-Shinjuku", detail: "Stop B4", itemID: nil, planSource: "user"),
      TripEvent(id: "walk", date: at(64), kind: .plan, title: "Walk to the hotel", detail: "4 min walk", itemID: nil, planSource: "user"),
      TripEvent(id: "in", date: at(72), kind: .checkIn, title: "Check in · Hotel Hoshizora", detail: "Ref HSZ-48213", itemID: nil, planSource: nil),
    ]
  }

  private func step(_ id: String) throws -> TripReminders.Reminder {
    let j = try #require(Journey.current(events, now: t0, done: []))
    let i = try #require(j.all.firstIndex { $0.event.id == id })
    return TripReminders.reminder(j.all[i].event, journey: (j, i, j.steps.count))
  }

  @Test func journeyStepReadsLikeAStationSign() throws {
    let bus = try step("bus")
    #expect(bus.title.hasPrefix("Step 2 of 3 · Bus 61 at "))
    #expect(bus.body == "Stop B4 · To Nishi-Shinjuku")
    #expect(bus.category == "journey-bus")
    #expect(bus.lead == 10 * 60)
    #expect(bus.userInfo["stepID"] == "bus")
    #expect(try step("train").title.hasPrefix("Step 1 of 3 · Narita Express at "))
    #expect(try step("train").body == "Car 8 · To Shinjuku")
    #expect(try step("walk").body == "4 min walk · To Hotel, then check in")
  }

  @Test func goalOffersTheBooking() throws {
    let goal = try step("in")
    #expect(goal.title.hasPrefix("Check in at "))
    #expect(goal.title.hasSuffix("· Hotel Hoshizora"))
    #expect(goal.category == "journey-hotel")
  }

  @Test func aTrainOnItsOwnIsNotAnAirportAlert() {
    let train = TripEvent(id: "t", date: t0, kind: .depart, title: "Tokyo → Kyoto", detail: "Nozomi 21",
                          itemID: nil, planSource: nil, vehicle: "train")
    #expect(!TripReminders.reminder(train, journey: nil).title.contains("airport"))
    let flight = TripEvent(id: "f", date: t0, kind: .depart, title: "SFO → HND", detail: "EA 061",
                           itemID: nil, planSource: nil, vehicle: "flight")
    #expect(TripReminders.reminder(flight, journey: nil).title.hasPrefix("Leave for the airport"))
  }

  @Test func actionsLeadToTheRightPlace() {
    let info: [AnyHashable: Any] = ["stepID": "bus", "card": "travelcopilot://trip", "ask": "About Bus 61: "]
    #expect(NotificationActions.target(action: "done", info: info) == .done("bus"))
    #expect(NotificationActions.target(action: "card", info: info) == .open(URL(string: "travelcopilot://trip")!))
    guard case let .open(url) = NotificationActions.target(action: "ask", info: info) else { Issue.record("ask"); return }
    #expect(url.absoluteString == "travelcopilot://ask?q=About%20Bus%2061:%20")
    #expect(NotificationActions.target(action: "com.apple.UNNotificationDefaultActionIdentifier", info: info)
            == .open(URL(string: "travelcopilot://trip")!))
    #expect(NotificationActions.target(action: "com.apple.UNNotificationDefaultActionIdentifier", info: [:]) == .home)
  }

  @Test func askLinkOpensBlueWithTheStep() {
    let router = AppRouter()
    #expect(router.open(URL(string: "travelcopilot://ask?q=About%20Bus%2061:%20")!))
    #expect(router.ask?.text == "About Bus 61: ")
    #expect(router.ask?.autoSubmit == false)
  }
}
