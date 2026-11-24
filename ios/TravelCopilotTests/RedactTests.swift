import Testing
@testable import TravelCopilot

struct RedactTests {
  @Test func hidesCardNumbers() {
    let r = Redact.sensitive("Paid with Visa 4111 1111 1111 1111, exp 12/28, CVV: 123.")
    #expect(r.text == "Paid with Visa [card ending 1111], exp 12/28, CVV: [hidden].")
    #expect(r.cards == 1)
    #expect(Redact.sensitive("Amex 3782-822463-10005").text == "Amex [card ending 0005]")
  }

  @Test func keepsBookingNumbers() {
    // Ticket numbers (13 digits), phone numbers, confirmation codes, flights and
    // 16-digit numbers that fail the card check all stay.
    let text = "E-ticket 2051234567890 · call +1 415 555 0134 · ref ABC123 · NH 107 · order 1234567890123456"
    let r = Redact.sensitive(text)
    #expect(r.text == text)
    #expect(r.note.isEmpty)
  }

  @Test func hidesPassportNumbers() {
    #expect(Redact.sensitive("Passport No.: M12345678 (USA)").text == "Passport No.: [passport number] (USA)")
    #expect(Redact.sensitive("passport number TK1234567").text == "passport number [passport number]")
    #expect(Redact.sensitive("旅券番号：TK1234567").text == "旅券番号：[passport number]")
    #expect(Redact.sensitive("여권번호 M1234567").text == "여권번호 [passport number]")
    // Without the word passport, a code like this is left alone.
    #expect(Redact.sensitive("Seat 12A, gate B12345").text == "Seat 12A, gate B12345")
  }

  @Test func hidesPassportCodeLines() {
    let page = """
      Name: Alex Traveler
      P<USATRAVELER<<ALEX<<<<<<<<<<<<<<<<<<<<<<<<<
      M123456784USA0001023M3001017<<<<<<<<<<<<<<02
      """
    let r = Redact.sensitive(page)
    #expect(r.text == "Name: Alex Traveler\n[passport code line]\n[passport code line]")
    #expect(r.passports == 2)
    #expect(r.note == " · hid 2 passport numbers")
  }

  @Test func luhnCheck() {
    #expect(Redact.luhn("4111111111111111"))
    #expect(!Redact.luhn("4111111111111112"))
  }
}
