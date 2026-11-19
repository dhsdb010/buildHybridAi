import Foundation
import Testing
@testable import TravelCopilot

struct TripProgressTests {
  let start = Date(timeIntervalSince1970: 1_000_000)

  @Test func statesFollowTheClock() {
    #expect(TripProgress.of(start: start, now: start.addingTimeInterval(-4 * 3600), isNext: true) == .later)
    #expect(TripProgress.of(start: start, now: start.addingTimeInterval(-2 * 3600), isNext: true) == .next)
    #expect(TripProgress.of(start: start, now: start.addingTimeInterval(-2 * 3600), isNext: false) == .later)
    #expect(TripProgress.of(start: start, now: start.addingTimeInterval(-25 * 60), isNext: true) == .soon)
    #expect(TripProgress.of(start: start, now: start.addingTimeInterval(10 * 60), isNext: false) == .now)
    #expect(TripProgress.of(start: start, now: start.addingTimeInterval(2 * 3600), isNext: false) == .done)
    // Ends when the next moment starts
    #expect(TripProgress.of(start: start, end: start.addingTimeInterval(1800), now: start.addingTimeInterval(1900), isNext: false) == .done)
  }

  @Test func countdownText() {
    #expect(TripProgress.countdown(to: start, now: start.addingTimeInterval(-25 * 60)) == "in 25 min")
    #expect(TripProgress.countdown(to: start, now: start.addingTimeInterval(-80 * 60)) == "in 1 h 20 min")
    #expect(TripProgress.countdown(to: start, now: start.addingTimeInterval(-3 * 3600)) == "in 3 h")
    #expect(TripProgress.soon.label(start: start, now: start.addingTimeInterval(-25 * 60)) == "In 25 min")
  }

  @Test @MainActor func liveActivityPicksNowOrNextWithinEightHours() {
    func ev(_ id: String, _ offset: TimeInterval) -> TripEvent {
      TripEvent(id: id, date: start.addingTimeInterval(offset), kind: .plan, title: id, detail: "", itemID: nil, planSource: "user")
    }
    let events = [ev("a", -3 * 3600), ev("b", 2 * 3600), ev("c", 10 * 3600)]
    #expect(TripReminders.current(events, now: start)?.0.id == "b")
    #expect(TripReminders.current([ev("far", 9 * 3600)], now: start) == nil)
    #expect(TripReminders.current([ev("on", -10 * 60)], now: start)?.1 == .now)
  }
}
