import MapKit
import Foundation
import Testing
@testable import TravelCopilot

@Suite struct HandleTests {
  @Test func normalizes() {
    #expect(Handle.normalize(" @Alex_K ") == "alex_k")
  }

  @Test func rules() {
    #expect(Handle.isValid("alex_k"))
    #expect(Handle.problem("ab") == .tooShort)
    #expect(Handle.problem(String(repeating: "a", count: 21)) == .tooLong)
    #expect(Handle.problem("alex.k") == .badCharacters)
    #expect(Handle.problem("민아친구") == .badCharacters)
    #expect(Handle.problem("blue") == .reserved)
  }

  @Test func suggestion() {
    #expect(Handle.suggestion(name: "Alex Kim") == "alex_kim")
    #expect(Handle.suggestion(name: "José") == "jose")
    #expect(Handle.suggestion(name: "Al") == "")
  }
}

@Suite struct InviteCodeTests {
  @Test func makesValidCodes() {
    for _ in 0..<50 {
      let c = InviteCode.make()
      #expect(c.count == 8)
      #expect(InviteCode.parse(c) == c)
      #expect(!c.contains("0") && !c.contains("O") && !c.contains("1") && !c.contains("I"))
    }
  }

  @Test func parsesCodesAndLinks() {
    #expect(InviteCode.parse("k7q4 mz2h") == "K7Q4MZ2H")
    #expect(InviteCode.parse("K7Q4-MZ2H") == "K7Q4MZ2H")
    #expect(InviteCode.parse("https://demo-app.web.app/i/K7Q4MZ2H") == "K7Q4MZ2H")
    #expect(InviteCode.parse("travelcopilot://i/K7Q4MZ2H") == "K7Q4MZ2H")
    #expect(InviteCode.parse("https://example.com/other/K7Q4MZ2H") == nil)
    #expect(InviteCode.parse("K7Q4MZ2") == nil)       // too short
    #expect(InviteCode.parse("K7Q4MZ20") == nil)      // 0 isn't in the alphabet
  }

  @Test func links() {
    #expect(InviteCode.link("K7Q4MZ2H", projectID: "demo-app").absoluteString == "https://demo-app.web.app/i/K7Q4MZ2H")
    #expect(InviteCode.link("K7Q4MZ2H", projectID: nil).absoluteString == "travelcopilot://i/K7Q4MZ2H")
    #expect(InviteCode.display("K7Q4MZ2H") == "K7Q4 MZ2H")
  }

  @Test func expiry() {
    let now = Date()
    #expect(!InviteCode.isExpired(createdAt: now.addingTimeInterval(-6 * 86400), now: now))
    #expect(InviteCode.isExpired(createdAt: now.addingTimeInterval(-8 * 86400), now: now))
  }
}

@Suite struct MessageFilterTests {
  @Test func masksAndCaps() {
    #expect(MessageFilter.clean("TeamLab on Friday?") == "TeamLab on Friday?")
    #expect(!MessageFilter.clean("this is shit").lowercased().contains("shit"))
    #expect(MessageFilter.clean(String(repeating: "a", count: 3000)).count == MessageFilter.maxLength)
  }
}

@Suite struct TripRoomTests {
  @Test func membersText() {
    let r = TripRoom(id: "r", name: "Tokyo trip", owner: "me",
                     members: [.init(id: "me", name: "Alex", handle: "alex_k", role: .owner),
                               .init(id: "m", name: "Mina", handle: "mina", role: .editor)],
                     tripTitle: nil, friendsCanEdit: true, createdAt: Date())
    #expect(r.membersText(me: "me") == "You, Mina")
    #expect(r.member("m")?.role.title == "Can edit")
  }

  @MainActor @Test func inviteLinkOpensChats() {
    let router = AppRouter()
    #expect(router.open(URL(string: "travelcopilot://i/K7Q4MZ2H")!))
    #expect(router.inviteCode?.code == "K7Q4MZ2H" && router.showChats)
  }
}

@Suite struct BlueInRoomTests {
  @Test func mentions() {
    #expect(BlueInRoom.mentions("@blue can you suggest for our trip plan?"))
    #expect(BlueInRoom.mentions("Hey @Blue, what's good on Friday?"))
    #expect(!BlueInRoom.mentions("I love the blue lagoon"))
    #expect(!BlueInRoom.mentions("mail me at me@blue.com"))
    #expect(!BlueInRoom.mentions("@bluebird is my ID"))
  }

  @Test func questionDropsTheMention() {
    #expect(BlueInRoom.question("@blue can you suggest for our trip plan?") == "can you suggest for our trip plan?")
    #expect(BlueInRoom.question("@Blue, rain plan?") == "rain plan?")
  }

  @Test func promptUsesOnlyTheRoom() {
    let room = TripRoom(id: "r", name: "Seoul trip", owner: "me",
                        members: [.init(id: "me", name: "Alex", handle: "alex_k", role: .owner),
                                  .init(id: "j", name: "Jun", handle: "jun_t", role: .editor)],
                        tripTitle: "Seoul · Mar 3–7", friendsCanEdit: true, createdAt: Date())
    let msgs = [RoomMessage(id: "1", author: "me", authorName: "Alex", text: "Alex made this room", sentAt: nil, kind: .system, pending: false),
                RoomMessage(id: "2", author: "j", authorName: "Jun", text: "Hi everyone!", sentAt: nil, kind: .text, pending: false)]
    let p = BlueInRoom.prompt(room: room, messages: msgs, question: "what should we do first?", asker: "Alex")
    #expect(p.contains("Room: Seoul trip · trip: Seoul · Mar 3–7"))
    #expect(p.contains("Jun: Hi everyone!"))
    #expect(!p.contains("made this room"))            // system lines aren't sent
    #expect(p.contains("Question from Alex: what should we do first?"))
  }
}

@Suite struct MentionsTests {
  let room = TripRoom(id: "r", name: "Tokyo trip", owner: "me",
                      members: [.init(id: "me", name: "Alex", handle: "alex_k", role: .owner),
                                .init(id: "m", name: "Mina Park", handle: "mina", role: .editor),
                                .init(id: "j", name: "Jun", handle: "jun_t", role: .editor)],
                      tripTitle: nil, friendsCanEdit: true, createdAt: Date())

  @Test func activeQuery() {
    #expect(Mentions.activeQuery(in: "Saturday works. @") == "")
    #expect(Mentions.activeQuery(in: "Saturday works. @Mi") == "mi")
    #expect(Mentions.activeQuery(in: "@") == "")
    #expect(Mentions.activeQuery(in: "mail a@b") == nil)          // not a word start
    #expect(Mentions.activeQuery(in: "@mina hi") == nil)          // finished, then more text
    #expect(Mentions.activeQuery(in: "no mention") == nil)
  }

  @Test func suggestionsBlueFirstThenRoomOnly() {
    let all = Mentions.suggestions(query: "", room: room, me: "me")
    #expect(all.map(\.title) == ["Blue", "Mina Park", "Jun"])     // never yourself
    #expect(Mentions.suggestions(query: "mi", room: room, me: "me").map(\.title) == ["Mina Park"])
    #expect(Mentions.suggestions(query: "b", room: room, me: "me").map(\.title) == ["Blue"])
    #expect(Mentions.suggestions(query: "jun_", room: room, me: "me").map(\.title) == ["Jun"])   // by @ID too
    #expect(Mentions.suggestions(query: "ken", room: room, me: "me").isEmpty)
  }

  @Test func insertReplacesTheTypedWord() {
    let mina = Mentions.suggestions(query: "mi", room: room, me: "me")[0]
    #expect(Mentions.insert(mina, into: "Saturday works. @mi") == "Saturday works. @Mina ")
    let blue = Mentions.suggestions(query: "", room: room, me: "me")[0]
    #expect(Mentions.insert(blue, into: "@") == "@Blue ")
  }

  @Test func boldOnlyKnownMentions() {
    let text = "Saturday works. @Mina @Blue is it open? mail a@b.com @ken"
    let words = Mentions.ranges(in: text, room: room).map { String(text[$0]) }
    #expect(words == ["@Mina", "@Blue"])
  }
}

@Suite struct SharedPlanTests {
  let cal = TripTimeline.calendar
  func at(_ day: Int, _ hour: Int) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour))!
  }
  func stop(_ day: Int, _ hour: Int, _ title: String) -> SharedStop {
    SharedStop(id: title, date: at(day, hour), title: title, detail: "", kind: "See", addedBy: "me", addedByName: "Alex")
  }

  @Test func summaryAndDays() {
    let stops = [stop(3, 10, "teamLab"), stop(2, 18, "Shibuya Sky"), stop(3, 13, "Toyosu"), stop(7, 11, "Shopping")]
    #expect(SharedPlan.days(stops).count == 3)
    #expect(SharedPlan.summary(stops) == "Dec 2–7 · 3 days · 4 stops")
    #expect(SharedPlan.stops(on: at(3, 0), stops).map(\.title) == ["teamLab", "Toyosu"])
    #expect(SharedPlan.summary([]) == "No stops yet")
  }

  @MainActor @Test func plannerOutlineBecomesStops() {
    let brief = PlanBrief(start: at(2, 0), end: at(4, 0))
    let outline = [DayIdea(title: "Arrive · Shibuya", area: "Shibuya"), DayIdea(title: "Art day", area: "Roppongi"),
                   DayIdea(title: "Fly home", area: "Haneda")]
    let drafts = PlanService.sharedStops(brief: brief, outline: outline, hotel: nil, kept: [])
    #expect(drafts.map(\.title) == ["Arrive · Shibuya", "Art day", "Fly home"])
    #expect(cal.component(.hour, from: drafts[0].date) == 9)
    #expect(cal.component(.day, from: drafts[2].date) == 4)
  }

  @Test func blueSeesTheSharedPlan() {
    let room = TripRoom(id: "r", name: "Tokyo trip", owner: "me", members: [.init(id: "me", name: "Alex", handle: "alex_k", role: .owner)],
                        tripTitle: nil, friendsCanEdit: true, createdAt: Date())
    let p = BlueInRoom.prompt(room: room, messages: [], question: "swap Dec 3?", asker: "Alex", plan: [stop(3, 10, "teamLab")])
    #expect(p.contains("Shared plan:"))
    #expect(p.contains("teamLab (See)"))
  }
}

@Suite("Add a stop search") @MainActor
struct AddStopSearchTests {
  @Test func categoriesBecomeKindsAndIcons() {
    #expect(DayStops.style(.cafe) == ("cup.and.saucer", "Food", "Café"))
    #expect(DayStops.style(.hotel).kind == "Stay")
    #expect(DayStops.style(.landmark).label == "Landmark")
    #expect(DayStops.style(nil) == ("mappin", "Stop", "Place"))
  }

  @Test func distanceReadsLikeMaps() {
    let a = CLLocationCoordinate2D(latitude: 35.6586, longitude: 139.7454)   // Tokyo Tower
    #expect(DayStops.distance(nil, a) == nil)
    #expect(DayStops.distance(a, CLLocationCoordinate2D(latitude: 35.6616, longitude: 139.7454))?.hasSuffix(" m") == true)
    #expect(DayStops.distance(a, CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005)) == "4.1 km")
  }
}
