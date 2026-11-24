import Foundation
import Testing
@testable import TravelCopilot

struct SpendTests {
  @Test func budgetTurnsOrangeAt80Percent() {
    #expect(Spend.status(spent: 123, budget: 1000) == .onTrack)
    #expect(Spend.status(spent: 799, budget: 1000) == .onTrack)
    #expect(Spend.status(spent: 800, budget: 1000) == .near)
    #expect(Spend.status(spent: 1200, budget: 1000) == .near)
    #expect(Spend.status(spent: 50, budget: 0) == .onTrack)
  }

  @Test func currencyFromCountry() {
    #expect(Spend.currency(country: "JP") == "JPY")
    #expect(Spend.currency(country: "KR") == "KRW")
    #expect(Spend.currency(country: "FR") == "EUR")
    #expect(Spend.currency(country: nil) == nil)
  }

  @MainActor @Test func totalsByDayAndCategory() {
    let cal = TripTimeline.calendar
    let d3 = cal.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 12))!
    let d2 = cal.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 19))!
    let items = [
      ExpenseItem(spentAt: d3, merchant: "Ichiran", amount: 1180, currency: "JPY", category: .food),
      ExpenseItem(spentAt: d3.addingTimeInterval(3600), merchant: "Don Quijote", amount: 3960, currency: "JPY", category: .shopping),
      ExpenseItem(spentAt: d2, merchant: "Lawson", amount: 840, currency: "JPY", category: .food),
    ]
    #expect(Spend.localTotal(items) == 5980)
    let days = Spend.byDay(items)
    #expect(days.count == 2)
    #expect(days[0].items.map(\.merchant) == ["Don Quijote", "Ichiran"])   // newest day, newest first
    let cats = Spend.byCategory(items)
    #expect(cats.first?.category == .shopping)                                 // biggest first
    #expect(Spend.toSettle(items) == 3)
  }

  @MainActor @Test func homeAmountsUseTheSettledValueThenTheSavedRate() {
    let e = ExpenseItem(spentAt: Date(), merchant: "A", amount: 1496, currency: "JPY", category: .food)
    let rate = FXRate(local: "JPY", home: "USD", localPerHome: 149.6, date: Date())
    #expect(Spend.home(e, rate: nil) == nil)
    #expect(abs((Spend.home(e, rate: rate) ?? 0) - 10) < 0.0001)
    #expect(Spend.home(e, rate: FXRate(local: "KRW", home: "USD", localPerHome: 1400, date: Date())) == nil)
    e.homeAmount = 9.99
    #expect(Spend.home(e, rate: rate) == 9.99)
    #expect(Spend.homeTotal([e], rate: nil) == 9.99)
  }

  @Test func receiptTotalComesFromTheTotalLine() {
    #expect(ReceiptTotal.find(ExpenseService.sampleLines) == 1180)
    #expect(ReceiptTotal.find(["Coffee 4.50", "Cake 5.00", "TOTAL 9.50", "Card ****1234"]) == 9.5)
    #expect(ReceiptTotal.find(["합계", "12,000원"]) == 12000)
    #expect(ReceiptTotal.find(["Coffee 300", "Thank you"]) == nil)
  }

  @Test func categoriesFromModelWords() {
    #expect(ExpenseCategory.from("Food") == .food)
    #expect(ExpenseCategory.from("restaurant") == .food)
    #expect(ExpenseCategory.from("Subway ticket") == .transport)
    #expect(ExpenseCategory.from("souvenir shop") == .shopping)
    #expect(ExpenseCategory.from("???") == .other)
  }

  @Test func parsesTheRateReply() throws {
    let data = Data(#"{"amount":1.0,"base":"USD","date":"2026-11-28","rates":{"JPY":149.6}}"#.utf8)
    let r = try ExpenseService.parse(data, local: "JPY", home: "USD")
    #expect(r.localPerHome == 149.6)
    #expect(Calendar(identifier: .gregorian).component(.day, from: r.date) == 28)
    #expect(throws: (any Error).self) { try ExpenseService.parse(data, local: "EUR", home: "USD") }
  }

  @MainActor @Test func csvHasEveryExpense() {
    let e = ExpenseItem(spentAt: Date(), merchant: "Ichiran \"Shinjuku\"", amount: 1180, currency: "JPY", category: .food)
    let csv = Spend.csv([e], home: "USD")
    #expect(csv.hasPrefix("date,place,category,amount,currency,usd,settled"))
    #expect(csv.contains("\"Ichiran 'Shinjuku'\",food,1180.0,JPY,,false"))
  }
}

struct UpNextTests {
  static let cal = TripTimeline.calendar
  static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: day, hour: h, minute: m))! }

  static var events: [TripEvent] {
    [
      TripEvent(id: "arr", date: at(3, 15, 55), kind: .arrive, title: "Land at HND", detail: "EA 061", itemID: nil, planSource: nil, vehicle: "flight"),
      TripEvent(id: "in", date: at(3, 17), kind: .checkIn, title: "Check in · Hotel Hoshizora", detail: "Ref HSZ", itemID: nil, planSource: nil),
      TripEvent(id: "dinner", date: at(3, 18, 30), kind: .plan, title: "Dinner in Shinjuku", detail: "12 min walk", itemID: nil, planSource: "user"),
      TripEvent(id: "asakusa", date: at(4, 9), kind: .plan, title: "Asakusa by train", detail: "Ginza line", itemID: nil, planSource: "user"),
      TripEvent(id: "out", date: at(7, 11), kind: .checkOut, title: "Check out · Hotel Hoshizora", detail: "", itemID: nil, planSource: nil),
    ]
  }

  @Test func firstCardIsTheNextThingToDo() {
    let cards = UpNext.cards(Self.events, now: Self.at(3, 16, 40), done: [], language: "Japanese")
    #expect(cards.map(\.id) == ["in", "dinner", "asakusa", "out"])
    #expect(cards[0].title == "Taxi card")
    #expect(cards[0].label == "Next · check-in 17:00")
    #expect(cards[0].action == .taxi)
    #expect(cards[1].label == "Then · 18:30")
    #expect(cards[1].symbol == "fork.knife")
    #expect(cards[2].label == "Tomorrow · 09:00")
    #expect(cards[2].symbol == "tram")
  }

  @Test func finishedStepsDropOff() {
    let cards = UpNext.cards(Self.events, now: Self.at(3, 16, 40), done: ["in"], language: nil)
    #expect(cards.first?.id == "dinner")
    #expect(cards.first?.label == "Next · 18:30")
  }

  @Test func pastMomentsLeaveAfterAGracePeriod() {
    #expect(UpNext.cards(Self.events, now: Self.at(3, 17, 20), done: [], language: nil).first?.id == "in")
    #expect(UpNext.cards(Self.events, now: Self.at(3, 17, 40), done: [], language: nil).first?.id == "dinner")
    #expect(UpNext.cards(Self.events, now: Self.at(8, 9), done: [], language: nil).isEmpty)
  }
}

struct TripSummaryTests {
  static let cal = TripTimeline.calendar
  static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: day, hour: h, minute: m))! }

  static var summary: TripSummary {
    let events = [
      TripEvent(id: "dep", date: at(2, 11, 40), kind: .depart, title: "SFO → Tokyo Haneda", detail: "EA 061 · ABC", itemID: nil, planSource: nil, vehicle: "flight"),
      TripEvent(id: "arr", date: at(3, 15, 55), kind: .arrive, title: "Land at Tokyo Haneda", detail: "EA 061", itemID: nil, planSource: nil, vehicle: "flight"),
      TripEvent(id: "in", date: at(3, 15), kind: .checkIn, title: "Check in · Hotel Hoshizora", detail: "", itemID: nil, planSource: nil),
      TripEvent(id: "p1", date: at(4, 11), kind: .plan, title: "Senso-ji", detail: "", itemID: nil, planSource: "user"),
      TripEvent(id: "out", date: at(7, 11), kind: .checkOut, title: "Check out · Hotel Hoshizora", detail: "", itemID: nil, planSource: nil),
    ]
    return TripSummary.build(
      events: events,
      plans: [.init(start: at(4, 11), title: "Senso-ji", detail: "", kind: "Asakusa", latitude: 35.71, longitude: 139.79)],
      places: [.init(name: "Hotel Hoshizora", kind: "hotel", latitude: 35.69, longitude: 139.70)],
      expenses: [
        .init(date: at(4, 11, 20), merchant: "Senso-ji", amount: 1000, currency: "JPY", category: .sights),
        .init(date: at(3, 16, 30), merchant: "Keikyu Line", amount: 2020, currency: "JPY", category: .transport),
        .init(date: at(4, 15), merchant: "Don Quijote", amount: 3960, currency: "JPY", category: .shopping),
      ])!
  }

  @Test func daysInOrderWithPastTenseWords() {
    let s = Self.summary
    #expect(s.dayCount == 6)
    #expect(s.days.map { Self.cal.component(.day, from: $0.day) } == [2, 3, 4, 7])
    let d3 = s.days[1].stops.map(\.title)
    #expect(d3 == ["Landed at Tokyo Haneda", "Keikyu Line", "Checked in · Hotel Hoshizora"])
    #expect(s.days[0].stops[0].detail == "EA 061 · 11:40")
    #expect(s.days[1].stops[2].detail == "from 15:00")
  }

  @Test func aReceiptAtAPlannedStopJoinsThatStop() {
    let d4 = Self.summary.days[2].stops
    #expect(d4.map(\.title) == ["Senso-ji", "Don Quijote"])
    #expect(d4[0].detail == "Asakusa · ¥1,000")
    #expect(d4[0].symbol == ExpenseCategory.sights.symbol)
  }

  @Test func routeAndPlaces() {
    let s = Self.summary
    #expect(s.route.map(\.title) == ["Checked in · Hotel Hoshizora", "Senso-ji"])
    #expect(s.route(on: Self.at(4, 0)).map(\.title) == ["Senso-ji"])
    // Hotel, Senso-ji, Don Quijote (the train ride isn't a place).
    #expect(s.places == 3)
  }

  @Test func stepsEasterEggMath() {
    #expect(Steps.fujis(84_210) == 16)
    #expect(Steps.kmText(84_210) == "about 61 km on foot")
    #expect(Steps.fujis(1000) == 0)
  }

  @Test func cityFromTheFlightIn() {
    #expect(TripSummary.city(destination: "Tokyo Haneda") == "Tokyo")
    #expect(TripSummary.city(destination: "HND") == "Tokyo")
    #expect(TripSummary.city(destination: "XYZ") == nil)
    #expect(TripSummary.flightNumber("EA 061 San Francisco (SFO) to Tokyo") == "EA 061")
    #expect(TripSummary.city(destination: nil) == nil)
  }

  @Test func welcomeUsesTheFirstName() {
    #expect(Profile.firstName(account: "Alex Kim") == "Alex" || Profile.name != nil)
    #expect(Profile.firstName(account: nil) == Profile.name)
  }
}

struct TripIconTests {
  @Test func everyCategoryHasAnEmoji() {
    for c in ExpenseCategory.allCases { #expect(TripIcon.emoji[c.symbol] != nil) }
    for s in ["airplane.departure", "airplane.arrival", "bed.double", "staroflife", "tram.fill.tunnel", "ferry", "bus"] {
      #expect(TripIcon.emoji[s] != nil)
    }
  }

  @Test func planWordsPickATransportSymbol() {
    #expect(UpNext.symbol(plan: "Ferry to Odaiba") == "ferry")
    #expect(UpNext.symbol(plan: "Bus to Hakone") == "bus")
    #expect(UpNext.symbol(plan: "Ginza metro") == "tram.fill.tunnel")
    #expect(UpNext.symbol(plan: "Senso-ji") == "building.columns")
  }
}
