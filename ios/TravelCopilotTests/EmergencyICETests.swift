import Foundation
import Testing
@testable import TravelCopilot

struct EmergencyICETests {
  func card() -> EmergencyCard {
    let c = EmergencyCard()
    c.ownerName = "Alex Traveler"; c.bloodType = "A+"
    c.allergies = ["Penicillin", "Peanuts", "Cats"]
    c.conditions = ["Asthma"]; c.surgeries = ["Appendectomy (2021)"]
    c.contactName = "Jamie Lee"; c.contactPhone = "+1 415 555 0134"; c.contactRelation = "Partner"
    c.insuranceProvider = "World Nomads"; c.insurancePolicy = "WN-1"
    return c
  }

  @Test func sectionsFollowThePaperCardOrder() {
    let ids = card().iceSections(language: "ja", localFirst: true).map(\.id)
    #expect(ids == ["personal", "allergies", "medicines", "conditions", "surgeries", "contacts", "insurance"])
  }

  @Test func allergiesAreGroupedByType() {
    let s = card().iceSections(language: "ja", localFirst: false).first { $0.id == "allergies" }!
    #expect(s.rows.map(\.label) == ["Drug", "Food", "Other"])
    #expect(s.rows.first?.value == "Penicillin")
    #expect(s.rows.first?.valueOther == "ペニシリン")
    #expect(s.alert)
  }

  @Test func emptyOptionalSectionsAreLeftOut() {
    let c = EmergencyCard()
    let ids = c.iceSections(language: "ja", localFirst: true).map(\.id)
    #expect(ids == ["personal", "allergies", "medicines", "conditions"])
    #expect(c.iceSections(language: "ja", localFirst: true)[1].rows.first?.value == "なし")
  }

  @Test func surgeriesGoToTranslation() {
    #expect(EmergencyText.needsTranslation(card(), language: "ja").contains("Appendectomy (2021)"))
  }
}
