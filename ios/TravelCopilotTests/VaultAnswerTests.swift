import Testing
@testable import TravelCopilot

@MainActor
struct VaultAnswerTests {
  private func hotel() -> VaultItem {
    let h = VaultItem(kind: "hotel", title: "Hotel Hoshizora Shinjuku")
    h.confirmationCode = "HSZ-48213"
    h.startDate = "2026-12-01"
    h.checkInTime = "15:00"
    h.address = "4-99-1 Nishi-Shinjuku"
    h.addressLocal = "東京都新宿区西新宿4-99-1"
    return h
  }

  @Test func checkInQuotesStoredValues() throws {
    let a = try #require(VaultAnswerBuilder.answer(hotel(), .checkIn))
    #expect(a.value == "2026-12-01 15:00")
    #expect(a.text.contains("15:00"))
    #expect(!a.showTaxiCard)
  }

  @Test func confirmationCodeIsVerbatim() throws {
    #expect(try #require(VaultAnswerBuilder.answer(hotel(), .confirmationCode)).value == "HSZ-48213")
  }

  @Test func taxiUsesLocalScriptAndOpensCard() throws {
    let a = try #require(VaultAnswerBuilder.answer(hotel(), .taxi))
    #expect(a.value == "東京都新宿区西新宿4-99-1")
    #expect(a.showTaxiCard)
  }

  @Test func missingFieldReturnsNilInsteadOfGuessing() {
    #expect(VaultAnswerBuilder.answer(hotel(), .phone) == nil)
    #expect(VaultAnswerBuilder.answer(hotel(), .route) == nil)
    #expect(VaultAnswerBuilder.answer(hotel(), .none) == nil)
  }

  @Test func replyPromptFallsBackToEnglish() {
    #expect(ReplyPrompt.text(for: "ja-JP") == "こちらにご返信を入力してください")
    #expect(ReplyPrompt.text(for: "xx") == "Type your reply here")
    #expect(ReplyPrompt.text(for: nil) == "Type your reply here")
    #expect(LocalReplyScreen.screen(for: "ja-JP").send == "送信")
    #expect(LocalReplyScreen.screen(for: "xx") == .english)
    #expect(LocalReplyScreen.byLanguage.values.allSatisfy { !$0.title.isEmpty && !$0.send.isEmpty && !$0.handBack.isEmpty })
  }
}

struct RomanizerTests {
  @Test func japaneseReadsKanji() {
    let r = Romanizer.latin("東京に行きます", languageCode: "ja")
    #expect(r.lowercased().contains("toukyou") || r.lowercased().contains("tokyo"))
  }
  @Test func latinScriptReturnsEmpty() {
    #expect(Romanizer.latin("Bonjour", languageCode: "fr") == "")
  }
  @Test func koreanTransliterates() {
    #expect(!Romanizer.latin("안녕하세요", languageCode: "ko").isEmpty)
  }
}

struct RomanizerParticleTests {
  @Test func topicParticleIsWa() {
    #expect(Romanizer.latin("私は学生です", languageCode: "ja").contains(" wa "))
  }
}

struct RomanizerCleanupTests {
  @Test func loneNMergesAndParensTight() {
    let r = Romanizer.latin("使えません (ibuprofen)", languageCode: "ja")
    #expect(!r.contains(" n "))
    #expect(!r.hasSuffix(" n"))
    #expect(r.contains("(ibuprofen)"))
  }
}

struct RomanizerReadableTests {
  @Test func politeEndingsAndAddressesReadNaturally() {
    #expect(Romanizer.readable("kono juusho made o negai shi masu") == "Kono jusho made onegaishimasu")
    #expect(Romanizer.readable("toukyou to shinjuku ku nishishinjuku 4 - 99 - 1") == "Tokyo-to shinjuku-ku nishishinjuku 4-99-1")
  }
}

struct AskGuardTests {
  @Test func smallTalkNeverGetsABookingValue() {
    for q in ["Hello", "hi there", "thanks!", "good morning"] {
      #expect(!VaultField.allCases.contains { AskGuard.fits(q, field: $0) }, "\(q)")
      #expect(!AskGuard.fitsPlace(q))
    }
  }

  @Test func realQuestionsStillFit() {
    #expect(AskGuard.fits("When is hotel check-in?", field: .checkIn))
    #expect(AskGuard.fits("What's my flight booking code?", field: .confirmationCode))
    #expect(AskGuard.fits("Show my hotel to a taxi driver", field: .taxi))
    #expect(AskGuard.fits("When does my train leave?", field: .departure))
    #expect(AskGuard.fitsPlace("How far is Senso-ji from my hotel?"))
  }
}

/// The code step of Blue's answer, with a fixed model pick (no AI): each rule the test set needed.
@MainActor
struct AskResolverTests {
  let meta = AIMeta(route: .deviceOnly, source: .onDevice, latencyMs: 0)
  let hotel: VaultItem = {
    let h = VaultItem(kind: "hotel", title: "Hotel Hoshizora Shinjuku")
    h.confirmationCode = "HSZ-48213"; h.address = "4-99-1 Nishi-Shinjuku"; h.addressLocal = "東京都新宿区西新宿4-99-1"
    h.startDate = "2026-12-03"; h.checkInTime = "15:00"
    return h
  }()
  let flight: VaultItem = {
    let f = VaultItem(kind: "flight", title: "Flight EA 061")
    f.confirmationCode = "QX7P2L"; f.origin = "SFO"; f.destination = "HND"; f.startDate = "2026-12-02"; f.departureTime = "11:40"
    return f
  }()
  let places = [
    Place(name: "Hotel Hoshizora Shinjuku", kind: "hotel", latitude: 35.6895, longitude: 139.6917),
    Place(name: "HND", kind: "airport", latitude: 35.5494, longitude: 139.7798),
    Place(name: "Senso-ji", kind: "plan", latitude: 35.7148, longitude: 139.7967),
  ]

  func run(_ q: String, _ intent: String, item: Int = -1, field: String = "none", place: Int = -1) -> AskOutcome {
    AskResolver.resolve(AskIntent(intent: intent, itemIndex: item, field: field, placeIndex: place),
                        question: q, items: [flight, hotel], places: places, here: nil, meta: meta)
  }

  @Test func unsavedThingsNeverShowAnotherField() {
    guard case .notInVault = run("What's my seat number?", "vault", item: 0, field: "confirmationCode") else { Issue.record("seat"); return }
    guard case .notInVault = run("What gate does my flight leave from?", "vault", item: 0, field: "departure") else { Issue.record("gate"); return }
    // "navigate" isn't "gate"
    guard case .place = run("How do I navigate to Senso-ji?", "place", place: 2) else { Issue.record("navigate"); return }
  }

  @Test func taxiWordsOpenTheTaxiCard() {
    guard case let .vault(a, item, _) = run("I need to tell the cab driver where to go", "place", place: 0) else { Issue.record("taxi"); return }
    #expect(item.kind == "hotel" && a.showTaxiCard)
  }

  @Test func placeIsFoundByNameNotTheModelsNumber() {
    guard case let .place(_, p, _) = run("How far is Senso-ji from my hotel?", "place", place: 1) else { Issue.record("senso-ji"); return }
    #expect(p.name == "Senso-ji")
    guard case let .place(_, a, _) = run("How far is the airport from the hotel?", "place", item: 1, place: 0) else { Issue.record("airport"); return }
    #expect(a.name == "HND")
  }

  @Test func whereQuestionsGetTheRoute() {
    guard case let .vault(a, _, _) = run("Where does my flight go?", "vault", item: 0, field: "arrival") else { Issue.record("route"); return }
    #expect(a.value == "SFO → HND")
  }

  @Test func japaneseCheckInWorks() {
    guard case let .vault(a, _, _) = run("チェックインは何時ですか？", "vault", item: 1, field: "checkIn") else { Issue.record("ja"); return }
    #expect(a.value == "2026-12-03 15:00")
  }
}

extension AskResolverTests {
  @Test func rightFieldOnTheWrongBookingUsesTheRightBooking() {
    guard case let .vault(a, item, _) = run("When is check-in?", "vault", item: 0, field: "checkIn") else { Issue.record("checkIn"); return }
    #expect(item.kind == "hotel" && a.value == "2026-12-03 15:00")
  }
}
