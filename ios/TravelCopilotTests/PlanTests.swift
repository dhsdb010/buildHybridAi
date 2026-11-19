import Testing
@testable import TravelCopilot

@MainActor
struct PlanTests {
  @Test func destinationsFollowOnDeviceLanguages() {
    let countries = PlanLanguages.countries(["ja", "fr"])
    #expect(countries.map(\.code) == ["JP", "FR"])
    #expect(PlanLanguages.countries([]).isEmpty)
  }

  @Test func languageNamesSkipEnglish() {
    #expect(PlanLanguages.languageNames(["en", "ja", "ko"]) == ["Japanese", "Korean"])
  }

  @Test func normalizeIgnoresCaseAccentsAndPunctuation() {
    #expect(PlanService.normalize("Café Kitsuné, Shibuya") == PlanService.normalize("cafe kitsune shibuya"))
  }

  @Test func localReviewSitesAreLinksOnly() {
    #expect(LocalReviews.site(country: "JP", kind: .food) == "Tabelog")
    #expect(LocalReviews.site(country: "JP", kind: .hotel) == nil)
    #expect(LocalReviews.site(country: "FR", kind: .food) == nil)
    #expect(LocalReviews.url(country: "JP", kind: .food, name: "Menya", city: "Tokyo")?.host() == "tabelog.com")
  }

  @Test func googleScoreFormatting() {
    var p = PlanPlace(kind: .food, name: "A", area: "B", why: "", mapsURL: nil, placeID: nil)
    #expect(p.googleScore == nil)
    p.rating = 4.46; p.ratingCount = 3120
    #expect(p.googleScore == "★ 4.5 · 3.1k")
    p.ratingCount = 860
    #expect(p.googleScore == "★ 4.5 · 860")
  }
}
