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
