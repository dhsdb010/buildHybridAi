import Foundation
import SwiftData
import Testing
@testable import TravelCopilot

/// Blue's question test set: real questions against the real on-device model, scored by what Blue
/// would actually show. Slow (a few seconds per question) and needs Apple Intelligence, so it only
/// runs when asked:
///
///     TEST_RUNNER_BLUE_EVAL=1 xcodebuild test … -only-testing:TravelCopilotTests/BlueEvalTests
///
/// Each line of the report starts with `BLUE_EVAL|` so it's easy to pull out of the test log.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BLUE_EVAL"] == "1"), .serialized)
struct BlueEvalTests {
  /// What Blue should show for a question.
  enum Expect: CustomStringConvertible {
    /// A stored field of a booking ("hotel" / "flight"). Several fields can be acceptable.
    case field(String, [VaultField])
    /// A distance to this saved place.
    case place(String)
    /// Help reply or "not in your bookings": anything but a booking value.
    case noValue

    var description: String {
      switch self {
      case let .field(kind, f): "\(kind).\(f.map(\.rawValue).joined(separator: "|"))"
      case let .place(name): "place:\(name)"
      case .noValue: "no value"
      }
    }
  }

  struct Case { let q: String; let expect: Expect; let group: String }

  static let cases: [Case] = [
    // Hotel
    .init(q: "When is hotel check-in?", expect: .field("hotel", [.checkIn]), group: "hotel"),
    .init(q: "What time can I check in?", expect: .field("hotel", [.checkIn]), group: "hotel"),
    .init(q: "When do I have to check out?", expect: .field("hotel", [.checkOut]), group: "hotel"),
    .init(q: "when's checkout", expect: .field("hotel", [.checkOut]), group: "hotel"),
    .init(q: "What's my hotel confirmation number?", expect: .field("hotel", [.confirmationCode]), group: "hotel"),
    .init(q: "hotel booking code?", expect: .field("hotel", [.confirmationCode]), group: "hotel"),
    .init(q: "What's the hotel's address?", expect: .field("hotel", [.address, .taxi]), group: "hotel"),
    .init(q: "Where am I staying?", expect: .field("hotel", [.address, .taxi]), group: "hotel"),
    .init(q: "hotel addr", expect: .field("hotel", [.address, .taxi]), group: "hotel"),
    .init(q: "Show my hotel to a taxi driver", expect: .field("hotel", [.taxi]), group: "hotel"),
    .init(q: "I need to tell the cab driver where to go", expect: .field("hotel", [.taxi]), group: "hotel"),
    .init(q: "What's the hotel phone number?", expect: .field("hotel", [.phone]), group: "hotel"),
    .init(q: "How do I call the hotel?", expect: .field("hotel", [.phone]), group: "hotel"),
    .init(q: "チェックインは何時ですか？", expect: .field("hotel", [.checkIn]), group: "other language"),
    // Flight
    .init(q: "When does my flight leave?", expect: .field("flight", [.departure]), group: "flight"),
    .init(q: "What time is my flight?", expect: .field("flight", [.departure]), group: "flight"),
    .init(q: "What time should I leave for the airport?", expect: .field("flight", [.departure]), group: "flight"),
    .init(q: "When do I land in Tokyo?", expect: .field("flight", [.arrival]), group: "flight"),
    .init(q: "What time do I arrive at Haneda?", expect: .field("flight", [.arrival]), group: "flight"),
    .init(q: "What's my flight booking reference?", expect: .field("flight", [.confirmationCode]), group: "flight"),
    .init(q: "What's my PNR?", expect: .field("flight", [.confirmationCode]), group: "flight"),
    .init(q: "Where does my flight go?", expect: .field("flight", [.route, .arrival]), group: "flight"),
    .init(q: "Which airport do I fly from?", expect: .field("flight", [.route, .departure]), group: "flight"),
    // Places (distance from the hotel)
    .init(q: "How far is Senso-ji from my hotel?", expect: .place("Senso-ji"), group: "place"),
    .init(q: "How long to walk to Senso-ji?", expect: .place("Senso-ji"), group: "place"),
    .init(q: "How far is the airport from the hotel?", expect: .place("HND"), group: "place"),
    .init(q: "How do I get to Haneda airport?", expect: .place("HND"), group: "place"),
    // Small talk and out of scope: never a booking value
    .init(q: "Hello", expect: .noValue, group: "small talk"),
    .init(q: "Thanks!", expect: .noValue, group: "small talk"),
    .init(q: "Good morning", expect: .noValue, group: "small talk"),
    .init(q: "Who are you?", expect: .noValue, group: "small talk"),
    .init(q: "Tell me a joke", expect: .noValue, group: "small talk"),
    .init(q: "What's the weather tomorrow?", expect: .noValue, group: "out of scope"),
    .init(q: "Can you recommend a ramen place?", expect: .noValue, group: "out of scope"),
    .init(q: "Where can I eat nearby?", expect: .noValue, group: "out of scope"),
    // Asks for something that isn't saved: must not show a different value
    .init(q: "What's my seat number?", expect: .noValue, group: "not saved"),
    .init(q: "What gate does my flight leave from?", expect: .noValue, group: "not saved"),
    .init(q: "Is breakfast included at the hotel?", expect: .noValue, group: "not saved"),
    .init(q: "What's the hotel wifi password?", expect: .noValue, group: "not saved"),
    .init(q: "How much did the hotel cost?", expect: .noValue, group: "not saved"),
    .init(q: "What's my flight number?", expect: .noValue, group: "not saved"),
  ]

  /// New phrasings written after the rules were tuned, never used to tune them: the honest score.
  static let heldOut: [Case] = [
    .init(q: "what time does the hotel let me in", expect: .field("hotel", [.checkIn]), group: "held out"),
    .init(q: "Latest time to leave my room?", expect: .field("hotel", [.checkOut]), group: "held out"),
    .init(q: "Give me the reservation number for Hoshizora", expect: .field("hotel", [.confirmationCode]), group: "held out"),
    .init(q: "Can you show the hotel address in Japanese for the driver?", expect: .field("hotel", [.taxi]), group: "held out"),
    .init(q: "hotel contact number", expect: .field("hotel", [.phone]), group: "held out"),
    .init(q: "When am I flying out of SFO?", expect: .field("flight", [.departure]), group: "held out"),
    .init(q: "what time will I get to Tokyo", expect: .field("flight", [.arrival]), group: "held out"),
    .init(q: "airline confirmation code please", expect: .field("flight", [.confirmationCode]), group: "held out"),
    .init(q: "Is Senso-ji walkable from where I'm staying?", expect: .place("Senso-ji"), group: "held out"),
    .init(q: "distance to HND", expect: .place("HND"), group: "held out"),
    .init(q: "hi blue", expect: .noValue, group: "held out"),
    .init(q: "I love this app", expect: .noValue, group: "held out"),
    .init(q: "Which terminal do I fly from?", expect: .noValue, group: "held out"),
    .init(q: "Does my room have a view?", expect: .noValue, group: "held out"),
    .init(q: "How many bags can I check?", expect: .noValue, group: "held out"),
    .init(q: "チェックアウトは何時？", expect: .field("hotel", [.checkOut]), group: "held out"),
  ]

  /// Second held-out set, written on 20 Nov before the "time questions" rule existed (the first set
  /// found the misses that rule fixes, so it's no longer a clean test). Includes traps for that rule.
  static let heldOut2: [Case] = [
    .init(q: "What time is my room ready?", expect: .field("hotel", [.checkIn]), group: "held out 2"),
    .init(q: "How early can I check in?", expect: .field("hotel", [.checkIn]), group: "held out 2"),
    .init(q: "How late can I stay at the hotel on the last day?", expect: .field("hotel", [.checkOut]), group: "held out 2"),
    .init(q: "When does my plane take off?", expect: .field("flight", [.departure]), group: "held out 2"),
    .init(q: "When will we touch down in Japan?", expect: .field("flight", [.arrival]), group: "held out 2"),
    .init(q: "hotel booking number", expect: .field("hotel", [.confirmationCode]), group: "held out 2"),
    .init(q: "What time is breakfast?", expect: .noValue, group: "held out 2"),
    .init(q: "What time does the gate close?", expect: .noValue, group: "held out 2"),
    .init(q: "What time is it in Tokyo now?", expect: .noValue, group: "held out 2"),
    .init(q: "How long is the flight?", expect: .noValue, group: "held out 2"),
  ]

  /// The sample Tokyo trip (same as the app's "Use a sample trip").
  static func sample(_ ctx: ModelContext) -> ([VaultItem], [Place]) {
    let flight = VaultItem(kind: "flight", title: "Flight EA 061 San Francisco (SFO) → Tokyo Haneda (HND)")
    flight.confirmationCode = "QX7P2L"
    flight.startDate = "2026-12-02"; flight.departureTime = "11:40"
    flight.endDate = "2026-12-03"; flight.arrivalTime = "15:55"
    flight.origin = "SFO"; flight.destination = "HND"
    let hotel = VaultItem(kind: "hotel", title: "Hotel Hoshizora Shinjuku")
    hotel.confirmationCode = "HSZ-48213"
    hotel.startDate = "2026-12-03"; hotel.checkInTime = "15:00"
    hotel.endDate = "2026-12-07"; hotel.checkOutTime = "11:00"
    hotel.address = "4-99-1 Nishi-Shinjuku, Shinjuku-ku, Tokyo"
    hotel.addressLocal = "東京都新宿区西新宿4-99-1"
    hotel.phone = "+81 3-0000-0000"
    let places = [
      Place(name: "Hotel Hoshizora Shinjuku", kind: "hotel", latitude: 35.6895, longitude: 139.6917),
      Place(name: "HND", kind: "airport", latitude: 35.5494, longitude: 139.7798),
      Place(name: "Senso-ji", kind: "plan", latitude: 35.7148, longitude: 139.7967, source: "you"),
    ]
    [flight, hotel].forEach(ctx.insert); places.forEach(ctx.insert)
    return ([flight, hotel], places)
  }

  enum Score: String { case correct, missed, wrong, error }

  /// correct = shows the expected value · missed = says it isn't saved when it is ·
  /// wrong = shows a value that doesn't answer the question (the worst case).
  static func score(_ outcome: AskOutcome, _ expect: Expect) -> (Score, String) {
    switch (outcome, expect) {
    case let (.vault(answer, item, _), .field(kind, fields)):
      let ok = item.kind == kind && fields.contains { VaultAnswerBuilder.answer(item, $0)?.value == answer.value }
      return (ok ? .correct : .wrong, "\(item.kind): \(answer.value)")
    case let (.vault(answer, item, _), _):
      return (.wrong, "\(item.kind): \(answer.value)")
    case let (.place(_, place, _), .place(name)):
      return (place.name == name ? .correct : .wrong, "place: \(place.name)")
    case let (.place(_, place, _), _):
      return (.wrong, "place: \(place.name)")
    case (.notInVault, .noValue), (.other, .noValue), (.cloudAnswer, .noValue), (.waiting, .noValue):
      return (.correct, "no value")
    case (.cloudAnswer, _), (.waiting, _):
      return (.missed, "open question")
    case (.notInVault, _):
      return (.missed, "not in bookings")
    case (.other, _):
      return (.missed, "help reply")
    case (.translation, _):
      return (.wrong, "translation")
    }
  }

  @Test func runTestSet() async throws {
    let container = try ModelContainer(for: VaultItem.self, Place.self, RoutingEntry.self, TranslationEntry.self,
                                       configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let (items, places) = Self.sample(ctx)
    let ai = AIService(connectivity: Connectivity(), context: ctx)
    try #require(ai.deviceModelAvailable, "Apple Intelligence isn't available on this simulator / device")

    var tally: [Score: Int] = [:]
    var byGroup: [String: (Int, Int)] = [:]
    var totalMs = 0, onDevice = 0
    print("BLUE_EVAL|#|score|group|question|expected|got|model pick|ms|ran on")
    let all = Self.cases + Self.heldOut + Self.heldOut2
    for (n, c) in all.enumerated() {
      var line: [String]
      do {
        let (intent, meta) = try await ai.classify(c.q, items: items, places: places)
        let outcome = AskResolver.resolve(intent, question: c.q, items: items, places: places,
                                          here: (35.6895, 139.6917), meta: meta)
        let (score, got) = Self.score(outcome, c.expect)
        tally[score, default: 0] += 1
        let g = byGroup[c.group] ?? (0, 0)
        byGroup[c.group] = (g.0 + (score == .correct ? 1 : 0), g.1 + 1)
        totalMs += meta.latencyMs
        if meta.source == .onDevice { onDevice += 1 }
        let pick = "\(intent.intent) item \(intent.itemIndex) \(intent.field) place \(intent.placeIndex)"
        line = ["\(n + 1)", score.rawValue, c.group, c.q, c.expect.description, got, pick,
                "\(meta.latencyMs)", meta.source == .onDevice ? "device" : "cloud"]
      } catch {
        tally[.error, default: 0] += 1
        line = ["\(n + 1)", "error", c.group, c.q, c.expect.description, "\(error)", "", "", ""]
      }
      print("BLUE_EVAL|" + line.joined(separator: "|"))
    }
    let total = all.count
    let correct = tally[.correct] ?? 0
    print("BLUE_EVAL|SUMMARY|correct \(correct)/\(total) (\(correct * 100 / total)%) · missed \(tally[.missed] ?? 0) · wrong \(tally[.wrong] ?? 0) · errors \(tally[.error] ?? 0) · on-device \(onDevice) · avg \(totalMs / max(1, total - (tally[.error] ?? 0))) ms")
    for (g, (ok, n)) in byGroup.sorted(by: { $0.key < $1.key }) {
      print("BLUE_EVAL|GROUP|\(g)|\(ok)/\(n)")
    }
    // The bar the test enforces: Blue must never show a wrong value. Accuracy is reported, not enforced (yet).
    #expect(tally[.wrong] ?? 0 == 0, "Blue showed a value that doesn't answer the question")
  }
}
