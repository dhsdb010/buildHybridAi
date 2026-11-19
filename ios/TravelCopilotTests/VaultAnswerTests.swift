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
