import Foundation
import SwiftData
import Testing
@testable import TravelCopilot

@MainActor
struct EmergencyCardTests {
  func sample() -> EmergencyCard {
    let c = EmergencyCard()
    c.bloodType = "A+"
    c.medicines = [EmergencyMedicine(name: "Ibuprofen 200 mg", schedule: "twice a day")]
    c.allergies = ["Penicillin", "Peanuts"]
    c.conditions = ["Asthma", "Bad knees"]
    c.contactName = "Jamie Lee"; c.contactPhone = "+1 415 555 0134"; c.contactRelation = "Partner"
    return c
  }

  @Test func labelsAndCommonItemsAreFixedNotAI() {
    #expect(EmergencyText.labels(for: "ja")?.allergies == "アレルギー")
    #expect(EmergencyText.local("Penicillin", language: "ja", card: sample()) == "ペニシリン")
    #expect(EmergencyText.labels(for: "fr") == nil)   // no fixed labels → English-only card, no flip button
  }

  @Test func onlyTheTravelersOwnWordsGoToTranslation() {
    let c = sample()
    #expect(EmergencyText.needsTranslation(c, language: "ja") == ["Bad knees", "Ibuprofen 200 mg, twice a day"])
    c.translationLanguage = "ja"; c.translations["Bad knees"] = "膝が悪い"
    #expect(EmergencyText.needsTranslation(c, language: "ja") == ["Ibuprofen 200 mg, twice a day"])
  }

  @Test func bloodTypeInJapanese() {
    #expect(EmergencyText.bloodType("A+", language: "ja") == "A型 Rh+")
    #expect(EmergencyText.bloodType("O−", language: "ja") == "O型 Rh−")
    #expect(EmergencyText.bloodType("AB+", language: "ko") == "AB+")
  }

  @Test func translationCheckKeepsDosesAndMedicineNames() {
    #expect(EmergencyTranslator.isSafe("Ibuprofen 200 mg, twice a day", "イブプロフェン (ibuprofen) 200 mg、1日2回", isMedicine: true))
    #expect(!EmergencyTranslator.isSafe("Ibuprofen 200 mg, twice a day", "イブプロフェン (ibuprofen) 2000 mg、1日2回", isMedicine: true))
    #expect(!EmergencyTranslator.isSafe("Ibuprofen 200 mg", "イブプロフェン 200mg", isMedicine: true))      // English name dropped
    #expect(!EmergencyTranslator.isSafe("Insulin 10 units", "インスリン (insulin) 10単位 50", isMedicine: true)) // a big extra number
    #expect(EmergencyTranslator.isSafe("Bad knees", "膝が悪い", isMedicine: false))
  }

  @Test func cardRowsBothSides() throws {
    let c = sample()
    c.translationLanguage = "ja"
    c.translations = ["Ibuprofen 200 mg, twice a day": "イブプロフェン (ibuprofen) 200 mg、1日2回"]
    let ja = c.rows(language: "ja", localFirst: true)
    #expect(ja[0].label == "アレルギー" && ja[0].value == "ペニシリン\nピーナッツ" && ja[0].valueOther == "Penicillin, Peanuts")
    #expect(ja[1].value == "イブプロフェン (ibuprofen) 200 mg、1日2回")
    #expect(ja[2].value == "喘息\nBad knees")                 // untranslated words stay in English, never guessed
    #expect(ja[3].value == "A型 Rh+")
    #expect(ja[4].value == "Jamie Lee (パートナー)\n+1 415 555 0134" && ja[4].valueOther == "Partner")
    let en = c.rows(language: "ja", localFirst: false)
    #expect(en[0].label == "Allergies" && en[0].value == "Penicillin\nPeanuts" && en[0].valueOther == "ペニシリン、ピーナッツ")
    #expect(en[4].value == "Jamie Lee (partner)\n+1 415 555 0134" && en[4].valueOther == "パートナー")
  }

  @Test func emptyCardSaysNone() {
    let c = EmergencyCard()
    #expect(c.isEmpty)
    let rows = c.rows(language: "ja", localFirst: true)
    #expect(rows.count == 3 && rows.allSatisfy { $0.value == "なし" })
  }
}

@MainActor
struct EmergencyIntentTests {
  @Test func actionBeforeTheAppIsReadyIsRemembered() async throws {
    EmergencyIntentHandler.show = nil
    var opened = 0
    _ = try await ShowEmergencyCardIntent().perform()   // cold launch: the app isn't ready yet
    #expect(EmergencyIntentHandler.pending)
    EmergencyIntentHandler.show = { opened += 1 }        // the app comes up → the card opens
    #expect(opened == 1 && !EmergencyIntentHandler.pending)
    _ = try await ShowEmergencyCardIntent().perform()   // app running: opens right away
    #expect(opened == 2)
    EmergencyIntentHandler.show = nil
  }

  @Test func deepLinkOpensTheCard() {
    let router = AppRouter()
    #expect(router.open(URL(string: "travelcopilot://emergency")!))
    #expect(router.emergency == .card)
  }
}
