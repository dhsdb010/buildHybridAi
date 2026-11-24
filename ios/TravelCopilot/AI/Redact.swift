import Foundation

/// Hides card and passport numbers before text goes to a model. Every prompt passes through
/// here in `AIService`, on both routes, since a hybrid call can fall back to the cloud.
enum Redact {
  struct Result: Equatable {
    var text: String
    var cards = 0
    var passports = 0

    /// For the Routing Log, e.g. " · hid 1 card number".
    var note: String {
      var parts: [String] = []
      if cards > 0 { parts.append("\(cards) card number\(cards == 1 ? "" : "s")") }
      if passports > 0 { parts.append("\(passports) passport number\(passports == 1 ? "" : "s")") }
      return parts.isEmpty ? "" : " · hid " + parts.joined(separator: ", ")
    }
  }

  static func sensitive(_ input: String) -> Result {
    var cards = 0, passports = 0
    var text = replace(mrz, in: input) { _ in passports += 1; return "[passport code line]" }
    text = replace(passport, in: text) { m in passports += 1; return m.prefix + "[passport number]" }
    text = replace(card, in: text) { m in
      let digits = m.whole.filter(\.isNumber)
      guard [15, 16, 19].contains(digits.count), luhn(digits) else { return nil }
      cards += 1
      return "[card ending \(digits.suffix(4))]"
    }
    text = replace(cvc, in: text) { m in m.prefix + "[hidden]" }
    return Result(text: text, cards: cards, passports: passports)
  }

  // MARK: Patterns

  /// 15, 16 or 19 digits, optionally grouped with spaces or dashes; checked with Luhn below.
  /// 13-digit airline ticket numbers and phone numbers don't match.
  private static let card = try! NSRegularExpression(pattern: #"(?<![\d-])\d(?:[ -]?\d){14,18}(?![\d-])"#)

  /// A passport number right after the word "passport" in the languages the app supports.
  private static let passport = try! NSRegularExpression(
    pattern: #"((?:passport|passeport|pasaporte|reisepass|パスポート|旅券|여권|护照|護照)[^\n\dA-Z]{0,20}?(?:no\.?|number|nr\.?|番号|번호|号码|號碼)?[^\n\dA-Z]{0,6})([A-Z]{0,2}\d[A-Z0-9]{5,8})(?![A-Z0-9])"#,
    options: [.caseInsensitive])

  /// The two machine-readable lines at the bottom of a passport photo page.
  private static let mrz = try! NSRegularExpression(
    pattern: #"(?m)^(?=[A-Z0-9<]*<<)[A-Z0-9<]{30,44}$"#)

  /// The 3–4 digit security code after "CVV", "CVC" or "security code".
  private static let cvc = try! NSRegularExpression(
    pattern: #"((?:cvv2?|cvc2?|security code|セキュリティコード|보안코드)[^\n\d]{0,6})(\d{3,4})(?!\d)"#,
    options: [.caseInsensitive])

  // MARK: Helpers

  struct Match { let whole: String; let prefix: String }

  /// Replaces each match with `transform`'s result, or keeps it when that returns nil.
  private static func replace(_ re: NSRegularExpression, in s: String, _ transform: (Match) -> String?) -> String {
    let ns = s as NSString
    var out = ""
    var last = 0
    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
      let whole = ns.substring(with: m.range)
      let prefix = m.numberOfRanges > 2 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
      guard let rep = transform(Match(whole: whole, prefix: prefix)) else { continue }
      out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) + rep
      last = m.range.location + m.range.length
    }
    return out + ns.substring(from: last)
  }

  static func luhn(_ digits: String) -> Bool {
    var sum = 0
    for (i, ch) in digits.reversed().enumerated() {
      guard var d = ch.wholeNumberValue else { return false }
      if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
      sum += d
    }
    return sum % 10 == 0
  }
}
