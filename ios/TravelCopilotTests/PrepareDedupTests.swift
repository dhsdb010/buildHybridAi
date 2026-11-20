import Testing
@testable import TravelCopilot

@MainActor
struct PrepareDedupTests {
  func item(_ kind: String, _ title: String, code: String? = nil, start: String? = nil, country: String? = nil) -> VaultItem {
    let i = VaultItem(kind: kind, title: title)
    i.confirmationCode = code
    i.startDate = start
    i.countryCode = country
    return i
  }

  @Test func sameCodeIsSameBooking() {
    // The model may write the code or title slightly differently the second time.
    #expect(PrepareService.isSameBooking(
      item("hotel", "Hotel Hoshizora Shinjuku", code: "HSZ-48213"),
      item("hotel", "Hoshizora Shinjuku", code: "hsz 48213")))
  }

  @Test func differentCodeIsDifferentBooking() {
    #expect(!PrepareService.isSameBooking(
      item("hotel", "Hotel Hoshizora Shinjuku", code: "HSZ-48213"),
      item("hotel", "Hotel Hoshizora Shinjuku", code: "HSZ-99999")))
  }

  @Test func withoutCodesTitleAndDateDecide() {
    #expect(PrepareService.isSameBooking(
      item("flight", "Flight EA 061 SFO → HND", start: "2026-12-02"),
      item("flight", "flight ea 061 sfo → hnd", start: "2026-12-02")))
    // Same flight a week later: a different booking.
    #expect(!PrepareService.isSameBooking(
      item("flight", "Flight EA 061 SFO → HND", start: "2026-12-02"),
      item("flight", "Flight EA 061 SFO → HND", start: "2026-12-09")))
  }

  @Test func differentKindIsDifferentBooking() {
    #expect(!PrepareService.isSameBooking(
      item("hotel", "Tokyo", code: "A1"), item("train", "Tokyo", code: "A1")))
  }

  @Test func packCountryPrefersTheHotel() {
    let flight = item("flight", "SFO → HND", country: "US")
    let hotel = item("hotel", "Hoshizora", country: "JP")
    #expect(PrepareService.mainCountry(of: [flight, hotel])?.countryCode == "JP")
    #expect(PrepareService.mainCountry(of: [flight])?.countryCode == "US")
    #expect(PrepareService.mainCountry(of: [item("other", "Note")]) == nil)
  }
}
